#!/usr/bin/env bash
# wp-security-drift-deadman.sh
# Dead-man's-switch — segnala su Slack se lo script principale si ferma — oc:8558
set -uo pipefail

HEARTBEAT_FILE="${HEARTBEAT_FILE:-/root/state/wp-security-drift-heartbeat}"
MAX_AGE_SECONDS="${MAX_AGE_SECONDS:-5400}"
SLACK_WEBHOOK_URL_FILE="${SLACK_WEBHOOK_URL_FILE:-/root/.wp-security-slack-webhook}"
# Marker di "già notificato, ancora stale": evita di rispedire lo stesso alert Slack a ogni
# invocazione (cron ogni 15 min) finché il problema persiste — stesso principio di
# should_notify/clear_resolved nello script principale, qui semplificato a un file singolo
# perché il deadman ha un solo "check" possibile (trovato in review 24/09/2026).
NOTIFIED_MARKER_FILE="${NOTIFIED_MARKER_FILE:-/root/state/wp-security-drift-deadman-notified}"
# Stesso log dello script principale: un fallimento di invio qui va scritto da qualche parte
# di persistente, non solo su stderr (requisito esplicito overview.md), altrimenti il
# fallimento del fallback stesso passa inosservato.
LOG_FILE="${LOG_FILE:-/var/log/wp-security-drift-check.log}"

log() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    echo "$(date '+%F %T') - [deadman] $1" >> "$LOG_FILE"
}

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
        if [ -f "$NOTIFIED_MARKER_FILE" ]; then
            # Già notificato per questo episodio di stale: non rispedire lo stesso alert.
            exit 1
        fi

        if [ ! -f "$SLACK_WEBHOOK_URL_FILE" ] || [ ! -s "$SLACK_WEBHOOK_URL_FILE" ]; then
            log "ERRORE: SLACK_WEBHOOK_URL_FILE non configurato o vuoto"
            exit 1
        fi

        local webhook_url
        webhook_url=$(cat "$SLACK_WEBHOOK_URL_FILE")

        local message="Il check wp-security-drift-check non ha aggiornato l'heartbeat entro la finestra attesa (max ${MAX_AGE_SECONDS}s)."

        local http_code
        http_code=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" -X POST -H 'Content-type: application/json' \
            --data "$(jq -n --arg text "$message" '{text: $text}')" \
            "$webhook_url")

        if [ "$http_code" != "200" ]; then
            log "ERRORE: invio Slack fallito, HTTP $http_code"
            exit 1
        fi

        mkdir -p "$(dirname "$NOTIFIED_MARKER_FILE")" 2>/dev/null || true
        touch "$NOTIFIED_MARKER_FILE"
        exit 1
    fi

    # Heartbeat di nuovo fresco: se c'era un marker di notifica precedente, il problema si è
    # risolto — lo rimuoviamo così una futura ricomparsa viene trattata come nuova e notificata.
    rm -f "$NOTIFIED_MARKER_FILE"
    exit 0
}

if [[ "${1:-}" != "--source-only" ]]; then
    main "$@"
fi
