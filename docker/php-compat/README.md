# Ambiente di test di compatibilità PHP

> Ticket: oc:8834

Riproduce in locale lo stack del server WordPress (Apache + mod_php) per provare un sito su
una versione di PHP diversa da quella di produzione, senza che il sito possa raggiungere
internet.

## Come è fatto

- `web`: immagine ufficiale `php:<versione>-apache` con le stesse estensioni del server
  (`Dockerfile`) e i valori di `php.ini` del server (`php.ini`). Serve un sito alla volta in
  HTTPS, con la docroot montata **allo stesso percorso di produzione**: `.htaccess` e `.user.ini`
  dei siti usano percorsi assoluti (WAF di Wordfence).
- `db`: `mysql:8.0`, come il server (MySQL 8.0.46).
- `edge`: inoltro TCP che pubblica `127.0.0.1:8443` sul Mac. `web` e `db` stanno solo sulla rete
  `isolated` (`internal: true`), quindi non escono su internet; `edge` è l'unico con un'uscita e
  non esegue codice dei siti.
- `mu-plugins/oc8834-no-outbound.php`: seconda barriera, blocca `wp_mail` e le richieste HTTP
  uscenti di WordPress. `import-site.sh` lo copia nella copia di lavoro, mai in produzione.

## Uso

```bash
# 1. backup del sito senza media (codice + dump), dal server al disco esterno
scripts/php-migration/backup-sites.sh "/Volumes/Crucial X6/Siti Webmapp/oc_8834/backup" parcopan.org

# 2. import nel container, sulla versione di PHP voluta
PHP_VERSION=8.4.27 scripts/php-migration/import-site.sh \
    "/Volumes/Crucial X6/Siti Webmapp/oc_8834/backup/<AAAAMMGG-HHMM>/parcopan.org" parcopan.org

# 3. smoke test con lo stesso URL di produzione, e lettura dei log PHP
scripts/php-migration/smoke-test.sh parcopan.org --local
scripts/php-migration/classify-php-log.sh docker/php-compat/logs/php-error.log

# 4. a fine test
docker compose -p oc8834 -f docker/php-compat/compose.yml down -v
```

Se un sito ha nomi di file che differiscono solo per maiuscole (sicai: `src/Views` e
`src/views` nello stesso plugin), appoggio e copia di lavoro devono stare su un file system
case-sensitive, perché l'APFS di default non lo è:

```bash
hdiutil create -size 60g -type SPARSE -fs "Case-sensitive APFS" -volname oc8834-cs ~/oc8834-cs.sparseimage
hdiutil attach ~/oc8834-cs.sparseimage -nobrowse -mountpoint /Volumes/oc8834-cs
export STAGING_DIR=/Volumes/oc8834-cs/staging WORK_DIR=/Volumes/oc8834-cs/work
```

Per provare tutti i siti su più versioni in un colpo solo c'è
`scripts/php-migration/run-compat-tests.sh <backup> <risultati> 8.3.36 8.4.27`.

`PHP_VERSION` accetta qualunque tag `*-apache` dell'immagine ufficiale (provati `8.4.27` e
`8.3.36`). Il test dell'ambiente è `PHP_VERSION=<versione> bash tests/test-php-compat-env.sh`.

I dump contengono dati personali (clienti, ordini): restano sul disco esterno e i container si
cancellano a fine test.
