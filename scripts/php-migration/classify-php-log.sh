#!/usr/bin/env bash
# classify-php-log.sh
# Classifica un log PHP per livello — oc:8834
#
# Uso: classify-php-log.sh <file-log>
# Prima riga: "fatal=<n> warning=<n> deprecated=<n> notice=<n>". Seguono le righe fatal e
# warning senza duplicati (senza la data in testa). Exit 1 se fatal>0, altrimenti 0.
# Le righe di stack trace ("Stack trace:", "#<n> ", "thrown in") non contano: un Uncaught
# con trace è un fatal solo. Accetta sia il formato di error_log PHP sia l'error.log di Apache.
set -uo pipefail

classify_php_log() {
    local file="$1"
    awk '
        # Toglie data e prefissi Apache ([php:error] [pid ..] [client ..]) per deduplicare.
        function message(line) {
            sub(/^.*PHP /, "PHP ", line)
            sub(/, referer: .*$/, "", line)
            return line
        }
        /PHP (Fatal error|Parse error):/ { fatal++;      m = message($0); if (!(m in seen)) { seen[m] = 1; listed[++n] = m }; next }
        /PHP Warning:/                   { warning++;    m = message($0); if (!(m in seen)) { seen[m] = 1; listed[++n] = m }; next }
        /PHP Deprecated:/                { deprecated++; next }
        /PHP Notice:/                    { notice++;     next }
        END {
            printf "fatal=%d warning=%d deprecated=%d notice=%d\n", fatal, warning, deprecated, notice
            for (i = 1; i <= n; i++) print listed[i]
            exit (fatal > 0 ? 1 : 0)
        }
    ' "$file"
}

if [ "${1:-}" = "--source-only" ]; then
    return 0 2>/dev/null || exit 0
fi

if [ $# -ne 1 ] || [ ! -r "$1" ]; then
    echo "Uso: $0 <file-log>" >&2
    exit 2
fi

classify_php_log "$1"
