#!/usr/bin/env bash
# import-site.sh
# Carica un sito dal backup nel container di test di compatibilità PHP — oc:8834
#
# Uso: PHP_VERSION=8.4.27 import-site.sh <cartella-backup-sito> <sito>
# Estrae files.tar.gz del backup in una copia di lavoro sul disco interno
# (WORK_DIR/<sito>, default ~/oc8834-work), avvia lo stack con la docroot montata allo stesso
# percorso di produzione (letto dal file docroot del backup), importa db.sql.gz in un DB
# dedicato e adatta wp-config.php: DB locale e DISABLE_WP_CRON. WP_HOME/WP_SITEURL restano
# quelli di produzione (vedi smoke-test.sh --local). Il backup non viene mai modificato.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(cd "$SCRIPT_DIR/../../docker/php-compat" && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/oc8834-work}"

if [ $# -lt 2 ]; then
    echo "Uso: $0 <cartella-backup-sito> <sito>" >&2
    exit 2
fi
backup="${1%/}" site="$2"
root="$(cat "$backup/docroot")"
work="$WORK_DIR/$site"
db="$(tr '.-' '__' <<< "$site")"

rm -rf "$work"
mkdir -p "$work"
tar -xzf "$backup/files.tar.gz" -C "$work"
mkdir -p "$work/wp-content/mu-plugins"
cp "$COMPOSE_DIR/mu-plugins/oc8834-no-outbound.php" "$work/wp-content/mu-plugins/"

export PHP_VERSION="${PHP_VERSION:-8.4.27}" SITE_NAME="$site" SITE_ROOT="$root" SITE_WORK="$work"
dc() { docker compose -p oc8834 -f "$COMPOSE_DIR/compose.yml" "$@"; }

mkdir -p "$COMPOSE_DIR/logs"
dc up -d --build --wait --force-recreate web edge
dc exec -T db mysql -uroot -poc8834 -e \
    "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\`; GRANT ALL ON \`$db\`.* TO 'wp'@'%';" 2>/dev/null
gzip -dc "$backup/db.sql.gz" | dc exec -T db mysql -uroot -poc8834 "$db" 2>/dev/null

wpc() { dc exec -T -w "$root" web wp --allow-root "$@"; }
wpc config set DB_NAME "$db" --quiet
wpc config set DB_USER wp --quiet
wpc config set DB_PASSWORD oc8834 --quiet
wpc config set DB_HOST db --quiet
wpc config set DISABLE_WP_CRON true --raw --quiet
# Con WP_DEBUG=false WordPress abbassa error_reporting e scarta le Deprecated: in locale lo
# accendiamo, senza mostrare nulla in pagina e senza debug.log, così tutto va nel log PHP.
wpc config set WP_DEBUG true --raw --quiet
wpc config set WP_DEBUG_DISPLAY false --raw --quiet
wpc config set WP_DEBUG_LOG false --raw --quiet

: > "$COMPOSE_DIR/logs/php-error.log"
echo "Pronto: $site su PHP $PHP_VERSION (copia di lavoro $work)"
