#!/usr/bin/env bash
# Test dell'ambiente Docker di compatibilità PHP — oc:8834
# Uso: PHP_VERSION=8.4.27 bash tests/test-php-compat-env.sh
# Avvia lo stack con un sito finto, controlla versione, SAPI, estensioni, php.ini e
# isolamento dalla rete, poi lo spegne. Richiede Docker.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../docker/php-compat/compose.yml"
export PHP_VERSION="${PHP_VERSION:-8.4.27}"

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

work=$(mktemp -d)
echo '<?php echo php_sapi_name();' > "$work/sapi.php"
export SITE_WORK="$work" SITE_ROOT=/var/www/html/test.local SITE_NAME=test.local
dc() { docker compose -p oc8834-envtest -f "$COMPOSE_FILE" "$@"; }
cleanup() { dc down -v > /dev/null 2>&1 || true; rm -rf "$work"; }
trap cleanup EXIT

dc up -d --build --wait > /dev/null

test_env_php_version() {
    assert_eq "versione PHP" "$PHP_VERSION" "$(dc exec -T web php -r 'echo PHP_VERSION;')"
}

test_env_sapi_mod_php() {
    assert_eq "SAPI via HTTPS" apache2handler \
        "$(curl -sk --connect-to test.local:443:127.0.0.1:8443 https://test.local/sapi.php)"
}

test_env_extensions() {
    local mods e missing=""
    mods=$(dc exec -T web php -m)
    for e in apcu bz2 curl exif gd gmp intl mbstring mysqli pdo_mysql soap tidy xml xmlrpc xsl zip "Zend OPcache"; do
        grep -qxF "$e" <<< "$mods" || missing="$missing $e"
    done
    assert_eq "estensioni mancanti" "" "${missing# }"
}

test_env_no_internet() {
    local rc=0
    dc exec -T web curl -sS -m 5 -o /dev/null https://wordpress.org > /dev/null 2>&1 || rc=$?
    assert_eq "web non raggiunge internet" fail "$([ "$rc" -ne 0 ] && echo fail || echo ok)"
}

test_env_php_ini_values() {
    assert_eq "php.ini" "1G 50M 50M $(dc exec -T web php -r 'echo E_ALL;')" \
        "$(dc exec -T web php -r 'echo ini_get("memory_limit")," ",ini_get("upload_max_filesize")," ",ini_get("post_max_size")," ",ini_get("error_reporting");')"
}

test_env_php_version
test_env_sapi_mod_php
test_env_extensions
test_env_no_internet
test_env_php_ini_values

exit "$FAIL"
