#!/usr/bin/env bash
# smoke-test.sh
# Smoke test di un sito WordPress — oc:8834
#
# Uso: smoke-test.sh <sito> [--local]
# Interroga https://<sito><percorso> per ogni percorso di smoke-urls.conf, seguendo i
# redirect. Con --local la connessione va al container di test (SMOKE_LOCAL_TARGET), così il
# sito riceve lo stesso URL di produzione. Stampa "OK|KO <http_code> <percorso> [motivo]";
# exit 1 se almeno un KO. Una pagina è KO anche con HTTP 200 se il body è vuoto o contiene
# l'errore critico di WordPress o un "Fatal error" stampato.
set -uo pipefail

SMOKE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SMOKE_URLS_CONF="${SMOKE_URLS_CONF:-$SMOKE_DIR/smoke-urls.conf}"

# smoke_urls_for_site <sito> <conf>: i percorsi del sito, uno per riga
smoke_urls_for_site() {
    awk -v site="$1" '$1 == site && $0 !~ /^[[:space:]]*#/ { print $2 }' "$2"
}

# smoke_check_response <http_code> <file_body> <percorso>: exit 0 se OK, 1 se KO
# (stampa il motivo del KO)
smoke_check_response() {
    local code="$1" body="$2" path="$3"
    if [ "$code" != "200" ]; then
        echo "HTTP $code"; return 1
    fi
    if [ ! -s "$body" ]; then
        echo "body vuoto"; return 1
    fi
    if grep -qiE 'There has been a critical error|Si è verificato un errore critico|Fatal error(</b>)?:' "$body"; then
        echo "errore critico nel body"; return 1
    fi
    if [ "$path" = "/wp-login.php" ] && ! grep -q 'id="loginform"' "$body"; then
        echo "form di login assente"; return 1
    fi
    # Una pagina di wp-admin senza accesso fa redirect al login, che risponde 200: conta
    # solo se è davvero la bacheca.
    if [[ "$path" == /wp-admin/* ]] && ! grep -q 'id="adminmenu"' "$body"; then
        echo "non è la bacheca (accesso non riuscito?)"; return 1
    fi
    return 0
}

# Il container di test pubblica HTTPS su 8443 (sul Mac la 443 può essere occupata):
# --connect-to manda lì le richieste lasciando invariato l'URL https://<sito>/.
SMOKE_LOCAL_TARGET="${SMOKE_LOCAL_TARGET:-127.0.0.1:8443}"
SMOKE_RETRY_DELAY="${SMOKE_RETRY_DELAY:-5}"
SMOKE_CONNECT_TIMEOUT="${SMOKE_CONNECT_TIMEOUT:-15}"

# Opzioni curl per il container: "::" devia ogni host, così un redirect verso un altro host
# (www., dominio diverso) resta in locale invece di arrivare alla produzione.
smoke_local_curl_opts() {
    echo "-k --connect-to ::$SMOKE_LOCAL_TARGET"
}

# smoke_check_checkout <http_code> <file_body> <path_finale> <path_checkout>: exit 0 se la
# pagina di checkout WooCommerce è stata davvero servita (col carrello vuoto WooCommerce
# reindirizza al carrello, che risponde 200)
smoke_check_checkout() {
    local code="$1" body="$2" final="$3" expected="$4"
    if [ "$code" != "200" ]; then
        echo "HTTP $code"; return 1
    fi
    if [ "$final" != "$expected" ]; then
        echo "reindirizzato a $final (carrello vuoto?)"; return 1
    fi
    if ! grep -q 'woocommerce-checkout' "$body"; then
        echo "form di checkout assente"; return 1
    fi
    return 0
}

smoke_test_site() {
    local site="$1" mode="${2:-}" path body err code reason ko=0
    local -a curl_opts=(-sS -L --connect-timeout "$SMOKE_CONNECT_TIMEOUT" --max-time 60)
    # shellcheck disable=SC2207 # opzioni senza spazi
    [ "$mode" = "--local" ] && curl_opts=($(smoke_local_curl_opts) "${curl_opts[@]}")
    body=$(mktemp)
    err=$(mktemp)
    while IFS= read -r path; do
        # Una connessione fallita (curl senza codice HTTP) si riprova una volta: sul server
        # capitano errori di connessione sporadici che non dipendono dal sito.
        code=$(curl "${curl_opts[@]}" -o "$body" -w '%{http_code}' "https://$site$path" 2>"$err")
        if [ "$code" = "000" ]; then
            sleep "$SMOKE_RETRY_DELAY"
            code=$(curl "${curl_opts[@]}" -o "$body" -w '%{http_code}' "https://$site$path" 2>"$err")
        fi
        if [ "$code" = "000" ]; then
            echo "KO 000 $path $(head -1 "$err")"
            ko=1
        elif reason=$(smoke_check_response "$code" "$body" "$path"); then
            echo "OK $code $path"
        else
            echo "KO $code $path $reason"
            ko=1
        fi
    done < <(smoke_urls_for_site "$site" "$SMOKE_URLS_CONF")
    rm -f "$body" "$err"
    return "$ko"
}

if [ "${1:-}" = "--source-only" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ $# -lt 1 ]; then
    echo "Uso: $0 <sito> [--local]" >&2
    exit 2
fi

if [ -z "$(smoke_urls_for_site "$1" "$SMOKE_URLS_CONF")" ]; then
    echo "Nessun percorso per $1 in $SMOKE_URLS_CONF" >&2
    exit 2
fi

smoke_test_site "$1" "${2:-}"
