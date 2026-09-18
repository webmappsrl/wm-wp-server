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
