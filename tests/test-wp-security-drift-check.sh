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

test_check_unexpected_php_in_uploads_flags_unexpected_php() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-content/uploads"
    printf '<?php system($_GET["c"]); ?>' > "$tmp/wp-content/uploads/shell.php"
    local out count
    out=$(BOILERPLATE_FILE=/dev/null check_unexpected_php_in_uploads "$tmp")
    count=$(echo "$out" | grep -c "shell.php" || true)
    assert_eq "rileva file .php inaspettato in uploads/" "1" "$count"
    rm -rf "$tmp"
}

test_check_unexpected_php_in_uploads_skips_wpml_twig_cache() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-content/uploads/cache/wpml/twig"
    printf '<?php // twig cache ?>' > "$tmp/wp-content/uploads/cache/wpml/twig/abc123.php"
    local out
    out=$(BOILERPLATE_FILE=/dev/null check_unexpected_php_in_uploads "$tmp")
    assert_eq "non segnala file in cache/wpml/twig/ (whitelist nota)" "" "$out"
    rm -rf "$tmp"
}

test_check_unexpected_php_in_uploads_skips_sucuri() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-content/uploads/sucuri"
    printf '<?php // dati sucuri ?>' > "$tmp/wp-content/uploads/sucuri/sucuri-datastore.php"
    local out
    out=$(BOILERPLATE_FILE=/dev/null check_unexpected_php_in_uploads "$tmp")
    assert_eq "non segnala file in sucuri/ (whitelist nota)" "" "$out"
    rm -rf "$tmp"
}

test_check_unexpected_php_in_uploads_skips_charmap() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-content/uploads/fonts/some-font"
    printf '<?php // charmap ?>' > "$tmp/wp-content/uploads/fonts/some-font/charmap.php"
    local out
    out=$(BOILERPLATE_FILE=/dev/null check_unexpected_php_in_uploads "$tmp")
    assert_eq "non segnala charmap.php (whitelist nota)" "" "$out"
    rm -rf "$tmp"
}

test_check_unexpected_php_in_uploads_missing_uploads_dir() {
    local tmp
    tmp=$(mktemp -d)
    local out rc=0
    out=$(BOILERPLATE_FILE=/dev/null check_unexpected_php_in_uploads "$tmp") || rc=$?
    assert_eq "nessun errore se uploads/ non esiste" "0" "$rc"
    assert_eq "nessun output se uploads/ non esiste" "" "$out"
    rm -rf "$tmp"
}

test_check_unexpected_php_in_uploads_skips_whitelisted_index() {
    local tmp boilerplate
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-content/uploads"
    boilerplate=$(mktemp)
    printf '<?php\n// Silence is golden.\n' > "$tmp/wp-content/uploads/index.php"
    md5sum "$tmp/wp-content/uploads/index.php" | cut -d' ' -f1 > "$boilerplate"
    local out
    out=$(BOILERPLATE_FILE="$boilerplate" check_unexpected_php_in_uploads "$tmp")
    assert_eq "index.php boilerplate in uploads/ non genera output" "" "$out"
    rm -rf "$tmp" "$boilerplate"
}

test_check_unexpected_php_in_uploads_skips_nested_sucuri() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-content/uploads/sites/2/sucuri"
    printf '<?php // nested sucuri datastore ?>' > "$tmp/wp-content/uploads/sites/2/sucuri/datastore.php"
    local out
    out=$(BOILERPLATE_FILE=/dev/null check_unexpected_php_in_uploads "$tmp")
    assert_eq "non segnala file in sucuri/ anche se annidato (multisite)" "" "$out"
    rm -rf "$tmp"
}

test_check_unexpected_php_in_uploads_skips_nested_wpforms_cache() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-content/uploads/sites/2/wpforms/cache"
    printf '<?php // wpforms cache ?>' > "$tmp/wp-content/uploads/sites/2/wpforms/cache/form123.php"
    local out
    out=$(BOILERPLATE_FILE=/dev/null check_unexpected_php_in_uploads "$tmp")
    assert_eq "non segnala file in wpforms/cache/ anche se annidato" "" "$out"
    rm -rf "$tmp"
}

test_check_unexpected_php_in_uploads_skips_debug_log_php_with_mailchimp_pattern() {
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/wp-content/uploads"
    printf '<?php exit;' > "$tmp/wp-content/uploads/debug-log.php"
    local out
    out=$(BOILERPLATE_FILE=/dev/null check_unexpected_php_in_uploads "$tmp")
    assert_eq "non segnala debug-log.php con pattern Mailchimp" "" "$out"
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

start_mock_http_server() {
    local port="$1" status_code="$2"
    python3 -c "
import http.server, socketserver
socketserver.TCPServer.allow_reuse_address = True
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.send_response($status_code)
        self.end_headers()
    def log_message(self, *args): pass
with socketserver.TCPServer(('127.0.0.1', $port), Handler) as httpd:
    httpd.timeout = 10
    httpd.handle_request()
" >/dev/null 2>&1 &
    local pid=$!
    echo "$pid"
}

start_mock_html_server() {
    local port="$1" content_file="$2"
    python3 -c "
import http.server, socketserver
socketserver.TCPServer.allow_reuse_address = True
with open('$content_file', 'rb') as f:
    BODY = f.read()
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(BODY)
    def log_message(self, *args): pass
with socketserver.TCPServer(('127.0.0.1', $port), Handler) as httpd:
    httpd.timeout = 10
    httpd.handle_request()
" >/dev/null 2>&1 &
    local pid=$!
    echo "$pid"
}

test_check_homepage_redirect_detects_ushort_company_signature() {
    local tmp html_file port pid rc=0 out count
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    printf '<html><body>Contenuto normale, ushort.company nel testo</body></html>' > "$html_file"
    port=18090
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    count=$(printf '%s\n' "$out" | grep -c "IOC" || true)
    assert_eq "rileva la firma nota ushort.company (oc:8547/oc:8558)" "1" "$count"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_check_homepage_redirect_detects_maintenance_signature() {
    local tmp html_file port pid rc=0 out count
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    printf '<html><body>Briefly unavailable for scheduled maintenance</body></html>' > "$html_file"
    port=18091
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    count=$(printf '%s\n' "$out" | grep -c "IOC" || true)
    assert_eq "rileva la firma nota 'Briefly unavailable for scheduled maintenance'" "1" "$count"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_check_homepage_redirect_flags_external_redirect() {
    local tmp html_file port pid rc=0 out count
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    printf '<html><script>location.replace("//some-completely-different-domain.evil/x");</script></html>' > "$html_file"
    port=18092
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    count=$(printf '%s\n' "$out" | grep -c "dominio esterno" || true)
    assert_eq "rileva redirect client-side verso un dominio diverso dal proprio" "1" "$count"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_check_homepage_redirect_ignores_internal_redirect() {
    local tmp html_file port pid rc=0 out
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    port=18093
    printf '<html><script>location.href = "https://127.0.0.1:%s/some-page";</script></html>' "$port" > "$html_file"
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    assert_eq "non segnala un redirect verso il proprio stesso dominio (navigazione interna)" "" "$out"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_check_homepage_redirect_clean_homepage_no_anomaly() {
    local tmp html_file port pid rc=0 out
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    printf '<html><body>Homepage pulita, nessuna anomalia</body></html>' > "$html_file"
    port=18094
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    assert_eq "homepage pulita non genera output" "" "$out"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_check_homepage_redirect_unreachable_site_returns_cleanly() {
    local rc=0 out
    out=$(check_homepage_redirect "127.0.0.1:1") || rc=$?
    assert_eq "sito irraggiungibile: nessun errore" "0" "$rc"
    assert_eq "sito irraggiungibile: nessun output (non è un uptime monitor)" "" "$out"
}

test_check_homepage_redirect_detects_real_attack_string() {
    local tmp html_file port pid rc=0 out sig_count redirect_count
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    # Stringa reale trovata oggi in wp-admin/index.php su valdicecinaoutdoor.it (oc:8547/oc:8558)
    printf '%s' 'location.replace("//ushort.company/pxCXpSDmu0r6")' > "$html_file"
    port=18095
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    sig_count=$(printf '%s\n' "$out" | grep -c "firma nota 'ushort.company'" || true)
    redirect_count=$(printf '%s\n' "$out" | grep -c "dominio esterno" || true)
    assert_eq "la stringa reale dell'attacco viene riconosciuta come firma nota" "1" "$sig_count"
    assert_eq "la stringa reale dell'attacco viene riconosciuta anche come redirect esterno" "1" "$redirect_count"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_send_slack_alert_returns_success_on_http_200() {
    local port=18080 pid rc=0
    pid=$(start_mock_http_server "$port" 200)
    sleep 2
    send_slack_alert "messaggio di test" "http://127.0.0.1:$port/webhook" || rc=$?
    assert_eq "successo quando il webhook risponde 200" "0" "$rc"
    wait "$pid" 2>/dev/null || true
}

test_send_slack_alert_returns_failure_on_http_500() {
    local port=18081 pid rc=0
    pid=$(start_mock_http_server "$port" 500)
    sleep 2
    send_slack_alert "messaggio di test" "http://127.0.0.1:$port/webhook" || rc=$?
    assert_eq "fallimento quando il webhook risponde 500" "1" "$rc"
    wait "$pid" 2>/dev/null || true
}

test_send_slack_alert_returns_failure_on_http_404() {
    local port=18082 pid rc=0
    pid=$(start_mock_http_server "$port" 404)
    sleep 2
    send_slack_alert "messaggio di test" "http://127.0.0.1:$port/webhook" || rc=$?
    assert_eq "fallimento quando il canale/webhook non è più valido (404)" "1" "$rc"
    wait "$pid" 2>/dev/null || true
}

test_send_slack_alert_fails_when_webhook_not_configured() {
    local rc=0
    send_slack_alert "messaggio di test" "" || rc=$?
    assert_eq "fallisce subito se il webhook non è configurato" "1" "$rc"
}

test_should_notify_true_for_new_anomaly() {
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    local rc=0
    should_notify "anomaly-1" "$state" || rc=$?
    assert_eq "notifica sempre una nuova anomalia" "0" "$rc"
    rm -rf "$tmp"
}

test_should_notify_only_once_while_anomaly_stays_open() {
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    local rc=0
    should_notify "anomaly-1" "$state" || rc=$?
    assert_eq "notifica la prima volta" "0" "$rc"
    rc=0
    should_notify "anomaly-1" "$state" || rc=$?
    assert_eq "non rinotifica una seconda volta senza clear_resolved, indipendentemente dal tempo trascorso" "1" "$rc"
    rm -rf "$tmp"
}

test_clear_resolved_removes_entry() {
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    should_notify "anomaly-1" "$state" >/dev/null
    clear_resolved "anomaly-1" "$state"
    local count
    count=$(grep -c "anomaly-1" "$state" 2>/dev/null || true)
    assert_eq "l'anomalia risolta viene rimossa dallo stato" "0" "$count"
    rm -rf "$tmp"
}

test_should_notify_true_again_after_clear_resolved() {
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    should_notify "anomaly-1" "$state" >/dev/null
    clear_resolved "anomaly-1" "$state"
    local rc=0
    should_notify "anomaly-1" "$state" || rc=$?
    assert_eq "rinotifica come nuova occorrenza dopo clear_resolved" "0" "$rc"
    rm -rf "$tmp"
}

test_should_notify_not_suppressed_by_suffix_domain_entry() {
    # Regression oc:8558: "maremma.it:htaccess" è suffisso di "parco-maremma.it:htaccess".
    # Con grep -qF (senza -x) la riga esistente per il dominio più lungo faceva match anche
    # per il dominio più corto/distinto, sopprimendo erroneamente una nuova anomalia.
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    printf 'parco-maremma.it:htaccess\tnotificata\n' > "$state"
    local rc=0
    should_notify "maremma.it:htaccess" "$state" || rc=$?
    assert_eq "anomalia di un dominio suffisso non viene soppressa da un'entry di un dominio più lungo" "0" "$rc"
    rm -rf "$tmp"
}

test_clear_resolved_does_not_remove_longer_domain_entry() {
    # Regression oc:8558: clear_resolved su "maremma.it:htaccess" non deve rimuovere l'entry
    # di "parco-maremma.it:htaccess" (falso match per sottostringa con grep -vF senza -x).
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    printf 'parco-maremma.it:htaccess\tnotificata\n' > "$state"
    clear_resolved "maremma.it:htaccess" "$state"
    local rc=0
    grep -qxF "parco-maremma.it:htaccess"$'\t'"notificata" "$state" || rc=$?
    assert_eq "l'entry del dominio più lungo resta nello stato dopo clear_resolved sul suffisso" "0" "$rc"
    rm -rf "$tmp"
}

test_with_lock_prevents_concurrent_execution() {
    local tmp lockfile
    tmp=$(mktemp -d)
    lockfile="$tmp/test.lock"
    touch "$lockfile"

    noop() { echo "eseguito"; }
    local out rc=0
    out=$(with_lock "$lockfile" noop) || rc=$?
    assert_eq "with_lock non esegue se il lock è già preso" "1" "$rc"
    rm -rf "$tmp"
}

test_with_lock_runs_and_releases_when_free() {
    local tmp lockfile
    tmp=$(mktemp -d)
    lockfile="$tmp/test.lock"

    noop() { echo "eseguito"; }
    local out
    out=$(with_lock "$lockfile" noop)
    assert_eq "with_lock esegue la funzione quando libero" "eseguito" "$out"
    assert_eq "il lock viene rilasciato dopo l'esecuzione" "false" "$([ -e "$lockfile" ] && echo true || echo false)"
    rm -rf "$tmp"
}

test_run_check_forwards_stdout_with_nonzero_return() {
    fake_check_violation() {
        echo "VIOLAZIONE: qualcosa non va"
        return 1
    }
    local out
    out=$(run_check "fake-check" fake_check_violation)
    assert_eq "run_check inoltra stdout anche con return non-zero" "VIOLAZIONE: qualcosa non va" "$out"
}

test_run_check_empty_output_with_zero_return() {
    fake_check_clean() {
        return 0
    }
    local out
    out=$(run_check "fake-check-clean" fake_check_clean)
    assert_eq "run_check non produce output per check pulito (return 0, no stdout)" "" "$out"
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
test_check_unexpected_php_in_uploads_flags_unexpected_php
test_check_unexpected_php_in_uploads_skips_wpml_twig_cache
test_check_unexpected_php_in_uploads_skips_sucuri
test_check_unexpected_php_in_uploads_skips_charmap
test_check_unexpected_php_in_uploads_missing_uploads_dir
test_check_unexpected_php_in_uploads_skips_whitelisted_index
test_check_unexpected_php_in_uploads_skips_nested_sucuri
test_check_unexpected_php_in_uploads_skips_nested_wpforms_cache
test_check_unexpected_php_in_uploads_skips_debug_log_php_with_mailchimp_pattern
test_check_index_integrity_flags_core_mismatch
test_check_index_integrity_passes_core_match
test_check_index_integrity_recognizes_boilerplate
test_check_index_integrity_flags_unrecognized_file
test_baseline_diff_shows_new_files_when_no_baseline_exists
test_baseline_write_persists_candidates
test_check_homepage_redirect_detects_ushort_company_signature
test_check_homepage_redirect_detects_maintenance_signature
test_check_homepage_redirect_flags_external_redirect
test_check_homepage_redirect_ignores_internal_redirect
test_check_homepage_redirect_clean_homepage_no_anomaly
test_check_homepage_redirect_unreachable_site_returns_cleanly
test_check_homepage_redirect_detects_real_attack_string
test_send_slack_alert_returns_success_on_http_200
test_send_slack_alert_returns_failure_on_http_500
test_send_slack_alert_returns_failure_on_http_404
test_send_slack_alert_fails_when_webhook_not_configured
test_should_notify_true_for_new_anomaly
test_should_notify_only_once_while_anomaly_stays_open
test_clear_resolved_removes_entry
test_should_notify_true_again_after_clear_resolved
test_should_notify_not_suppressed_by_suffix_domain_entry
test_clear_resolved_does_not_remove_longer_domain_entry
test_with_lock_prevents_concurrent_execution
test_with_lock_runs_and_releases_when_free
test_run_check_forwards_stdout_with_nonzero_return
test_run_check_empty_output_with_zero_return

exit $FAIL
