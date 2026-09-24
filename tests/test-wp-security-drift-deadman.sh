#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/wp-security-drift-deadman.sh" --source-only

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

test_heartbeat_is_stale_when_file_missing() {
    local rc=0
    heartbeat_is_stale "/tmp/non-esiste-$$" 5400 "$(date +%s)" || rc=$?
    assert_eq "file assente è considerato stale" "0" "$rc"
}

test_heartbeat_is_stale_when_too_old() {
    local tmp
    tmp=$(mktemp)
    touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '-2 hours' +%Y%m%d%H%M)" "$tmp"
    local rc=0
    heartbeat_is_stale "$tmp" 5400 "$(date +%s)" || rc=$?
    assert_eq "un heartbeat vecchio di 2h con soglia 90min è stale" "0" "$rc"
    rm -f "$tmp"
}

test_heartbeat_is_fresh_when_recent() {
    local tmp
    tmp=$(mktemp)
    local rc=0
    heartbeat_is_stale "$tmp" 5400 "$(date +%s)" || rc=$?
    assert_eq "un heartbeat appena scritto non è stale" "1" "$rc"
    rm -f "$tmp"
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

test_main_notifies_once_then_suppresses_while_stale() {
    local tmp port pid rc=0
    tmp=$(mktemp -d)
    touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '-2 hours' +%Y%m%d%H%M)" "$tmp/heartbeat"
    port=18300
    pid=$(start_mock_http_server "$port" 200)
    sleep 2
    printf 'http://127.0.0.1:%s/webhook\n' "$port" > "$tmp/webhook"

    local HEARTBEAT_FILE="$tmp/heartbeat"
    local MAX_AGE_SECONDS=5400
    local SLACK_WEBHOOK_URL_FILE="$tmp/webhook"
    local NOTIFIED_MARKER_FILE="$tmp/notified"
    local LOG_FILE="$tmp/log"

    rc=0
    ( set +e; main ) || rc=$?
    assert_eq "prima invocazione stale: exit 1 (notifica inviata)" "1" "$rc"
    assert_eq "marker di notifica creato" "ok" "$([ -f "$NOTIFIED_MARKER_FILE" ] && echo ok || echo mancante)"
    wait "$pid" 2>/dev/null || true

    # Seconda invocazione, heartbeat ancora stale: nessun server mock in ascolto — se
    # provasse a inviare di nuovo, il curl fallirebbe e basta a dimostrare che NON sta
    # rispedendo (altrimenti l'assert sul log sotto fallirebbe per l'errore di invio).
    rc=0
    ( set +e; main ) || rc=$?
    assert_eq "seconda invocazione, ancora stale: exit 1 senza reinviare" "1" "$rc"
    local log_lines
    log_lines=$([ -f "$LOG_FILE" ] && grep -c . "$LOG_FILE" || echo 0)
    assert_eq "nessuna riga di log aggiunta alla seconda invocazione (soppressa prima di tentare l'invio)" "0" "$log_lines"

    rm -rf "$tmp"
}

test_main_clears_marker_when_heartbeat_fresh_again() {
    local tmp rc=0
    tmp=$(mktemp -d)
    touch "$tmp/heartbeat"
    touch "$tmp/notified"

    local HEARTBEAT_FILE="$tmp/heartbeat"
    local MAX_AGE_SECONDS=5400
    local NOTIFIED_MARKER_FILE="$tmp/notified"

    rc=0
    ( set +e; main ) || rc=$?
    assert_eq "heartbeat di nuovo fresco: exit 0" "0" "$rc"
    assert_eq "marker di notifica rimosso" "ok" "$([ -f "$NOTIFIED_MARKER_FILE" ] || echo ok)"

    rm -rf "$tmp"
}

test_main_logs_on_slack_send_failure() {
    local tmp port pid rc=0
    tmp=$(mktemp -d)
    touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '-2 hours' +%Y%m%d%H%M)" "$tmp/heartbeat"
    port=18301
    pid=$(start_mock_http_server "$port" 500)
    sleep 2
    printf 'http://127.0.0.1:%s/webhook\n' "$port" > "$tmp/webhook"

    local HEARTBEAT_FILE="$tmp/heartbeat"
    local MAX_AGE_SECONDS=5400
    local SLACK_WEBHOOK_URL_FILE="$tmp/webhook"
    local NOTIFIED_MARKER_FILE="$tmp/notified"
    local LOG_FILE="$tmp/log"

    rc=0
    ( set +e; main ) || rc=$?
    assert_eq "invio fallito: exit 1" "1" "$rc"
    local count
    count=$([ -f "$LOG_FILE" ] && grep -c "invio Slack fallito" "$LOG_FILE" || echo 0)
    assert_eq "il fallimento di invio viene scritto nel log, non solo su stderr" "1" "$count"
    assert_eq "nessun marker creato su invio fallito (va ritentato al prossimo giro)" "ok" "$([ -f "$NOTIFIED_MARKER_FILE" ] || echo ok)"
    wait "$pid" 2>/dev/null || true

    rm -rf "$tmp"
}

test_heartbeat_is_stale_when_file_missing
test_heartbeat_is_stale_when_too_old
test_heartbeat_is_fresh_when_recent
test_main_notifies_once_then_suppresses_while_stale
test_main_clears_marker_when_heartbeat_fresh_again
test_main_logs_on_slack_send_failure

exit $FAIL
