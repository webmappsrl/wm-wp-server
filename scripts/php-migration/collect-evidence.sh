#!/usr/bin/env bash
# collect-evidence.sh
# Conservazione delle tracce prima di intervenire sul server — oc:8834
#
# Uso (dal Mac): collect-evidence.sh <cartella-destinazione> [data-inizio]
# Crea <dest>/evidenze-<AAAAMMGG-HHMM>/ con i log Apache, l'elenco dei file modificati,
# gli amministratori WordPress, cron, timer e processi del server, più SHA256SUMS.
# Sul server legge soltanto: non crea né modifica file. data-inizio di default 2026-10-19
# (il giorno prima della divulgazione di PHP2Shell).
set -euo pipefail

SSH_HOST="${SSH_HOST:-php8}"
VOLUME="/mnt/HC_Volume_102677298"

if [ $# -lt 1 ]; then
    echo "Uso: $0 <cartella-destinazione> [data-inizio AAAA-MM-GG]" >&2
    exit 2
fi
since="${2:-2026-10-19}"
out="$1/evidenze-$(date +%Y%m%d-%H%M)"
mkdir -p "$out/logs"

docroots=$(ssh "$SSH_HOST" "grep -hv '^[[:space:]]*#' /etc/apache2/sites-enabled/*.conf \
    | awk '\$1 == \"DocumentRoot\" {print \$2}' | sort -u")
echo "Docroot: $(wc -l <<< "$docroots" | tr -d ' ')"

echo "Log Apache dal $since"
ssh "$SSH_HOST" "find /var/log/apache2 $VOLUME/logs -type f -newermt $since" \
    | rsync -a --files-from=- "$SSH_HOST:/" "$out/logs/"

echo "File modificati dal $since"
# shellcheck disable=SC2086 # le docroot sono una per riga, senza spazi
ssh "$SSH_HOST" "find $(tr '\n' ' ' <<< "$docroots") /tmp /var/tmp /dev/shm /etc /root -xdev \
    -path /root/backups -prune -o -newermt $since \
    -printf '%TY-%Tm-%Td %TH:%TM\t%u\t%m\t%s\t%p\n' 2>/dev/null | sort" \
    > "$out/files-modified-since-${since//-/}.tsv"

echo "Amministratori WordPress"
# Query diretta sul DB: `wp config get` e `wp db query` leggono wp-config.php senza caricare
# WordPress, quindi plugin, tema ed eventuali backdoor non vengono eseguiti come root.
while IFS= read -r root; do
    echo "## $root"
    ssh -n "$SSH_HOST" "cd '$root' && p=\$(wp --allow-root config get table_prefix) && \
        wp --allow-root db query \"SELECT u.ID, u.user_login, u.user_email, u.user_registered \
        FROM \${p}users u JOIN \${p}usermeta m ON m.user_id = u.ID \
        WHERE m.meta_key = '\${p}capabilities' AND m.meta_value LIKE '%administrator%' ORDER BY u.ID\" 2>&1"
done <<< "$docroots" > "$out/wp-admins.tsv"

echo "Cron, timer e processi"
ssh "$SSH_HOST" 'for u in root www-data; do echo "## crontab $u"; crontab -l -u "$u" 2>&1; done
    echo "## /etc/crontab"; cat /etc/crontab
    for d in /etc/cron.d /etc/cron.hourly /etc/cron.daily /etc/cron.weekly /etc/cron.monthly; do
        echo "## $d"; ls -la --time-style=long-iso "$d"; done
    echo "## systemd timers"; systemctl list-timers --all --no-pager' > "$out/crontab.txt"
ssh "$SSH_HOST" 'ps auxww' > "$out/processes.txt"

( cd "$out" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 shasum -a 256 > SHA256SUMS )
echo "Fatto: $out"
