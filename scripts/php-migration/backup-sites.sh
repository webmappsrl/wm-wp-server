#!/usr/bin/env bash
# backup-sites.sh
# Backup dei siti WordPress senza media, dal server al Mac — oc:8834
#
# Uso (dal Mac): backup-sites.sh <cartella-backup> [sito…]
# Per ogni sito crea <dest>/<AAAAMMGG-HHMM>/<sito>/files.tar.gz (docroot senza media, vedi
# rsync-no-media.filter) e <sito>/db.sql.gz. Senza siti indicati fa tutti quelli dei vhost
# (enumerate_sites del drift-check di oc:8558). Il dump passa per ssh e non viene mai
# scritto su un file del server.
#
# I file passano da una cartella di appoggio sul disco interno (STAGING_DIR) e arrivano sul
# disco esterno come un unico archivio: l'exFAT del disco esterno ha blocchi da 512 KB, e
# decine di migliaia di file piccoli lo riempirebbero (circa 10 GB per sito invece di 0,5).
# L'archivio conserva i permessi, che l'exFAT perde, ma non i proprietari: rsync gira come
# utente del Mac. In un ripristino sul server servono chown e chmod come da
# documentazione operativa del repo privato (owner root, gruppo www-data sulle cartelle scrivibili).
# STAGING_DIR deve stare su un file system case-sensitive se un sito ha nomi che differiscono
# solo per maiuscole (sicai: src/Views e src/views); vedi docker/php-compat/README.md.
set -euo pipefail

SSH_HOST="${SSH_HOST:-php8}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$SCRIPT_DIR/rsync-no-media.filter"
STAGING_DIR="${STAGING_DIR:-$HOME/oc8834-staging}"

if [ $# -lt 1 ]; then
    echo "Uso: $0 <cartella-backup> [sito…]" >&2
    exit 2
fi
dest="$1/$(date +%Y%m%d-%H%M)"
shift

sites=$(ssh "$SSH_HOST" 'source /root/wp-security-drift-check.sh --source-only && enumerate_sites')
if [ $# -gt 0 ]; then
    sites=$(grep -E "^($(IFS='|'; echo "$*" | sed 's/\./\\./g'))\|" <<< "$sites" || true)
fi
[ -n "$sites" ] || { echo "Nessun sito da salvare" >&2; exit 2; }

while IFS='|' read -r site root; do
    echo "== $site ($root)"
    mkdir -p "$dest/$site" "$STAGING_DIR/$site"
    echo "$root" > "$dest/$site/docroot"
    rsync -a --delete --filter="merge $FILTER" "$SSH_HOST:$root/" "$STAGING_DIR/$site/"
    tar -czf "$dest/$site/files.tar.gz" -C "$STAGING_DIR/$site" .
    ssh -n "$SSH_HOST" "cd '$root' && wp --allow-root db export - --single-transaction --routines --triggers" \
        | gzip > "$dest/$site/db.sql.gz"
    if ! gzip -dc "$dest/$site/db.sql.gz" | tail -1 | grep -q 'Dump completed'; then
        echo "ERRORE: dump incompleto per $site" >&2
        exit 1
    fi
    tar -tzf "$dest/$site/files.tar.gz" > /dev/null
done <<< "$sites"

echo "Fatto: $dest (appoggio in $STAGING_DIR, da cancellare a fine lavoro)"
