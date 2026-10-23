---
paths:
  - "scripts/php-migration/**"
  - "docker/php-compat/**"
---

# Trappole: script di migrazione PHP e ambiente Docker di test

- Il disco esterno è exFAT con blocchi da 512 KB: un albero di file WordPress lo riempie (circa 10 GB per sito) — i file vanno in un archivio `files.tar.gz` per sito (oc:8834)
- L'APFS del Mac non distingue le maiuscole: sicai ha `src/Views` e `src/views` nello stesso plugin e rsync fallisce — appoggio e copie di lavoro su un'immagine Case-sensitive APFS, vedi `docker/php-compat/README.md` (oc:8834)
- Con `WP_DEBUG=false` WordPress scarta le Deprecated e il conteggio esce 0 — nel `wp-config.php` locale `WP_DEBUG=true` con display e debug.log spenti (oc:8834)
- Una pagina `/wp-admin/*` senza accesso fa redirect al login, che risponde 200 — controllare `id="adminmenu"` nel body (oc:8834)
- Col carrello vuoto il checkout WooCommerce fa redirect al carrello, che risponde 200 — controllare URL finale e form del checkout, con un prodotto semplice e disponibile (oc:8834)
- `ssh` dentro un `while read` consuma lo stdin del ciclo e lo interrompe dopo il primo giro — `ssh -n` (oc:8834)
- Su macOS `zcat` cerca file `.Z` — usare `gzip -dc` (oc:8834)
- Una rete Docker `internal` non pubblica porte — la porta la espone il container `edge`, l'unico con un'uscita (oc:8834)
- Caricare WordPress come root sul server (es. `wp user list`) esegue plugin e tema, comprese eventuali backdoor — per leggere dati usare `wp config get` e `wp db query`, che non caricano WordPress (oc:8834)
- Nel container i widget della bacheca di `wp-geohub` e `wm-package` vanno in errore perché Geohub non è raggiungibile — è un effetto dei test, non della versione di PHP (oc:8834)
