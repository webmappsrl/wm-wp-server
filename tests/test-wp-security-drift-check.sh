#!/usr/bin/env bash
# GNU grep shim for macOS: ensure -P (PCRE) support
if [ -d "/opt/homebrew/opt/grep/libexec/gnubin" ]; then
    export PATH="/opt/homebrew/opt/grep/libexec/gnubin:$PATH"
fi
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/wp-security-drift-check.sh" --source-only 2>/dev/null || \
source "$SCRIPT_DIR/../scripts/wp-security-drift-check.sh"

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

test_enumerate_sites_finds_two_distinct_docroots() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/sites-enabled"
    cat > "$tmp/sites-enabled/a.conf" <<'EOF'
<VirtualHost *:80>
    ServerName sito-a.it
    DocumentRoot /var/www/html/sito-a.it
</VirtualHost>
EOF
    cat > "$tmp/sites-enabled/b.conf" <<'EOF'
<VirtualHost *:80>
    ServerName sito-b.it
    DocumentRoot /mnt/volume/html/sito-b.it
</VirtualHost>
EOF
    cat > "$tmp/sites-enabled/default.conf" <<'EOF'
<VirtualHost *:80>
    DocumentRoot /var/www/html
</VirtualHost>
EOF
    local out count
    out=$(APACHE_SITES_ENABLED_DIR="$tmp/sites-enabled" enumerate_sites)
    count=$(count_sites "$out")
    assert_eq "trova esattamente 2 siti (esclude il vhost generico)" "2" "$count"
    rm -rf "$tmp"
}

test_enumerate_sites_empty_dir_returns_zero() {
    local tmp
    tmp=$(mktemp -d)
    local out count
    out=$(APACHE_SITES_ENABLED_DIR="$tmp" enumerate_sites)
    count=$(count_sites "$out")
    assert_eq "cartella vuota → 0 siti" "0" "$count"
    rm -rf "$tmp"
}

test_enumerate_sites_multi_space_and_tabs() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/sites-enabled"
    # Test with multiple spaces between directive and value
    cat > "$tmp/sites-enabled/multi-space.conf" <<'EOF'
<VirtualHost *:80>
    ServerName    sito-multi-space.it
    DocumentRoot    /var/www/multi-space.it
</VirtualHost>
EOF
    # Test with tabs between directive and value
    cat > "$tmp/sites-enabled/tab.conf" <<'EOF'
<VirtualHost *:80>
	ServerName	sito-tab.it
	DocumentRoot	/var/www/tab.it
</VirtualHost>
EOF
    local out count
    out=$(APACHE_SITES_ENABLED_DIR="$tmp/sites-enabled" enumerate_sites)
    count=$(count_sites "$out")
    assert_eq "multi-spazio e tab tra direttiva e valore" "2" "$count"
    rm -rf "$tmp"
}

test_check_apache_protection_enabled_detects_missing_mount_path() {
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/no-php-in-writable.conf" <<'EOF'
<DirectoryMatch "^/var/www/html/[^/]+/(wp-content/uploads|images|\.well-known)/">
    php_admin_flag engine off
</DirectoryMatch>
EOF
    local out rc=0
    out=$(check_apache_protection_enabled "$tmp/no-php-in-writable.conf") || rc=$?
    assert_eq "rileva copertura mancante sul volume montato" "1" "$rc"
    rm -rf "$tmp"
}

test_check_apache_protection_enabled_passes_when_both_paths_covered() {
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/no-php-in-writable.conf" <<'EOF'
<DirectoryMatch "^/var/www/html/[^/]+/(wp-content/uploads|images|\.well-known)/">
    php_admin_flag engine off
</DirectoryMatch>
<DirectoryMatch "^/mnt/HC_Volume_102677298/html/[^/]+/(wp-content/uploads|images|\.well-known)/">
    php_admin_flag engine off
</DirectoryMatch>
EOF
    local rc=0
    check_apache_protection_enabled "$tmp/no-php-in-writable.conf" || rc=$?
    assert_eq "passa quando entrambi i path sono coperti" "0" "$rc"
    rm -rf "$tmp"
}

test_check_wp_config_flags_detects_violation() {
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/wp-config.php" <<'EOF'
<?php
define('DISALLOW_FILE_MODS', false);
define('DISALLOW_FILE_EDIT', true);
EOF
    local rc=0
    check_wp_config_flags "$tmp" || rc=$?
    assert_eq "rileva DISALLOW_FILE_MODS=false come violazione" "1" "$rc"
    rm -rf "$tmp"
}

test_check_wp_config_flags_passes_when_both_true() {
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/wp-config.php" <<'EOF'
<?php
define('DISALLOW_FILE_MODS', true);
define('DISALLOW_FILE_EDIT', true);
EOF
    local rc=0
    check_wp_config_flags "$tmp" || rc=$?
    assert_eq "passa quando entrambi i flag sono true" "0" "$rc"
    rm -rf "$tmp"
}

test_check_wp_config_flags_skips_non_wordpress() {
    local tmp
    tmp=$(mktemp -d)
    local rc=0
    check_wp_config_flags "$tmp" || rc=$?
    assert_eq "restituisce 2 se non c'è wp-config.php" "2" "$rc"
    rm -rf "$tmp"
}

test_is_exception_matches_listed_domain() {
    local tmp
    tmp=$(mktemp -d)
    printf 'sito-eccezione.it\n' > "$tmp/exceptions.conf"
    local rc=0
    is_exception "sito-eccezione.it" "$tmp/exceptions.conf" || rc=$?
    assert_eq "riconosce il dominio in eccezione" "0" "$rc"
    rc=0
    is_exception "altro-sito.it" "$tmp/exceptions.conf" || rc=$?
    assert_eq "non segnala un dominio non in lista" "1" "$rc"
    rm -rf "$tmp"
}

test_enumerate_sites_finds_two_distinct_docroots
test_enumerate_sites_empty_dir_returns_zero
test_enumerate_sites_multi_space_and_tabs
test_check_apache_protection_enabled_detects_missing_mount_path
test_check_apache_protection_enabled_passes_when_both_paths_covered
test_check_wp_config_flags_detects_violation
test_check_wp_config_flags_passes_when_both_true
test_check_wp_config_flags_skips_non_wordpress
test_is_exception_matches_listed_domain

exit $FAIL
