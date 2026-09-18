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

test_heartbeat_is_stale_when_file_missing
test_heartbeat_is_stale_when_too_old
test_heartbeat_is_fresh_when_recent

exit $FAIL
