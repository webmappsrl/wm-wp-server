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
    curl -s --max-time 10 "https://api.wordpress.org/core/checksums/1.0/?version=${version}&locale=en_US"
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
    http_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST -H 'Content-type: application/json' \
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

    mkdir -p "$(dirname "$state_file")" 2>/dev/null || true
    touch "$state_file"

    if grep -qF "${anomaly_id}"$'\t' "$state_file" 2>/dev/null; then
        # Già presente nello stato: già notificata una volta, resta aperta. Niente reminder.
        return 1
    fi

    echo -e "${anomaly_id}\tnotificata" >> "$state_file"
    return 0
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

with_lock() {
    local lockfile="$1"; shift
    local fn="$1"; shift
    if [ -e "$lockfile" ]; then
        return 1
    fi
    touch "$lockfile"
    "$fn" "$@"
    local rc=$?
    rm -f "$lockfile"
    return $rc
}

LOCKFILE="${LOCKFILE:-/tmp/wp-security-drift-check.lock}"
LOG_FILE="${LOG_FILE:-/var/log/wp-security-drift-check.log}"
STATE_FILE="${STATE_FILE:-/root/state/wp-security-drift-state.tsv}"
BASELINE_FILE="${BASELINE_FILE:-/root/state/wp-security-index-baseline.tsv}"
HEARTBEAT_FILE="${HEARTBEAT_FILE:-/root/state/wp-security-drift-heartbeat}"
EXCEPTIONS_FILE="${EXCEPTIONS_FILE:-/root/config/disallow-exceptions.conf}"
BOILERPLATE_FILE="${BOILERPLATE_FILE:-/root/config/index-boilerplate-whitelist.txt}"
NO_PHP_CONF="${NO_PHP_CONF:-/etc/apache2/conf-available/no-php-in-writable.conf}"
SLACK_WEBHOOK_URL_FILE="${SLACK_WEBHOOK_URL_FILE:-/root/.wp-security-slack-webhook}"
# In produzione è sempre https; override consentito solo per i test (mock server locale in http).
HOMEPAGE_SCHEME="${HOMEPAGE_SCHEME:-https}"

log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "$(date '+%F %T') - $1" >> "$LOG_FILE"
}

run_check() {
    local name="$1"; shift
    local output
    output=$("$@" 2>&1) || true
    if [ -n "$output" ]; then
        echo "$output"
    fi
}

main() {
    local sites site_count
    local anomaly_domains=() anomaly_checks=() anomaly_details=()

    sites=$(enumerate_sites)
    site_count=$(count_sites "$sites")

    if [ "$site_count" -lt 1 ]; then
        anomaly_domains+=("enumerazione")
        anomaly_checks+=("enumerazione-siti")
        anomaly_details+=("0 siti trovati — possibile bug nel parsing dei vhost, nessun controllo eseguito")
    fi

    local domain docroot
    while IFS='|' read -r domain docroot; do
        [ -z "$docroot" ] && continue
        is_exception "$domain" "$EXCEPTIONS_FILE" && continue

        local out
        out=$(run_check "apache-rule" check_apache_protection_enabled "$NO_PHP_CONF")
        if [ -n "$out" ]; then
            anomaly_domains+=("$domain"); anomaly_checks+=("apache-rule"); anomaly_details+=("$out")
        else
            clear_resolved "$domain:apache-rule" "$STATE_FILE"
        fi

        out=$(run_check "wp-config" check_wp_config_flags "$docroot")
        if [ -n "$out" ]; then
            anomaly_domains+=("$domain"); anomaly_checks+=("wp-config"); anomaly_details+=("$out")
        else
            clear_resolved "$domain:wp-config" "$STATE_FILE"
        fi

        out=$(run_check "ioc-files" check_ioc_files "$docroot")
        if [ -n "$out" ]; then
            anomaly_domains+=("$domain"); anomaly_checks+=("ioc-files"); anomaly_details+=("$out")
        else
            clear_resolved "$domain:ioc-files" "$STATE_FILE"
        fi

        out=$(run_check "htaccess" check_htaccess "$docroot")
        if [ -n "$out" ]; then
            anomaly_domains+=("$domain"); anomaly_checks+=("htaccess"); anomaly_details+=("$out")
        else
            clear_resolved "$domain:htaccess" "$STATE_FILE"
        fi

        out=$(run_check "uploads-php" check_unexpected_php_in_uploads "$docroot")
        if [ -n "$out" ]; then
            anomaly_domains+=("$domain"); anomaly_checks+=("uploads-php"); anomaly_details+=("$out")
        else
            clear_resolved "$domain:uploads-php" "$STATE_FILE"
        fi

        # A differenza degli altri check, questo non legge il filesystem (docroot) ma fa una
        # fetch HTTP live della homepage pubblica: prende $domain, non $docroot.
        out=$(run_check "homepage-redirect" check_homepage_redirect "$domain")
        if [ -n "$out" ]; then
            anomaly_domains+=("$domain"); anomaly_checks+=("homepage-redirect"); anomaly_details+=("$out")
        else
            clear_resolved "$domain:homepage-redirect" "$STATE_FILE"
        fi

        local wp_version checksums_json
        wp_version=$(get_wp_version "$docroot")
        if [ -n "$wp_version" ]; then
            checksums_json=$(fetch_core_checksums "$wp_version")
            out=$(run_check "index-integrity" check_index_integrity "$docroot" "$checksums_json" "$BOILERPLATE_FILE")
            if [ -n "$out" ]; then
                anomaly_domains+=("$domain"); anomaly_checks+=("index-integrity"); anomaly_details+=("$out")
            else
                # Check eseguito davvero e risultato pulito: possiamo pulire un'anomalia precedente.
                clear_resolved "$domain:index-integrity" "$STATE_FILE"
            fi
        fi
        # Se wp_version non è determinabile, il check non è stato eseguito: non tocchiamo
        # lo stato di index-integrity, perché l'assenza di esecuzione non dice nulla sulla
        # risoluzione di un'anomalia precedente.
    done <<< "$sites"

    local webhook_url=""
    [ -f "$SLACK_WEBHOOK_URL_FILE" ] && webhook_url=$(cat "$SLACK_WEBHOOK_URL_FILE")

    local i anomaly_domain anomaly_check anomaly_detail anomaly_id anomaly_count log_line slack_message
    for i in "${!anomaly_domains[@]}"; do
        anomaly_domain="${anomaly_domains[$i]}"
        anomaly_check="${anomaly_checks[$i]}"
        anomaly_detail="${anomaly_details[$i]}"

        # Il log riceve il dettaglio completo (tutti i path); Slack riceve solo il conteggio.
        log_line="[$anomaly_domain] $anomaly_check: $anomaly_detail"
        anomaly_count=$(printf '%s\n' "$anomaly_detail" | grep -c .)

        # L'anomaly_id NON dipende dal contenuto (i path possono cambiare run dopo run):
        # dipende solo da sito+tipo di check, così should_notify/clear_resolved tracciano lo
        # stesso stato anche se cambia il singolo file nell'elenco delle anomalie rilevate.
        anomaly_id="${anomaly_domain}:${anomaly_check}"

        log "$log_line"
        if should_notify "$anomaly_id" "$STATE_FILE"; then
            slack_message="[$anomaly_domain] ${anomaly_check}: ${anomaly_count} anomalie rilevate — vedi log su wordpress-php8:/var/log/wp-security-drift-check.log"
            send_slack_alert "$slack_message" "$webhook_url" || log "invio Slack fallito per: $log_line"
        fi
    done

    mkdir -p "$(dirname "$HEARTBEAT_FILE")" 2>/dev/null || true
    date +%s > "$HEARTBEAT_FILE"
}

check_unexpected_php_in_uploads() {
    local docroot="$1"
    local uploads_dir="$docroot/wp-content/uploads"
    [ -d "$uploads_dir" ] || return 0

    local boilerplate_file="${BOILERPLATE_FILE:-config/index-boilerplate-whitelist.txt}"
    local f relpath base md5

    while IFS= read -r -d '' f; do
        relpath="${f#$uploads_dir/}"
        base="$(basename "$f")"

        case "/$relpath" in
            */cache/wpml/twig/*) continue ;;
            */sucuri/*) continue ;;
            */wpforms/cache/*) continue ;;
        esac

        case "$base" in
            charmap.php) continue ;;
            debug-log.php)
                if head -c 20 "$f" 2>/dev/null | grep -qE '^<\?php exit'; then
                    continue
                fi
                ;;
            index.php)
                md5=$(md5sum "$f" | cut -d' ' -f1)
                if [ -f "$boilerplate_file" ] && grep -qxF "$md5" "$boilerplate_file"; then
                    continue
                fi
                ;;
        esac

        echo "IOC: $f — file .php/.phtml/.phar inaspettato in uploads/ (non in whitelist nota)"
    done < <(find "$uploads_dir" -type f \( -iname "*.php" -o -iname "*.phtml" -o -iname "*.phar" \) -print0 2>/dev/null)
}

# Firme note dalla campagna attiva oc:8547/oc:8558 (già catalogate nel vecchio cron script
# che questo progetto sostituisce), viste verbatim nell'attacco reale su valdicecinaoutdoor.it.
HOMEPAGE_KNOWN_BAD_SIGNATURES=("ushort.company" "Briefly unavailable for scheduled maintenance")

check_homepage_redirect() {
    local domain="$1"
    local html
    # "|| true" (stesso idioma di run_check/baseline_diff/clear_resolved): un curl fallito
    # (timeout, connection refused, ecc.) non deve interrompere lo script sotto set -e — è
    # gestito subito sotto come "nessun body ricevuto", non come un errore.
    html=$(curl -sS --max-time 10 -A 'Mozilla/5.0 (compatible; wp-security-drift-check)' \
        "${HOMEPAGE_SCHEME}://${domain}/" 2>/dev/null) || true

    # Homepage irraggiungibile/vuota (timeout, connection refused, nessun body): non è la stessa
    # cosa di "trovato malware" — questo check non è un uptime monitor, esce pulito senza output.
    [ -z "$html" ] && return 0

    local sig
    for sig in "${HOMEPAGE_KNOWN_BAD_SIGNATURES[@]}"; do
        if grep -qF -- "$sig" <<< "$html"; then
            echo "IOC: homepage di $domain contiene la firma nota '$sig' (oc:8547/oc:8558)"
        fi
    done

    local redirect_pattern
    redirect_pattern="location\.replace\([^)]*\)"
    redirect_pattern+="|location\.href[[:space:]]*=[[:space:]]*[^;]*"
    redirect_pattern+="|<meta[^>]*http-equiv=[\"']?refresh[\"']?[^>]*>"

    local match
    while IFS= read -r match; do
        [ -z "$match" ] && continue
        # Flag solo se il target del redirect NON contiene il dominio del sito stesso
        # (case-insensitive): un redirect interno (stesso dominio) non è un'anomalia.
        if ! grep -qiF -- "$domain" <<< "$match"; then
            echo "IOC: homepage di $domain contiene un redirect client-side verso un dominio esterno: $match"
        fi
    done < <(grep -oE "$redirect_pattern" <<< "$html" 2>/dev/null)

    return 0
}

if [[ "${1:-}" != "--source-only" ]]; then
    with_lock "$LOCKFILE" main
fi
