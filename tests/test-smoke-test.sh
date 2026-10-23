#!/usr/bin/env bash
# Test dello smoke test per sito — oc:8834
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/php-migration/smoke-test.sh" --source-only

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

# verdict <http_code> <percorso> <body>: "OK" o "KO" secondo smoke_check_response
verdict() {
    local f rc
    f=$(mktemp)
    printf '%s' "$3" > "$f"
    rc=0; smoke_check_response "$1" "$f" "$2" > /dev/null || rc=$?
    rm -f "$f"
    [ "$rc" -eq 0 ] && echo OK || echo KO
}

test_smoke_ok_on_200_normal_body() {
    assert_eq "200 con pagina normale" OK "$(verdict 200 / '<html><body>Benvenuti</body></html>')"
}

test_smoke_detects_critical_error_with_200() {
    assert_eq "errore critico WordPress in italiano" KO \
        "$(verdict 200 / '<html><body><p>Si è verificato un errore critico sul tuo sito web.</p></body></html>')"
    assert_eq "errore critico WordPress in inglese" KO \
        "$(verdict 200 / '<html><body><p>There has been a critical error on this website.</p></body></html>')"
    assert_eq "Fatal error stampato in pagina" KO \
        "$(verdict 200 / '<br /><b>Fatal error</b>:  Uncaught Error in /var/www/a.php')"
}

test_smoke_ko_on_500() {
    assert_eq "HTTP 500" KO "$(verdict 500 / '<html>errore</html>')"
}

test_smoke_ko_on_empty_body() {
    assert_eq "body vuoto" KO "$(verdict 200 / '')"
}

test_smoke_login_needs_loginform() {
    assert_eq "login con form" OK "$(verdict 200 /wp-login.php '<form name="loginform" id="loginform" action="x">')"
    assert_eq "login senza form" KO "$(verdict 200 /wp-login.php '<html><body>Accesso disabilitato</body></html>')"
}

test_smoke_admin_needs_adminmenu() {
    assert_eq "wp-admin con menu di amministrazione" OK \
        "$(verdict 200 /wp-admin/ '<div id="adminmenuwrap"><ul id="adminmenu">')"
    assert_eq "wp-admin finito sul form di login" KO \
        "$(verdict 200 /wp-admin/edit.php?post_type=page '<form name="loginform" id="loginform">')"
}

test_smoke_local_routes_every_host() {
    # Un redirect verso un altro host (www., dominio diverso) non deve finire in produzione
    assert_eq "--local devia tutti gli host" "-k --connect-to ::127.0.0.1:8443" "$(smoke_local_curl_opts)"
}

test_smoke_checkout_needs_form() {
    local f rc
    f=$(mktemp)
    echo '<form name="checkout" method="post" class="checkout woocommerce-checkout">' > "$f"
    rc=0; smoke_check_checkout 200 "$f" /checkout/ /checkout/ > /dev/null || rc=$?
    assert_eq "checkout con il form" 0 "$rc"
    rc=0; smoke_check_checkout 200 "$f" /carrello/ /checkout/ > /dev/null || rc=$?
    assert_eq "checkout reindirizzato al carrello (carrello vuoto)" 1 "$rc"
    echo '<p class="cart-empty">Il carrello è vuoto.</p>' > "$f"
    rc=0; smoke_check_checkout 200 "$f" /checkout/ /checkout/ > /dev/null || rc=$?
    assert_eq "checkout senza form" 1 "$rc"
    rm -f "$f"
}

test_smoke_urls_per_site() {
    local conf
    conf=$(mktemp)
    cat > "$conf" <<'EOF'
# commento
parcopan.org /
parcopan.org /carrello/
sentierodeiducati.it /
sentierodeiducati.it /tracce-gps/
EOF
    assert_eq "percorsi di parcopan" "/ /carrello/" "$(smoke_urls_for_site parcopan.org "$conf" | tr '\n' ' ' | sed 's/ $//')"
    assert_eq "sito assente dal file" "" "$(smoke_urls_for_site assente.it "$conf")"
    rm -f "$conf"
}

test_smoke_conf_covers_all_sites() {
    local s n
    for s in acquasorgente.cai.it european-mountaineers.eu outcropedia.org selfguided-toscana.it \
        sicai.webmapp.it parco-maremma.it parcopan.org sentierodeiducati.it trekking.parcoforestecasentinesi.it; do
        n=$(smoke_urls_for_site "$s" "$SMOKE_URLS_CONF" | grep -cxF /wp-login.php || true)
        assert_eq "smoke-urls.conf: $s ha homepage e login" "2" \
            "$(( n + $(smoke_urls_for_site "$s" "$SMOKE_URLS_CONF" | grep -cx / || true) ))"
    done
}

test_smoke_reports_connection_failure() {
    local conf out
    conf=$(mktemp)
    echo "sito-finto.it /" > "$conf"
    # 192.0.2.1 (TEST-NET-1) non risponde: curl fallisce senza codice HTTP
    out=$(SMOKE_URLS_CONF="$conf" SMOKE_LOCAL_TARGET=192.0.2.1:8443 SMOKE_RETRY_DELAY=0 SMOKE_CONNECT_TIMEOUT=1 \
        smoke_test_site sito-finto.it --local || true)
    assert_eq "connessione fallita: codice 000 una volta sola" "KO 000 /" "$(cut -d' ' -f1-3 <<< "$out")"
    assert_eq "connessione fallita: motivo curl riportato" 1 "$(grep -c 'curl:' <<< "$out")"
    rm -f "$conf"
}

test_smoke_reports_connection_failure
test_smoke_ok_on_200_normal_body
test_smoke_detects_critical_error_with_200
test_smoke_ko_on_500
test_smoke_ko_on_empty_body
test_smoke_login_needs_loginform
test_smoke_admin_needs_adminmenu
test_smoke_local_routes_every_host
test_smoke_checkout_needs_form
test_smoke_urls_per_site
test_smoke_conf_covers_all_sites

exit "$FAIL"
