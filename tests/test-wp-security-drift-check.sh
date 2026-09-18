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

test_check_ioc_files_detects_php_in_image_extension() {
    local tmp
    tmp=$(mktemp -d)
    printf '<?php system($_GET["c"]); ?>' > "$tmp/logo.png"
    printf '\x89PNG\x0d\x0a\x1a\x0a real image bytes' > "$tmp/clean.png"
    local out count
    out=$(check_ioc_files "$tmp")
    count=$(echo "$out" | grep -c "logo.png" || true)
    assert_eq "rileva PHP embedded in file .png" "1" "$count"
    count=$(echo "$out" | grep -c "clean.png" || true)
    assert_eq "non segnala un'immagine pulita" "0" "$count"
    rm -rf "$tmp"
}

test_check_ioc_files_detects_php_tag_not_at_start() {
    local tmp
    tmp=$(mktemp -d)
    printf 'GIF89a-fake-header-bytes-then <?= system($_GET["c"]); ?>' > "$tmp/anim.gif"
    local out count
    out=$(check_ioc_files "$tmp")
    count=$(echo "$out" | grep -c "anim.gif" || true)
    assert_eq "rileva <?= anche non all'inizio del file" "1" "$count"
    rm -rf "$tmp"
}

test_check_htaccess_detects_known_signature() {
    local tmp
    tmp=$(mktemp -d)
    printf '%s' "$(head -c 32 /dev/zero | tr '\0' 'x')" > "$tmp/.htaccess"
    # forza il contenuto esatto la cui firma md5 conosciamo
    printf 'contenuto-malevolo-noto-oc8547' > "$tmp/.htaccess"
    local known_md5
    known_md5=$(md5sum "$tmp/.htaccess" | cut -d' ' -f1)
    local out count
    out=$(HTACCESS_KNOWN_BAD_MD5="$known_md5" check_htaccess "$tmp")
    count=$(echo "$out" | grep -c "firma nota" || true)
    assert_eq "rileva .htaccess con firma md5 nota" "1" "$count"
    rm -rf "$tmp"
}

test_check_htaccess_detects_php_content() {
    local tmp
    tmp=$(mktemp -d)
    printf 'RewriteEngine On\n<?php eval($_POST["x"]); ?>\n' > "$tmp/.htaccess"
    local out count
    out=$(check_htaccess "$tmp")
    count=$(echo "$out" | grep -c "sospetto" || true)
    assert_eq "rileva .htaccess con contenuto PHP" "1" "$count"
    rm -rf "$tmp"
}

test_check_index_integrity_flags_core_mismatch() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-admin"
    printf '<?php /* modificato da un attacco */ ?>' > "$tmp/wp-admin/index.php"
    local checksums_json='{"checksums":{"wp-admin/index.php":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}'
    local out count
    out=$(check_index_integrity "$tmp" "$checksums_json" "/dev/null")
    count=$(echo "$out" | grep -c "ANOMALIA" || true)
    assert_eq "rileva index.php core che non combacia col checksum ufficiale" "1" "$count"
    rm -rf "$tmp"
}

test_check_index_integrity_passes_core_match() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-admin"
    printf 'contenuto-originale' > "$tmp/wp-admin/index.php"
    local real_md5 checksums_json out count
    real_md5=$(md5sum "$tmp/wp-admin/index.php" | cut -d' ' -f1)
    checksums_json="{\"checksums\":{\"wp-admin/index.php\":\"$real_md5\"}}"
    out=$(check_index_integrity "$tmp" "$checksums_json" "/dev/null")
    count=$(echo "$out" | wc -l | tr -d ' ')
    [ -z "$out" ] && count=0
    assert_eq "nessuna anomalia quando l'hash combacia col core" "0" "$count"
    rm -rf "$tmp"
}

test_check_index_integrity_recognizes_boilerplate() {
    local tmp boilerplate
    tmp=$(mktemp -d)
    boilerplate=$(mktemp)
    printf '<?php\n// Silence is golden.\n' > "$tmp/index.php"
    md5sum "$tmp/index.php" | cut -d' ' -f1 > "$boilerplate"
    local checksums_json='{"checksums":{}}'
    local out
    out=$(check_index_integrity "$tmp" "$checksums_json" "$boilerplate")
    assert_eq "boilerplate nota non genera output" "" "$out"
    rm -rf "$tmp" "$boilerplate"
}

test_check_index_integrity_flags_unrecognized_file() {
    local tmp
    tmp=$(mktemp -d)
    printf '<?php echo "contenuto mai visto prima"; ?>' > "$tmp/index.php"
    local checksums_json='{"checksums":{}}'
    local out count
    out=$(check_index_integrity "$tmp" "$checksums_json" "/dev/null")
    count=$(echo "$out" | grep -c "DA_RIVEDERE" || true)
    assert_eq "segnala per revisione un file non riconosciuto" "1" "$count"
    rm -rf "$tmp"
}

test_baseline_diff_shows_new_files_when_no_baseline_exists() {
    local tmp candidates
    tmp=$(mktemp -d)
    candidates="$tmp/candidates.tsv"
    printf 'index.php\tabc123\n' > "$candidates"
    local out count
    out=$(baseline_diff "$candidates" "$tmp/nonexistent-baseline.tsv")
    count=$(echo "$out" | grep -c "abc123" || true)
    assert_eq "mostra i candidati come nuovi quando non c'è baseline" "1" "$count"
    rm -rf "$tmp"
}

test_baseline_write_persists_candidates() {
    local tmp candidates baseline
    tmp=$(mktemp -d)
    candidates="$tmp/candidates.tsv"
    baseline="$tmp/baseline.tsv"
    printf 'index.php\tabc123\n' > "$candidates"
    baseline_write "$candidates" "$baseline"
    local content
    content=$(cat "$baseline")
    assert_eq "la baseline scritta corrisponde ai candidati" "$(cat "$candidates")" "$content"
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
test_check_ioc_files_detects_php_in_image_extension
test_check_ioc_files_detects_php_tag_not_at_start
test_check_htaccess_detects_known_signature
test_check_htaccess_detects_php_content
test_check_index_integrity_flags_core_mismatch
test_check_index_integrity_passes_core_match
test_check_index_integrity_recognizes_boilerplate
test_check_index_integrity_flags_unrecognized_file
test_baseline_diff_shows_new_files_when_no_baseline_exists
test_baseline_write_persists_candidates

exit $FAIL
