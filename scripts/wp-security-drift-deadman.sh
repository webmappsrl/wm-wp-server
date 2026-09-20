#!/usr/bin/env bash
# wp-security-drift-deadman.sh
# Dead-man's-switch — segnala su Slack se lo script principale si ferma — oc:8558
set -uo pipefail

HEARTBEAT_FILE="${HEARTBEAT_FILE:-/root/state/wp-security-drift-heartbeat}"
MAX_AGE_SECONDS="${MAX_AGE_SECONDS:-5400}"
SLACK_WEBHOOK_URL_FILE="${SLACK_WEBHOOK_URL_FILE:-/root/.wp-security-slack-webhook}"

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
        [ ! -f "$SLACK_WEBHOOK_URL_FILE" ] || [ ! -s "$SLACK_WEBHOOK_URL_FILE" ] && \
            { echo "ERRORE: SLACK_WEBHOOK_URL_FILE non configurato o vuoto" >&2; exit 1; }

        local webhook_url
        webhook_url=$(cat "$SLACK_WEBHOOK_URL_FILE")

        local message="Il check wp-security-drift-check non ha aggiornato l'heartbeat entro la finestra attesa (max ${MAX_AGE_SECONDS}s)."

        local http_code
        http_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST -H 'Content-type: application/json' \
            --data "$(jq -n --arg text "$message" '{text: $text}')" \
            "$webhook_url")

        if [ "$http_code" != "200" ]; then
            echo "ERRORE: invio Slack fallito, HTTP $http_code" >&2
            exit 1
        fi
        exit 1
    fi
    exit 0
}

if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
