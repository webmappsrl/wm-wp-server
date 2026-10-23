#!/usr/bin/env bash
# Test del classificatore dei log PHP — oc:8834
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLASSIFY="$SCRIPT_DIR/../scripts/php-migration/classify-php-log.sh"
source "$CLASSIFY" --source-only

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

# Prima riga dell'output: i conteggi
counts() {
    classify_php_log "$1" | head -1 || true
}

test_classify_counts_levels() {
    local f
    f=$(mktemp)
    cat > "$f" <<'EOF'
[22-Oct-2026 10:00:00 UTC] PHP Fatal error:  Cannot redeclare foo() in /var/www/a.php on line 3
[22-Oct-2026 10:00:01 UTC] PHP Fatal error:  Allowed memory size exhausted in /var/www/b.php on line 9
[22-Oct-2026 10:00:02 UTC] PHP Warning:  Undefined array key "x" in /var/www/c.php on line 1
[22-Oct-2026 10:00:03 UTC] PHP Warning:  Undefined variable $y in /var/www/c.php on line 2
[22-Oct-2026 10:00:04 UTC] PHP Warning:  foreach() argument must be of type array in /var/www/c.php on line 4
[22-Oct-2026 10:00:05 UTC] PHP Deprecated:  Implicitly marking parameter $a as nullable is deprecated in /var/www/d.php on line 1
[22-Oct-2026 10:00:05 UTC] PHP Deprecated:  Implicitly marking parameter $b as nullable is deprecated in /var/www/d.php on line 2
[22-Oct-2026 10:00:05 UTC] PHP Deprecated:  Implicitly marking parameter $c as nullable is deprecated in /var/www/d.php on line 3
[22-Oct-2026 10:00:05 UTC] PHP Deprecated:  Creation of dynamic property X::$z is deprecated in /var/www/e.php on line 5
[22-Oct-2026 10:00:05 UTC] PHP Deprecated:  strftime() is deprecated in /var/www/f.php on line 6
EOF
    assert_eq "conteggio per livello" "fatal=2 warning=3 deprecated=5 notice=0" "$(counts "$f")"
    rm -f "$f"
}

test_classify_counts_uncaught_once() {
    local f
    f=$(mktemp)
    cat > "$f" <<'EOF'
[22-Oct-2026 10:00:00 UTC] PHP Fatal error:  Uncaught TypeError: count(): Argument #1 ($value) must be of type Countable|array, null given in /var/www/a.php:10
Stack trace:
#0 /var/www/a.php(10): count(NULL)
#1 /var/www/wp-includes/class-wp-hook.php(324): foo('')
#2 /var/www/wp-includes/class-wp-hook.php(348): WP_Hook->apply_filters(NULL, Array)
#3 /var/www/wp-includes/plugin.php(517): WP_Hook->do_action(Array)
#4 /var/www/wp-settings.php(700): do_action('init')
#5 {main}
  thrown in /var/www/a.php on line 10
EOF
    assert_eq "Uncaught con stack trace conta uno" "fatal=1 warning=0 deprecated=0 notice=0" "$(counts "$f")"
    rm -f "$f"
}

test_classify_parse_error_is_fatal() {
    local f
    f=$(mktemp)
    echo '[22-Oct-2026 10:00:00 UTC] PHP Parse error:  syntax error, unexpected token "}" in /var/www/a.php on line 3' > "$f"
    assert_eq "Parse error è fatal" "fatal=1 warning=0 deprecated=0 notice=0" "$(counts "$f")"
    rm -f "$f"
}

test_classify_exit_code() {
    local f rc
    f=$(mktemp)
    echo '[22-Oct-2026 10:00:00 UTC] PHP Deprecated:  strftime() is deprecated in /var/www/a.php on line 1' > "$f"
    rc=0; classify_php_log "$f" > /dev/null || rc=$?
    assert_eq "solo Deprecated: exit 0" 0 "$rc"
    echo '[22-Oct-2026 10:00:01 UTC] PHP Fatal error:  boom in /var/www/a.php on line 2' >> "$f"
    rc=0; classify_php_log "$f" > /dev/null || rc=$?
    assert_eq "con un Fatal: exit 1" 1 "$rc"
    rm -f "$f"
}

test_classify_apache_error_log_format() {
    local f
    f=$(mktemp)
    cat > "$f" <<'EOF'
[Wed Oct 22 10:00:00.123456 2026] [php:error] [pid 1234] [client 1.2.3.4:5678] PHP Fatal error:  Uncaught Error: Call to undefined function mysql_connect() in /var/www/a.php:3
[Wed Oct 22 10:00:01.123456 2026] [php:warn] [pid 1234] [client 1.2.3.4:5678] PHP Warning:  Undefined array key "x" in /var/www/b.php on line 1, referer: https://example.org/
[Wed Oct 22 10:00:02.123456 2026] [php:notice] [pid 1234] [client 1.2.3.4:5678] PHP Notice:  Function _load_textdomain_just_in_time was called incorrectly in /var/www/c.php on line 6
EOF
    assert_eq "formato error.log di Apache" "fatal=1 warning=1 deprecated=0 notice=1" "$(counts "$f")"
    rm -f "$f"
}

test_classify_lists_fatal_and_warning_once() {
    local f out
    f=$(mktemp)
    cat > "$f" <<'EOF'
[22-Oct-2026 10:00:00 UTC] PHP Warning:  Undefined array key "x" in /var/www/c.php on line 1
[22-Oct-2026 10:00:09 UTC] PHP Warning:  Undefined array key "x" in /var/www/c.php on line 1
[22-Oct-2026 10:00:10 UTC] PHP Deprecated:  strftime() is deprecated in /var/www/f.php on line 6
EOF
    out=$(classify_php_log "$f" | tail -n +2)
    assert_eq "warning ripetuto elencato una volta" 1 "$(grep -c 'Undefined array key' <<< "$out")"
    assert_eq "deprecated non elencato" 0 "$(grep -c 'strftime' <<< "$out" || true)"
    rm -f "$f"
}

test_classify_counts_levels
test_classify_counts_uncaught_once
test_classify_parse_error_is_fatal
test_classify_exit_code
test_classify_apache_error_log_format
test_classify_lists_fatal_and_warning_once

exit "$FAIL"
