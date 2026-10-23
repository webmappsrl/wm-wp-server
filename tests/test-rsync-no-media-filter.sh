#!/usr/bin/env bash
# Test del filtro rsync "senza media" — oc:8834
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$SCRIPT_DIR/../scripts/php-migration/rsync-no-media.filter"

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

# Crea una docroot finta con i file indicati e restituisce l'elenco dei file
# che rsync copierebbe applicando il filtro.
copied_files() {
    local tmp f
    tmp=$(mktemp -d)
    mkdir -p "$tmp/src" "$tmp/dst"
    for f in "$@"; do
        mkdir -p "$tmp/src/$(dirname "$f")"
        echo x > "$tmp/src/$f"
    done
    rsync -a --dry-run --out-format='%n' --filter="merge $FILTER" "$tmp/src/" "$tmp/dst/" \
        | grep -v '/$' | sort
    rm -rf "$tmp"
}

# copied <file> <elenco>: "si" se il file compare nell'elenco dei copiati
copied() {
    grep -qxF "$1" <<< "$2" && echo si || echo no
}

test_filter_excludes_year_folders() {
    local out
    out=$(copied_files wp-content/uploads/2024/05/a.jpg wp-content/uploads/2024/05/a.php)
    assert_eq "cartella anno: immagine esclusa" no "$(copied wp-content/uploads/2024/05/a.jpg "$out")"
    assert_eq "cartella anno: anche un .php è escluso" no "$(copied wp-content/uploads/2024/05/a.php "$out")"
}

test_filter_excludes_media_everywhere() {
    local out
    out=$(copied_files wp-content/uploads/slider/b.png wp-content/uploads/import/c.pdf \
        wp-content/uploads/vtour/d.mp4 wp-content/uploads/x/e.zip)
    assert_eq "media fuori dalle cartelle anno: png" no "$(copied wp-content/uploads/slider/b.png "$out")"
    assert_eq "media fuori dalle cartelle anno: pdf" no "$(copied wp-content/uploads/import/c.pdf "$out")"
    assert_eq "media fuori dalle cartelle anno: mp4" no "$(copied wp-content/uploads/vtour/d.mp4 "$out")"
    assert_eq "media fuori dalle cartelle anno: zip" no "$(copied wp-content/uploads/x/e.zip "$out")"
}

test_filter_excludes_uppercase_media() {
    local out
    out=$(copied_files wp-content/uploads/x/IMG_001.JPG wp-content/uploads/x/doc.PDF wp-content/uploads/x/f.Png)
    assert_eq "estensione maiuscola: JPG" no "$(copied wp-content/uploads/x/IMG_001.JPG "$out")"
    assert_eq "estensione maiuscola: PDF" no "$(copied wp-content/uploads/x/doc.PDF "$out")"
    assert_eq "estensione mista: Png" no "$(copied wp-content/uploads/x/f.Png "$out")"
}

test_filter_keeps_assets() {
    local out
    out=$(copied_files wp-content/uploads/us-assets/site.css wp-content/uploads/js_composer/custom.css \
        wp-content/uploads/smile_fonts/f/f.woff wp-content/uploads/wpml/x.json wp-content/uploads/cache/a.js)
    assert_eq "asset: us-assets css" si "$(copied wp-content/uploads/us-assets/site.css "$out")"
    assert_eq "asset: js_composer css" si "$(copied wp-content/uploads/js_composer/custom.css "$out")"
    assert_eq "asset: smile_fonts woff" si "$(copied wp-content/uploads/smile_fonts/f/f.woff "$out")"
    assert_eq "asset: wpml json" si "$(copied wp-content/uploads/wpml/x.json "$out")"
    assert_eq "asset: cache js" si "$(copied wp-content/uploads/cache/a.js "$out")"
}

test_filter_keeps_assets_with_year_in_name() {
    local out
    out=$(copied_files wp-content/uploads/us-assets/2024-theme.css wp-content/uploads/fonts/2025/x.woff2)
    assert_eq "asset con anno nel nome" si "$(copied wp-content/uploads/us-assets/2024-theme.css "$out")"
    assert_eq "cartella anno non in testa a uploads" si "$(copied wp-content/uploads/fonts/2025/x.woff2 "$out")"
}

test_filter_keeps_code_outside_uploads() {
    local out
    out=$(copied_files wp-content/plugins/p/logo.png wp-content/themes/t/screenshot.jpg wp-config.php .htaccess \
        wp-content/plugins/p/2024/x.php)
    assert_eq "png di un plugin" si "$(copied wp-content/plugins/p/logo.png "$out")"
    assert_eq "jpg di un tema" si "$(copied wp-content/themes/t/screenshot.jpg "$out")"
    assert_eq "wp-config.php" si "$(copied wp-config.php "$out")"
    assert_eq ".htaccess" si "$(copied .htaccess "$out")"
    assert_eq "cartella anno dentro un plugin" si "$(copied wp-content/plugins/p/2024/x.php "$out")"
}

test_filter_excludes_year_folders
test_filter_excludes_media_everywhere
test_filter_excludes_uppercase_media
test_filter_keeps_assets
test_filter_keeps_assets_with_year_in_name
test_filter_keeps_code_outside_uploads

exit "$FAIL"
