#!/usr/bin/env bash
# run-compat-tests.sh
# Test di compatibilità PHP dei siti nel container — oc:8834
#
# Uso: run-compat-tests.sh <cartella-backup-AAAAMMGG-HHMM> <cartella-risultati> <versione-php>… [-- sito…]
# Per ogni versione e ogni sito: import-site.sh, smoke-test.sh --local, pagine di wp-admin con
# un utente di test (cookie generato via WP-CLI, così i plugin che proteggono il login non
# interferiscono), per WooCommerce prodotto nel carrello e pagina di checkout, poi
# classify-php-log.sh sul log PHP. Scrive <risultati>/<versione>/<sito>/ (output e log PHP) e
# una riga per sito in <risultati>/risultati.tsv:
#   versione sito smoke admin woo fatal warning deprecated notice
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/../../docker/php-compat" && pwd)"
source "$SCRIPT_DIR/smoke-test.sh" --source-only

if [ $# -lt 3 ]; then
    echo "Uso: $0 <cartella-backup> <cartella-risultati> <versione-php>… [-- sito…]" >&2
    exit 2
fi
backup="${1%/}" results="${2%/}"
shift 2
versions=()
while [ $# -gt 0 ] && [ "$1" != "--" ]; do versions+=("$1"); shift; done
[ "${1:-}" = "--" ] && shift
if [ $# -gt 0 ]; then sites=("$@"); else
    sites=()
    for d in "$backup"/*/; do sites+=("$(basename "$d")"); done
fi

mkdir -p "$results"
tsv="$results/risultati.tsv"
[ -f "$tsv" ] || printf 'versione\tsito\tsmoke\tadmin\twoo\tfatal\twarning\tdeprecated\tnotice\n' > "$tsv"

dc() { docker compose -p oc8834 -f "$COMPOSE_DIR/compose.yml" "$@"; }

# check_url <sito> <percorso> <file-out> [opzioni curl…]: OK/KO come lo smoke test
check_url() {
    local site="$1" path="$2" out="$3" body code reason
    shift 3
    body=$(mktemp)
    # shellcheck disable=SC2046 # opzioni senza spazi
    code=$(curl -sS -L --max-time 120 $(smoke_local_curl_opts) "$@" \
        -o "$body" -w '%{http_code}' "https://$site$path" 2>/dev/null)
    if reason=$(smoke_check_response "$code" "$body" "$path"); then
        echo "OK $code $path" >> "$out"; rm -f "$body"; return 0
    fi
    echo "KO $code $path $reason" >> "$out"; rm -f "$body"; return 1
}

for version in "${versions[@]}"; do
    for site in "${sites[@]}"; do
        out="$results/$version/$site"
        mkdir -p "$out"
        echo "== PHP $version · $site"
        if ! PHP_VERSION="$version" bash "$SCRIPT_DIR/import-site.sh" "$backup/$site" "$site" > "$out/import.log" 2>&1; then
            printf '%s\t%s\tIMPORT-KO\t-\t-\t-\t-\t-\t-\n' "$version" "$site" >> "$tsv"
            continue
        fi
        root="$(cat "$backup/$site/docroot")"
        export PHP_VERSION="$version" SITE_NAME="$site" SITE_ROOT="$root" SITE_WORK="${WORK_DIR:-$HOME/oc8834-work}/$site"
        wpc() { dc exec -T -w "$root" web wp --allow-root "$@"; }

        smoke=OK
        smoke_test_site "$site" --local > "$out/smoke.txt" || smoke=KO

        # wp-admin con un utente di test e il suo cookie di accesso
        admin=OK
        uid=$(wpc user create oc8834test oc8834test@example.invalid --role=administrator --porcelain 2>/dev/null \
            || wpc user get oc8834test --field=ID 2>/dev/null)
        cookie=$(wpc eval "echo SECURE_AUTH_COOKIE, '=', wp_generate_auth_cookie($uid, time() + 3600, 'secure_auth'), '; ', LOGGED_IN_COOKIE, '=', wp_generate_auth_cookie($uid, time() + 3600, 'logged_in');" 2>/dev/null)
        page=$(wpc post list --post_type=page --post_status=publish --posts_per_page=1 --field=ID 2>/dev/null)
        : > "$out/admin.txt"
        for p in /wp-admin/ /wp-admin/edit.php?post_type=page "/wp-admin/post.php?post=$page&action=edit" /wp-admin/plugins.php; do
            check_url "$site" "$p" "$out/admin.txt" -b "$cookie" || admin=KO
        done

        # WooCommerce: un prodotto nel carrello e la pagina di checkout (il pagamento non parte:
        # il container non ha rete verso i gateway)
        woo=-
        if wpc plugin is-active woocommerce 2>/dev/null; then
            woo=OK
            jar=$(mktemp)
            # Un prodotto semplice e disponibile: un prodotto variabile o esaurito non entra nel
            # carrello e il checkout reindirizzerebbe al carrello vuoto.
            product=$(wpc eval "echo implode('', wc_get_products(['type' => 'simple', 'status' => 'publish', 'stock_status' => 'instock', 'limit' => 1, 'return' => 'ids']));" 2>/dev/null)
            checkout=$(wpc eval 'echo wp_parse_url(wc_get_checkout_url(), PHP_URL_PATH);' 2>/dev/null)
            : > "$out/woo.txt"
            if [ -z "$product" ]; then
                echo "KO - nessun prodotto semplice disponibile" >> "$out/woo.txt"; woo=KO
            else
                check_url "$site" "/?add-to-cart=$product" "$out/woo.txt" -c "$jar" -b "$jar" || woo=KO
                body=$(mktemp)
                # shellcheck disable=SC2046 # opzioni senza spazi
                read -r code final < <(curl -sS -L --max-time 120 $(smoke_local_curl_opts) -c "$jar" -b "$jar" \
                    -o "$body" -w '%{http_code} %{url_effective}' "https://$site$checkout" 2>/dev/null)
                final="/${final#https://*/}"
                if reason=$(smoke_check_checkout "$code" "$body" "$final" "$checkout"); then
                    echo "OK $code $checkout (prodotto $product nel carrello)" >> "$out/woo.txt"
                else
                    echo "KO $code $checkout $reason" >> "$out/woo.txt"; woo=KO
                fi
                rm -f "$body"
            fi
            rm -f "$jar"
        fi

        cp "$COMPOSE_DIR/logs/php-error.log" "$out/php-error.log"
        counts=$(bash "$SCRIPT_DIR/classify-php-log.sh" "$out/php-error.log" | tee "$out/classify.txt" | head -1)
        read -r fatal warning deprecated notice <<< "$(sed 's/[a-z]*=//g' <<< "$counts")"
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$version" "$site" "$smoke" "$admin" "$woo" \
            "$fatal" "$warning" "$deprecated" "$notice" >> "$tsv"
    done
done

dc down -v > /dev/null 2>&1 || true
column -t -s $'\t' "$tsv"
