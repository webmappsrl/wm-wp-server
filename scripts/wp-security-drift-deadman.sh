#!/usr/bin/env bash
# wp-security-drift-deadman.sh
# Dead-man's-switch indipendente da Slack — oc:8558
set -uo pipefail

HEARTBEAT_FILE="${HEARTBEAT_FILE:-/root/state/wp-security-drift-heartbeat}"
MAX_AGE_SECONDS="${MAX_AGE_SECONDS:-5400}"
MAIL_TO="${MAIL_TO:-}"

heartbeat_is_stale() {
    local heartbeat_file="$1"
    local max_age="$2"
    local now="$3"

    [ -f "$heartbeat_file" ] || return 0

    local last_run age
    last_run=$(stat -c %Y "$heartbeat_file" 2>/dev/null || stat -f %m "$heartbeat_file" 2>/dev/null)
    age=$((now - last_run))

    [ "$age" -gt "$max_age" ] && return 0
    return 1
}

main() {
    local now
    now=$(date +%s)
    if heartbeat_is_stale "$HEARTBEAT_FILE" "$MAX_AGE_SECONDS" "$now"; then
        [ -z "$MAIL_TO" ] && { echo "ERRORE: MAIL_TO non configurato" >&2; exit 1; }
        echo "Il check wp-security-drift-check non ha aggiornato l'heartbeat entro la finestra attesa (max ${MAX_AGE_SECONDS}s)." \
            | mail -s "[ALERT] wp-security-drift-check fermo su wordpress-php8" "$MAIL_TO"
        exit 1
    fi
    exit 0
}

if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
