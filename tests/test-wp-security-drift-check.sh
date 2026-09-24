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

test_enumerate_sites_skips_commented_servername() {
    # Regressione 24/09/2026: un vhost reale aveva un ServerName legacy commentato (tenuto per
    # storico, es. un vecchio nome interno) sopra a quello attivo. grep -m1 senza escludere i
    # commenti leggeva il nome commentato invece di quello vero.
    local tmp
    tmp=$(mktemp -d)
    mkdir -p "$tmp/sites-enabled"
    cat > "$tmp/sites-enabled/legacy.conf" <<'EOF'
<VirtualHost *:443>
    # ServerName     nome-legacy-dismesso.it
    ServerName     sito-vero.it
    DocumentRoot   /var/www/html/sito-vero.it
</VirtualHost>
EOF
    local out
    out=$(APACHE_SITES_ENABLED_DIR="$tmp/sites-enabled" enumerate_sites)
    assert_eq "legge il ServerName attivo, non quello commentato sopra" "sito-vero.it|/var/www/html/sito-vero.it" "$out"
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

start_mock_http_recording_server() {
    # Variante di start_mock_http_server che NON serve una sola richiesta: resta in ascolto
    # finché non viene killata e registra ogni POST ricevuta su $requests_file (una riga per
    # richiesta, col body). Serve al test di integrazione su main(), che deve poter contare
    # esattamente quante notifiche Slack sono partite in una run completa — né una in meno
    # (anomalia soppressa) né una in più (stessa anomalia notificata N volte).
    local port="$1" status_code="$2" requests_file="$3"
    : > "$requests_file"
    python3 -c "
import http.server, socketserver
socketserver.TCPServer.allow_reuse_address = True
REQUESTS_FILE = '$requests_file'
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length') or 0)
        body = self.rfile.read(length)
        # Scritto PRIMA della risposta: quando curl ritorna, la richiesta è già registrata.
        with open(REQUESTS_FILE, 'ab') as fh:
            fh.write(body.replace(b'\n', b' ') + b'\n')
        self.send_response($status_code)
        self.end_headers()
    def log_message(self, *args): pass
with socketserver.TCPServer(('127.0.0.1', $port), Handler) as httpd:
    httpd.serve_forever()
" >/dev/null 2>&1 &
    echo $!
}

start_mock_http_get_server() {
    local port="$1" status_code="$2"
    python3 -c "
import http.server, socketserver
socketserver.TCPServer.allow_reuse_address = True
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
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

start_mock_slow_http_server() {
    local port="$1" delay_seconds="$2"
    python3 -c "
import http.server, socketserver, time
socketserver.TCPServer.allow_reuse_address = True
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        time.sleep($delay_seconds)
        self.send_response(200)
        self.end_headers()
    def log_message(self, *args): pass
with socketserver.TCPServer(('127.0.0.1', $port), Handler) as httpd:
    httpd.timeout = 30
    httpd.handle_request()
" >/dev/null 2>&1 &
    local pid=$!
    echo "$pid"
}

wait_for_mock_server() {
    local port="$1" i
    for i in $(seq 1 100); do
        if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:${port}/" 2>/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

stop_mock_server() {
    local pid="$1"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
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

test_check_homepage_redirect_ignores_bare_variable_target() {
    local tmp html_file port pid rc=0 out
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    printf '<html><script>location.href = someVariableName;</script></html>' > "$html_file"
    port=18096
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    assert_eq "non segnala location.href verso una variabile bare (nessuna URL letterale nel match)" "" "$out"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_check_homepage_redirect_flags_meta_refresh_url_equals_external() {
    # Regressione: il formato standard del meta-refresh (`content="0;url=https://…"`) NON ha
    # la virgoletta adiacente allo schema/"//" — è "url=" che precede lo schema. Il pattern
    # letterale deve riconoscere anche questa forma (case-insensitive su "url").
    local tmp html_file port pid rc=0 out count
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    printf '<html><head><meta http-equiv="refresh" content="0;url=https://evil.example"></head></html>' > "$html_file"
    port=18097
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    count=$(printf '%s\n' "$out" | grep -c "dominio esterno" || true)
    assert_eq "rileva meta-refresh formato standard content=\"N;url=https://…\" come redirect esterno" "1" "$count"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_check_homepage_redirect_ignores_meta_refresh_url_equals_internal() {
    # Stesso formato "url=" del meta-refresh, ma verso il dominio stesso del sito: non è
    # un'anomalia, coerente con la logica interno/esterno già esistente.
    local tmp html_file port pid rc=0 out
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    port=18098
    printf '<html><head><meta http-equiv="refresh" content="0; url=//127.0.0.1:%s/page"></head></html>' "$port" > "$html_file"
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_homepage_redirect "127.0.0.1:$port") || rc=$?
    assert_eq "non segnala meta-refresh url= verso il proprio stesso dominio (interno)" "" "$out"
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

test_check_site_reachable_reachable_site_no_anomaly() {
    local tmp html_file port pid rc=0 out
    tmp=$(mktemp -d)
    html_file="$tmp/index.html"
    printf '<html><body>ok</body></html>' > "$html_file"
    port=18200
    pid=$(start_mock_html_server "$port" "$html_file")
    sleep 2
    out=$(HOMEPAGE_SCHEME=http check_site_reachable "127.0.0.1:$port") || rc=$?
    assert_eq "sito raggiungibile: nessun errore dello script" "0" "$rc"
    assert_eq "sito raggiungibile: nessuna anomalia" "" "$out"
    wait "$pid" 2>/dev/null || true
    rm -rf "$tmp"
}

test_check_site_reachable_connection_refused_reports_anomaly() {
    local rc=0 out count
    out=$(SITE_REACHABLE_TIMEOUT=2 SITE_REACHABLE_RETRIES=1 SITE_REACHABLE_RETRY_DELAY=0 check_site_reachable "127.0.0.1:1") || rc=$?
    assert_eq "sito irraggiungibile: nessun errore dello script" "0" "$rc"
    count=$(printf '%s\n' "$out" | grep -c "non raggiungibile" || true)
    assert_eq "sito irraggiungibile dopo i retry: anomalia segnalata" "1" "$count"
}

test_check_site_reachable_5xx_reports_anomaly() {
    local port pid rc=0 out count
    port=18201
    pid=$(start_mock_http_get_server "$port" 500)
    sleep 2
    out=$(HOMEPAGE_SCHEME=http SITE_REACHABLE_RETRIES=0 check_site_reachable "127.0.0.1:$port") || rc=$?
    count=$(printf '%s\n' "$out" | grep -c "non raggiungibile" || true)
    assert_eq "risposta 500 dal server: anomalia segnalata" "1" "$count"
    wait "$pid" 2>/dev/null || true
}

test_check_site_reachable_slow_response_within_timeout_no_anomaly() {
    # Scenario esplicito richiesto dall'utente: homepage lenta per plugin pesanti, ma che
    # comunque risponde entro un timeout più largo di quello standard (10s) — non deve
    # generare un falso positivo di "sito giù".
    local port pid rc=0 out
    port=18202
    pid=$(start_mock_slow_http_server "$port" 3)
    sleep 2
    out=$(HOMEPAGE_SCHEME=http SITE_REACHABLE_TIMEOUT=8 SITE_REACHABLE_RETRIES=0 check_site_reachable "127.0.0.1:$port") || rc=$?
    assert_eq "risposta lenta (3s) ma entro il timeout esteso (8s): nessuna anomalia" "" "$out"
    wait "$pid" 2>/dev/null || true
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
    should_notify "anomaly-1" "$state" "5" || rc=$?
    assert_eq "notifica sempre una nuova anomalia" "0" "$rc"
    rm -rf "$tmp"
}

test_should_notify_only_once_while_anomaly_stays_open() {
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    local rc=0
    should_notify "anomaly-1" "$state" "5" || rc=$?
    assert_eq "notifica la prima volta" "0" "$rc"
    rc=0
    should_notify "anomaly-1" "$state" "5" || rc=$?
    assert_eq "non rinotifica una seconda volta senza clear_resolved, se il conteggio non cambia" "1" "$rc"
    rm -rf "$tmp"
}

test_should_notify_renotifies_when_count_changes() {
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    local rc=0
    should_notify "anomaly-1" "$state" "5" || rc=$?
    assert_eq "notifica la prima volta (count=5)" "0" "$rc"
    rc=0
    should_notify "anomaly-1" "$state" "5" || rc=$?
    assert_eq "non rinotifica con lo stesso conteggio (count=5)" "1" "$rc"
    rc=0
    should_notify "anomaly-1" "$state" "8" || rc=$?
    assert_eq "rinotifica quando il conteggio cambia (count=8), senza clear_resolved" "0" "$rc"
    rm -rf "$tmp"
}

test_should_notify_renotifies_when_count_decreases() {
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    local rc=0
    should_notify "anomaly-1" "$state" "8" || rc=$?
    assert_eq "notifica la prima volta (count=8)" "0" "$rc"
    rc=0
    should_notify "anomaly-1" "$state" "3" || rc=$?
    assert_eq "rinotifica anche se il conteggio diminuisce (count=3)" "0" "$rc"
    rm -rf "$tmp"
}

test_clear_resolved_removes_entry() {
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    should_notify "anomaly-1" "$state" "5" >/dev/null
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
    should_notify "anomaly-1" "$state" "5" >/dev/null
    clear_resolved "anomaly-1" "$state"
    local rc=0
    should_notify "anomaly-1" "$state" "5" || rc=$?
    assert_eq "rinotifica come nuova occorrenza dopo clear_resolved" "0" "$rc"
    rm -rf "$tmp"
}

test_should_notify_not_suppressed_by_suffix_domain_entry() {
    # Regression oc:8558: "maremma.it:htaccess" è suffisso di "parco-maremma.it:htaccess".
    # Con matching per sottostringa la riga esistente per il dominio più lungo farebbe match
    # anche per il dominio più corto/distinto, sopprimendo erroneamente una nuova anomalia.
    # Il formato di stato è ora domain:check<TAB><count>, ma il matching deve restare
    # sul campo esatto (awk -F'\t' '$1 == id'), non per sottostringa.
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    printf 'parco-maremma.it:htaccess\t5\n' > "$state"
    local rc=0
    should_notify "maremma.it:htaccess" "$state" "5" || rc=$?
    assert_eq "anomalia di un dominio suffisso non viene soppressa da un'entry di un dominio più lungo" "0" "$rc"
    rm -rf "$tmp"
}

test_clear_resolved_does_not_remove_longer_domain_entry() {
    # Regression oc:8558: clear_resolved su "maremma.it:htaccess" non deve rimuovere l'entry
    # di "parco-maremma.it:htaccess" (falso match per sottostringa con grep -vF senza -x).
    # Verificato anche con il nuovo formato basato su conteggio, per lo stesso motivo.
    local tmp state
    tmp=$(mktemp -d)
    state="$tmp/state.tsv"
    printf 'parco-maremma.it:htaccess\t5\n' > "$state"
    clear_resolved "maremma.it:htaccess" "$state"
    local rc=0
    grep -qxF "parco-maremma.it:htaccess"$'\t'"5" "$state" || rc=$?
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

test_main_end_to_end_two_sites_suffix_domains() {
    # Test di integrazione su main(): è l'unico che esercita l'orchestrazione completa
    # (enumerazione vhost → check per dominio → log → stato → notifiche Slack → heartbeat).
    # I bug che copre vivevano tutti nel cablaggio di main(), non nelle singole funzioni, e
    # nessun test unitario per-funzione avrebbe potuto intercettarli:
    #   - regola Apache eseguita una sola volta per run, non una per sito;
    #   - anomalie di due domini di cui uno è suffisso dell'altro tracciate separatamente;
    #   - una seconda run identica non rinotifica nulla.
    local tmp port pid
    tmp=$(mktemp -d)
    port=18099

    # --- vhost: due siti il cui dominio è suffisso dell'altro --------------------------
    # L'ordine di enumerazione conta: i vhost sono letti in ordine di glob e il dominio PIÙ
    # LUNGO (parco-maremma.it) deve finire nello stato PRIMA di quello più corto
    # (maremma.it). È esattamente lo scenario in cui il vecchio matching per sottostringa in
    # should_notify sopprimeva la notifica del dominio corto (il prefisso "maremma.it:..."
    # è contenuto nella riga di stato "parco-maremma.it:...").
    local sites_dir="$tmp/sites-enabled"
    local docroot_parco="$tmp/www/parco-maremma.it"
    local docroot_maremma="$tmp/www/maremma.it"
    mkdir -p "$sites_dir" "$docroot_parco" "$docroot_maremma"

    cat > "$sites_dir/000-parco-maremma.it.conf" <<EOF
<VirtualHost *:80>
    ServerName parco-maremma.it
    DocumentRoot $docroot_parco
</VirtualHost>
EOF
    cat > "$sites_dir/001-maremma.it.conf" <<EOF
<VirtualHost *:80>
    ServerName maremma.it
    DocumentRoot $docroot_maremma
</VirtualHost>
EOF

    # wp-config.php in violazione su entrambi i siti → un'anomalia wp-config per dominio,
    # distinta e indipendente. Nessun wp-includes/version.php nei docroot: get_wp_version
    # resta vuoto e main() salta check_index_integrity per la sua guardia
    # `if [ -n "$wp_version" ]`, quindi nessuna chiamata a api.wordpress.org. Nessuna
    # uploads/, nessun .htaccess, nessun file con estensione immagine: ioc-files, htaccess e
    # uploads-php restano puliti per entrambi i siti.
    local d
    for d in "$docroot_parco" "$docroot_maremma"; do
        cat > "$d/wp-config.php" <<'EOF'
<?php
define('DISALLOW_FILE_MODS', false);
define('DISALLOW_FILE_EDIT', false);
EOF
    done

    # Regola Apache globale incompleta (manca il path del volume montato): una violazione
    # sola e globale che, con 2 siti enumerati, deve comunque produrre UNA anomalia e UNA
    # notifica, non una per sito.
    cat > "$tmp/no-php-in-writable.conf" <<'EOF'
<DirectoryMatch "^/var/www/html/[^/]+/(wp-content/uploads|images|\.well-known)/">
    php_admin_flag engine off
</DirectoryMatch>
EOF

    : > "$tmp/exceptions.conf"
    : > "$tmp/boilerplate.txt"

    local requests_file="$tmp/slack-requests.log"
    pid=$(start_mock_http_recording_server "$port" 200 "$requests_file")
    local ready=0
    wait_for_mock_server "$port" || ready=$?
    assert_eq "il mock Slack è in ascolto prima di lanciare main()" "0" "$ready"

    printf 'http://127.0.0.1:%s/webhook\n' "$port" > "$tmp/slack-webhook"

    # Tutta la configurazione dello script è in variabili globali: dichiararle `local` qui
    # le rende visibili a main() (scoping dinamico di bash) e le ripristina all'uscita dal
    # test, senza toccare nulla fuori dalla sandbox in $tmp.
    local APACHE_SITES_ENABLED_DIR="$sites_dir"
    local NO_PHP_CONF="$tmp/no-php-in-writable.conf"
    local SLACK_WEBHOOK_URL_FILE="$tmp/slack-webhook"
    local LOG_FILE="$tmp/drift.log"
    local STATE_FILE="$tmp/state.tsv"
    local HEARTBEAT_FILE="$tmp/heartbeat"
    local LOCKFILE="$tmp/drift.lock"
    local EXCEPTIONS_FILE="$tmp/exceptions.conf"
    local BOILERPLATE_FILE="$tmp/boilerplate.txt"
    local STAGGER_SECONDS=0
    # Schema fittizio: curl rifiuta il protocollo localmente (errore immediato, nessuna
    # risoluzione DNS né connessione di rete), quindi check_homepage_redirect riceve un body
    # vuoto ed esce pulito — lo stesso comportamento già previsto e testato per un sito
    # irraggiungibile. Serve a tenere il test completamente offline senza stubbare la
    # funzione, così anche il suo cablaggio dentro main() resta sotto test.
    # Lo stesso schema fittizio fa fallire anche check_site_reachable (curl non riesce a
    # instaurare alcuna connessione) — ma quel check, a differenza di homepage-redirect,
    # considera "irraggiungibile" un'anomalia reale (è il suo scopo): per i due domini di
    # fixture produce quindi correttamente un'anomalia site-down ciascuno, in aggiunta alle
    # 3 già previste. Retry a zero per non rallentare il test.
    local HOMEPAGE_SCHEME="wm-test-offline"
    local SITE_REACHABLE_RETRIES=0

    # main() è scritto per girare sotto `set -uo pipefail` come lo script in produzione
    # (senza -e: diversi check restituiscono non-zero come esito normale). La suite invece
    # gira con -e, quindi lo eseguiamo in una subshell con `set +e` per riprodurre
    # fedelmente l'ambiente reale; log, stato e heartbeat restano comunque su disco.
    local rc=0
    ( set +e; with_lock "$LOCKFILE" main ) || rc=$?
    assert_eq "main() completa senza errori (prima run)" "0" "$rc"

    # 1. Il log contiene le cinque anomalie distinte (apache-rule + wp-config e site-down per
    #    ciascuno dei due domini). Il match è su stringa fissa comprensiva della parentesi
    #    quadra aperta, così "[maremma.it]" non matcha "[parco-maremma.it]".
    local count
    count=$(grep -cF '[server] apache-rule:' "$LOG_FILE" || true)
    assert_eq "il log registra l'anomalia apache-rule una sola volta" "1" "$count"
    count=$(grep -cF '[parco-maremma.it] wp-config:' "$LOG_FILE" || true)
    assert_eq "il log registra l'anomalia wp-config di parco-maremma.it" "1" "$count"
    count=$(grep -cF '[maremma.it] wp-config:' "$LOG_FILE" || true)
    assert_eq "il log registra l'anomalia wp-config di maremma.it" "1" "$count"
    count=$(grep -cF '[parco-maremma.it] site-down:' "$LOG_FILE" || true)
    assert_eq "il log registra l'anomalia site-down di parco-maremma.it" "1" "$count"
    count=$(grep -cF '[maremma.it] site-down:' "$LOG_FILE" || true)
    assert_eq "il log registra l'anomalia site-down di maremma.it" "1" "$count"

    # 2. Lo stato traccia SOLO le anomalie Slack-eligible (homepage-redirect/site-down):
    #    apache-rule e wp-config restano nel log ma non hanno bisogno di stato, perché
    #    should_notify non viene più chiamato per loro (nessuna decisione di notifica da
    #    deduplicare). Due righe distinte: il dominio suffisso non collide con l'altro.
    count=$(grep -c . "$STATE_FILE" || true)
    assert_eq "lo stato contiene esattamente 2 anomalie (solo site-down)" "2" "$count"
    local id
    for id in "parco-maremma.it:site-down" "maremma.it:site-down"; do
        count=$(awk -F'\t' -v want="$id" '$1 == want' "$STATE_FILE" | grep -c . || true)
        assert_eq "lo stato ha una riga propria per $id" "1" "$count"
    done
    for id in "server:apache-rule" "parco-maremma.it:wp-config" "maremma.it:wp-config"; do
        count=$(awk -F'\t' -v want="$id" '$1 == want' "$STATE_FILE" | grep -c . || true)
        assert_eq "lo stato NON traccia $id (non è Slack-eligible)" "0" "$count"
    done

    # 3. Esattamente 2 POST al webhook: solo site-down per ciascuno dei due domini.
    #    apache-rule/wp-config restano solo nel log, mai su Slack (decisione Giuseppe
    #    Bonfanti, scrum 24/09/2026).
    count=$(grep -c . "$requests_file" || true)
    assert_eq "main() invia esattamente 2 notifiche Slack (solo site-down)" "2" "$count"

    # 4. Heartbeat (dead-man's-switch) scritto a fine run.
    local heartbeat
    heartbeat=$(cat "$HEARTBEAT_FILE" 2>/dev/null || true)
    assert_eq "l'heartbeat contiene un timestamp unix plausibile" "ok" \
        "$(printf '%s' "$heartbeat" | grep -qE '^[0-9]{10,}$' && echo ok || echo "valore inatteso: '$heartbeat'")"

    # 5. Seconda run a fixture invariata: stesse anomalie, stessi conteggi → nessuna nuova
    #    notifica (si notifica una volta sola finché la situazione non cambia).
    rc=0
    ( set +e; with_lock "$LOCKFILE" main ) || rc=$?
    assert_eq "main() completa senza errori (seconda run)" "0" "$rc"
    count=$(grep -c . "$requests_file" || true)
    assert_eq "una seconda run identica non invia nuove notifiche Slack" "2" "$count"
    count=$(grep -c . "$STATE_FILE" || true)
    assert_eq "lo stato resta a 2 anomalie dopo la seconda run" "2" "$count"

    stop_mock_server "$pid"
    rm -rf "$tmp"
}

test_enumerate_sites_finds_two_distinct_docroots
test_enumerate_sites_empty_dir_returns_zero
test_enumerate_sites_multi_space_and_tabs
test_enumerate_sites_skips_commented_servername
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
test_check_homepage_redirect_ignores_bare_variable_target
test_check_homepage_redirect_flags_meta_refresh_url_equals_external
test_check_homepage_redirect_ignores_meta_refresh_url_equals_internal
test_check_homepage_redirect_clean_homepage_no_anomaly
test_check_homepage_redirect_unreachable_site_returns_cleanly
test_check_homepage_redirect_detects_real_attack_string
test_send_slack_alert_returns_success_on_http_200
test_send_slack_alert_returns_failure_on_http_500
test_send_slack_alert_returns_failure_on_http_404
test_send_slack_alert_fails_when_webhook_not_configured
test_should_notify_true_for_new_anomaly
test_should_notify_only_once_while_anomaly_stays_open
test_should_notify_renotifies_when_count_changes
test_should_notify_renotifies_when_count_decreases
test_clear_resolved_removes_entry
test_should_notify_true_again_after_clear_resolved
test_should_notify_not_suppressed_by_suffix_domain_entry
test_clear_resolved_does_not_remove_longer_domain_entry
test_with_lock_prevents_concurrent_execution
test_with_lock_runs_and_releases_when_free
test_run_check_forwards_stdout_with_nonzero_return
test_run_check_empty_output_with_zero_return
test_main_end_to_end_two_sites_suffix_domains
test_check_site_reachable_reachable_site_no_anomaly
test_check_site_reachable_connection_refused_reports_anomaly
test_check_site_reachable_5xx_reports_anomaly
test_check_site_reachable_slow_response_within_timeout_no_anomaly

exit $FAIL
