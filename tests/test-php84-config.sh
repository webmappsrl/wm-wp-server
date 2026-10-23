#!/usr/bin/env bash
# Test dei file di configurazione apt e PHP 8.4 per il server — oc:8834
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="$SCRIPT_DIR/../config/php8.4"

FAIL=0

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" != "$actual" ]; then
        echo "FAIL: $desc — atteso '$expected', ottenuto '$actual'"
        FAIL=1
    else
        echo "PASS: $desc"
    fi
}

# Blocchi di un file preferences di apt separati da riga vuota, uno per riga
pin_blocks() {
    awk 'BEGIN { RS = ""; FS = "\n" } { gsub(/\n/, " | "); print }' "$1"
}

test_pin_keeps_php81_on_ubuntu() {
    local f="$CFG/apt-preferences-php81-ubuntu" blocks
    blocks=$(pin_blocks "$f")
    assert_eq "pin: 8.1 da Ubuntu con priorità 1001" 1 \
        "$(grep -c 'Package: php8.1\* libapache2-mod-php8.1 | Pin: release o=Ubuntu | Pin-Priority: 1001' <<< "$blocks")"
    assert_eq "pin: 8.1 dal PPA esclusa" 1 \
        "$(grep -c 'Package: php8.1\* libapache2-mod-php8.1 | Pin: release o=LP-PPA-ondrej-php | Pin-Priority: -1' <<< "$blocks")"
}

test_unattended_includes_ppa() {
    local f="$CFG/52unattended-upgrades-ondrej-php"
    assert_eq "unattended: origine del PPA consentita" 1 \
        "$(grep -cE '^[[:space:]]*"origin=LP-PPA-ondrej-php,codename=\$\{distro_codename\}";' "$f")"
    assert_eq "unattended: nessuna Package-Whitelist (è globale, fermerebbe anche Ubuntu)" 0 \
        "$(grep -v '^[[:space:]]*//' "$f" | grep -c 'Package-Whitelist' || true)"
}

test_ini_values_apache() {
    local f="$CFG/99-webmapp-apache2.ini"
    assert_eq "apache2: valori" "memory_limit=1G max_execution_time=60 post_max_size=50M upload_max_filesize=50M display_errors=Off error_reporting=E_ALL & ~E_DEPRECATED & ~E_STRICT" \
        "$(grep -vE '^\s*(;|$)' "$f" | sed 's/[[:space:]]*=[[:space:]]*/=/' | tr '\n' ' ' | sed 's/ $//')"
    assert_eq "apache2: nessuna direttiva session.sid_*" 0 "$(grep -c 'session.sid_' "$f" || true)"
}

test_ini_values_cli() {
    local f="$CFG/99-webmapp-cli.ini"
    assert_eq "cli: valori" "memory_limit=512M" \
        "$(grep -vE '^\s*(;|$)' "$f" | sed 's/[[:space:]]*=[[:space:]]*/=/' | tr '\n' ' ' | sed 's/ $//')"
}

test_pin_keeps_php81_on_ubuntu
test_unattended_includes_ppa
test_ini_values_apache
test_ini_values_cli

exit "$FAIL"
