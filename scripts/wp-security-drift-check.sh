#!/usr/bin/env bash
# wp-security-drift-check.sh
# Controllo periodico drift protezioni anti-malware — oc:8558
set -uo pipefail

APACHE_SITES_ENABLED_DIR="${APACHE_SITES_ENABLED_DIR:-/etc/apache2/sites-enabled}"

enumerate_sites() {
    local conf_dir="$APACHE_SITES_ENABLED_DIR"
    local -A seen_roots
    local conf domain root

    for conf in "$conf_dir"/*.conf; do
        [ -f "$conf" ] || continue
        domain=$(grep -m1 -oP 'ServerName\s+\K\S+' "$conf" 2>/dev/null)
        while IFS= read -r root; do
            root=$(echo "$root" | xargs)
            [ -z "$root" ] && continue
            [ "$root" = "/var/www/html" ] && continue
            if [ -z "${seen_roots[$root]:-}" ]; then
                seen_roots[$root]=1
                echo "${domain:-unknown}|$root"
            fi
        done < <(grep -oP 'DocumentRoot\s+\K\S+' "$conf" 2>/dev/null)
    done
}

count_sites() {
    local sites_output="$1"
    if [ -z "$sites_output" ]; then
        echo 0
        return
    fi
    echo "$sites_output" | grep -c '|'
}

check_apache_protection_enabled() {
    local conf="$1"
    [ -f "$conf" ] || { echo "MANCANTE: file di configurazione assente ($conf)"; return 1; }
    if grep -q '/var/www/html' "$conf" && grep -q '/mnt/HC_Volume_102677298/html' "$conf"; then
        return 0
    fi
    echo "VIOLAZIONE: la regola anti-exec-PHP non copre entrambi i DocumentRoot ($conf)"
    return 1
}

check_wp_config_flags() {
    local docroot="$1"
    local wpconfig="$docroot/wp-config.php"
    [ -f "$wpconfig" ] || return 2

    local mods edit
    mods=$(grep -oP "define\(\s*['\"]DISALLOW_FILE_MODS['\"]\s*,\s*\K(true|false)" "$wpconfig" 2>/dev/null)
    edit=$(grep -oP "define\(\s*['\"]DISALLOW_FILE_EDIT['\"]\s*,\s*\K(true|false)" "$wpconfig" 2>/dev/null)

    if [ "$mods" = "true" ] && [ "$edit" = "true" ]; then
        return 0
    fi
    echo "VIOLAZIONE: DISALLOW_FILE_MODS=${mods:-assente} DISALLOW_FILE_EDIT=${edit:-assente} in $wpconfig"
    return 1
}

is_exception() {
    local domain="$1"
    local exceptions_file="$2"
    [ -f "$exceptions_file" ] || return 1
    grep -qxF "$domain" "$exceptions_file"
}

IOC_EXTENSIONS="jpg jpeg png gif ico wav mp4 wmv jpc avi ttf css svg"
HTACCESS_KNOWN_BAD_MD5="${HTACCESS_KNOWN_BAD_MD5:-ee7f30053bde324521dd69e117781ad3}"

check_ioc_files() {
    local docroot="$1"
    local ext f
    for ext in $IOC_EXTENSIONS; do
        while IFS= read -r -d '' f; do
            if head -c 4096 "$f" 2>/dev/null | grep -qE '<\?php|<\?='; then
                echo "IOC: $f contiene un tag PHP nonostante l'estensione .$ext"
            fi
        done < <(find "$docroot" -type f -iname "*.$ext" -print0 2>/dev/null)
    done
}

check_htaccess() {
    local docroot="$1"
    local f sum
    while IFS= read -r -d '' f; do
        sum=$(md5sum "$f" | cut -d' ' -f1)
        if [ "$sum" = "$HTACCESS_KNOWN_BAD_MD5" ]; then
            echo "IOC: $f corrisponde alla firma nota di oc:8547"
        elif grep -qE '<\?php|<\?=' "$f" 2>/dev/null; then
            echo "IOC: $f è sospetto (contenuto PHP in un .htaccess)"
        fi
    done < <(find "$docroot" -type f -name ".htaccess" -print0 2>/dev/null)
}

get_wp_version() {
    local docroot="$1"
    grep -oP '(?<=\$wp_version = '"'"')[^'"'"']+' "$docroot/wp-includes/version.php" 2>/dev/null
}

fetch_core_checksums() {
    local version="$1"
    curl -s "https://api.wordpress.org/core/checksums/1.0/?version=${version}&locale=en_US"
}

check_index_integrity() {
    local docroot="$1"
    local checksums_json="$2"
    local boilerplate_file="$3"
    local f relpath md5 corehash

    while IFS= read -r -d '' f; do
        relpath="${f#$docroot/}"
        md5=$(md5sum "$f" | cut -d' ' -f1)

        corehash=$(echo "$checksums_json" | jq -r --arg p "$relpath" '.checksums[$p] // empty' 2>/dev/null)
        if [ -n "$corehash" ]; then
            [ "$md5" = "$corehash" ] && continue
            echo "ANOMALIA: $f non combacia col checksum core WordPress ($relpath)"
            continue
        fi

        if [ -f "$boilerplate_file" ] && grep -qxF "$md5" "$boilerplate_file"; then
            continue
        fi

        echo "DA_RIVEDERE: $f non riconosciuto (né core né boilerplate nota)"
    done < <(find "$docroot" -type f -name "index.php" -print0 2>/dev/null)
}

baseline_diff() {
    local candidates_file="$1"
    local baseline_file="$2"
    if [ -f "$baseline_file" ]; then
        diff "$baseline_file" "$candidates_file" || true
    else
        cat "$candidates_file"
    fi
}

baseline_write() {
    local candidates_file="$1"
    local baseline_file="$2"
    mkdir -p "$(dirname "$baseline_file")"
    cp "$candidates_file" "$baseline_file"
}

send_slack_alert() {
    local message="$1"
    local webhook_url="$2"
    [ -z "$webhook_url" ] && { echo "ERRORE: webhook Slack non configurato"; return 1; }

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H 'Content-type: application/json' \
        --data "$(jq -n --arg text "$message" '{text: $text}')" \
        "$webhook_url")

    if [ "$http_code" != "200" ]; then
        echo "ERRORE: invio Slack fallito, HTTP $http_code"
        return 1
    fi
    return 0
}

should_notify() {
    local anomaly_id="$1"
    local state_file="$2"
    local reminder_interval="$3"
    local now="$4"

    mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
    touch "$state_file"

    local line last_notified first_seen
    line=$(grep -F "${anomaly_id}"$'\t' "$state_file" || true)
    if [ -z "$line" ]; then
        echo -e "${anomaly_id}\t${now}\t${now}" >> "$state_file"
        return 0
    fi

    first_seen=$(echo "$line" | cut -f2)
    last_notified=$(echo "$line" | cut -f3)
    if [ $((now - last_notified)) -ge "$reminder_interval" ]; then
        local tmp_state
        tmp_state=$(mktemp)
        grep -vF "${anomaly_id}"$'\t' "$state_file" > "$tmp_state" || true
        echo -e "${anomaly_id}\t${first_seen}\t${now}" >> "$tmp_state"
        mv "$tmp_state" "$state_file"
        return 0
    fi
    return 1
}

clear_resolved() {
    local anomaly_id="$1"
    local state_file="$2"
    [ -f "$state_file" ] || return 0
    local tmp_state
    tmp_state=$(mktemp)
    grep -vF "${anomaly_id}"$'\t' "$state_file" > "$tmp_state" || true
    mv "$tmp_state" "$state_file"
}
