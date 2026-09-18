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
