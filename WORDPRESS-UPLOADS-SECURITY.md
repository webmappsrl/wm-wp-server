# WordPress malware remediation — handoff operativo

> Recap del lavoro già eseguito (plan Cursor completed) sul server multi-sito  
> `/root/html` → `/var/www/html`.  
> Scopo: far ripartire un agente/operatore **senza rifare da zero** se il problema torna.
>
> Data incidente / remediation: **2026-09-09 → 2026-09-10**.  
> Fonte di verità dei passi: plan in `/root/.cursor/plans/`.

## Problema (IOC)

Payload ricorrente su più vhost:

- `index.php` / `index.html` sostituiti con **falsa pagina di manutenzione**
- redirect mobile / inject verso **`ushort.company`**
- colpiti anche `index.php` di **root** e **`wp-admin/index.php`**
- in `wp-content`: centinaia di `index.php`/`index.html` usati come tappi di directory, più alcuni **bootstrap reali di plugin** sovrascritti
- su trekking: webshell in `uploads/` (`s.php`, `uploads/wp-login.php` fake)

**Siti trattati (solo questi quattro):**

| Sito | Versione core dopo remediation |
|------|--------------------------------|
| `parco-maremma.it` | **6.8.2** |
| `parcopan.org` | **6.8.8** |
| `trekking.parcoforestecasentinesi.it` | **6.8.8** |
| `sentierodeiducati.it` | **6.8.1** |

**Non toccati nella bonifica:** altri vhost sotto `~/html`, password utenti, aggiornamenti a WP 7.x, cancellazione massiva di contenuti/media.

### Estensione hardening volume (2026-09-14)

**`european-mountaineers.eu`**, **`outcropedia.org`**, **`selfguided-toscana.it`** e **`acquasorgente.cai.it`** (`/mnt/HC_Volume_102677298/html/…`) **non** hanno avuto IOC `ushort.company` né rsync bonifica. Hanno ricevuto lo **stesso modello** di lock write (`DISALLOW_*`, owner `root:www-data`, `upgrade/` non scrivibile) e inclusione nel cron IOC uploads. Dettaglio operativo: [`WORDPRESS-EUMA-HANDOFF.md`](/root/docs/WORDPRESS-EUMA-HANDOFF.md), [`WORDPRESS-OUTCROPEDIA-HANDOFF.md`](/root/docs/WORDPRESS-OUTCROPEDIA-HANDOFF.md), [`WORDPRESS-SELFGUIDED-HANDOFF.md`](/root/docs/WORDPRESS-SELFGUIDED-HANDOFF.md), [`WORDPRESS-ACQUASORGENTE-HANDOFF.md`](/root/docs/WORDPRESS-ACQUASORGENTE-HANDOFF.md). Aggiornamenti core/plugin: [`WORDPRESS-CORE-PLUGIN-UPDATES.md`](WORDPRESS-CORE-PLUGIN-UPDATES.md) → sezione **Perimetro volume**.

---

## Ordine reale dei plan eseguiti

Tutti i seguenti risultano **completed** (tranne note esplicite). Path plan: `/root/.cursor/plans/<file>`.

### 1. `ripristino_parco-maremma_d4a2465e` — Ripristino parco-maremma

**Cosa:** bonifica pilota su `parco-maremma.it`.

1. Scaricare pacchetto ufficiale **`wordpress-6.8.2`** (non più nuovo).
2. Sovrascrivere solo:
   - `wp-admin/` e `wp-includes/` con `rsync --delete` (toglie anche `index.html` malware assenti dal core pulito)
   - PHP di root del pacchetto (`index.php`, `wp-login.php`, `xmlrpc.php`, `wp-settings.php`, …)
3. **Non** copiare `wp-content` dal pacchetto; **non** toccare `wp-config.php`, `.htaccess`, uploads, child theme.
4. In `wp-content`: ripristinare stub sui tappi di directory:
   - us-core / Impreza: `<?php // Silence is golden. And we agree :)`
   - altri plugin: `<?php // Silence is golden.`
   - `index.html` malware: svuotati
5. File **non** stub (ricostruiti / da fonte ufficiale):
   - `us-core/templates/index.php` (schema da `templates/archive.php`)
   - `cc-child-pages/index.php` da tag **1.43** wordpress.org
6. Check DB via WP-CLI: `siteurl`/`home`, ricerca `ushort.company`, lista admin; rimuovere solo inject evidenti del malware.
7. Verifica: homepage/login/admin, `version.php` = 6.8.2, grep zero `ushort.company`.

Backup DB già presente (poi spostato):  
`/root/backups/parcomaremma-db-backup-20260909-062320.sql`

### 2. `fix_admin_dashboard_608b5dd1` — Fix admin dashboard (maremma)

**Problema:** wp-admin “bianco” dopo login: HTML si interrompe dopo `#wpwrap`, niente errore JS → **fatal PHP nascosto**.

**Cosa:** diagnosi con `WP_DEBUG_LOG` (display off), individuazione causa (stesso filone **Ultimate_VC_Addons / bsf-core**), fix mirato senza cambiare versione core né password. Verifica dashboard/media/frontend; spegnere debug visibile.

### 3. `backup_db_tre_siti_5be5814b` — Backup DB tre siti

Prima della pulizia degli altri tre:

| Sito | DB (`wp-config`) | Dump (poi spostati fuori webroot) |
|------|------------------|-----------------------------------|
| parcopan.org | `parcopan` | `parcopan-db-backup-20260909-073005.sql` |
| trekking… | `pnfc` | `pnfc-db-backup-20260909-073040.sql` |
| sentierodeiducati.it | `sentierodeiducati` | `sentierodeiducati-db-backup-20260909-073041.sql` |

Metodo: `mysqldump --defaults-extra-file` (cred da `wp-config`, file temp 600) → `--single-transaction --routines --triggers`.

### 4. `pulizia_tre_siti_wp_88976244` — Pulizia tre siti WP

Stesso metodo di maremma, core **6.8.1** (versione già presente, **niente upgrade**).

Procedura comune:
1. `wordpress-6.8.1.tar.gz` ufficiale
2. `rsync --delete` su `wp-admin/` + `wp-includes/`
3. Copia PHP root del pacchetto; mai `wp-config` / `wp-content` dal tarball
4. Stub index malware; ricostruire `us-core/templates/index.php` da `archive.php`
5. Grep `ushort.company` (esclusi dump SQL), check DB, homepage + login

**Differenze per sito:**

| Sito | Extra critico |
|------|----------------|
| **parcopan** | `wp-geohub/index.php` è bootstrap reale → ripristino da **git del plugin** (`git show HEAD:index.php`), non stub |
| **trekking** | UAVC 3.19.9: ripristino `admin/bsf-core/index.php` + guard `function_exists('bsf_registration_page_url')` in `admin/admin.php` (come maremma) |
| **sentieri** | `wp-geohub/index.php` da git plugin; child `wm-caire-child` |

> Nota: esiste anche `cleanup_tre_siti_wp_6f997eb6.plan.md` ancora **pending** (bozza/duplicato). La versione **eseguita** è `pulizia_tre_siti_wp_88976244`.

### 5. `ripristino_wm-package_b7ee87d8` — Ripristino wm-package (trekking)

**Errore di pulizia:** `wm-package/index.php` trattato come stub ma è il bootstrap del plugin → WP lo disattiva (“intestazione non valida”).

**Fix:** `git checkout HEAD -- index.php` nel plugin su trekking; `wp plugin activate wm-package`; verifica header/homepage. Non toccare altri file custom del plugin.

### 6–8. Lock write (hardening scrittura PHP)

Obiettivo: PHP/`www-data` non scrive più su codice (core/plugin/theme/upgrade UI), ma resta WRITE su `uploads/`, `languages/`, `wflogs/` (e su sentieri anche `w3tc-config/`).

| Plan | Sito | Azione |
|------|------|--------|
| `lock_write_trekking_0d1f0298` | trekking | Aggiungere `DISALLOW_FILE_EDIT` + `DISALLOW_FILE_MODS`; `chown/chmod` `wp-content/upgrade` → non scrivibile da PHP; lasciare `FS_METHOD=direct` |
| `lock_write_sentieri_375f3a92` | sentieri | Aggiungere solo `DISALLOW_FILE_EDIT` (`DISALLOW_FILE_MODS` e upgrade già ok) |
| `lock_write_maremma_parcopan_ba6f41ae` | maremma + parcopan | **Solo verifica** (hardening già presente: DISALLOW_*, upgrade locked, 0 `.php` scrivibili in core/plugin/theme) |

Verifica tipica: costanti in `wp-config`, permessi upgrade/uploads, homepage+login 200, niente `ushort.company`, versione core corretta.

### 9. `rimuovi_shell_trekking_uploads_59d21c33` — Shell in uploads trekking

Solo `trekking.../wp-content/uploads/`:

- **Eliminare:** `s.php`, `wp-login.php` (fake, non è il login WP)
- **Stub:** `smile_fonts/Defaults/index.php` → `<?php // Silence is golden.` (`root:www-data`)
- **Non toccare:** cache WPML Twig, `charmap.php`, ecc.

### 10. `sposta_dump_sql_a5465e00` — Dump fuori webroot

Spostati in `/root/backups/` (mode `600`, `root:root`) i dump ancora in document root, così non scaricabili via HTTP. Destinazione fuori da Apache docroot.

### 11. `cron_uploads_ioc_af5f8ca8` — Cron pulizia uploads IOC

1. **Fix `.htaccess` trekking uploads:** rimuovere `Allow from all` su nomi shell; lasciare Deny `.php` + Wordfence no-exec.
2. Script: **`/root/wp_uploads_ioc_clean.sh`**
   - Siti (2026-09-14): **otto** vhost, solo `wp-content/uploads/`:
     - `/var/www/html`: parco-maremma, trekking, parcopan, sentieri
     - `/mnt/HC_Volume_102677298/html`: `european-mountaineers.eu`, `outcropedia.org`, `selfguided-toscana.it`, `acquasorgente.cai.it`
   - Lock: `/tmp/wp_uploads_ioc_clean.lock`
   - Log: `/var/log/wp-uploads-ioc-clean.log`
   - Allowlist (non quarantena): `cache/wpml/twig/**/*.php`, `wpforms/cache/*`, `sucuri/*` (dati scanner Sucuri), `**/charmap.php`, `debug-log.php` con `<?php exit`, stub `Silence is golden`
   - Azioni: stub index con IOC manutenzione/`ushort.company`; altri `.php/.phtml/.phar` → move in `/root/backups/uploads-quarantine/<sito>/...` (retention 180 giorni)
3. Logrotate: `/etc/logrotate.d/wp-uploads-ioc-clean` (14 giorni)
4. Cron iniziale: `30 3 * * *` (poi cambiato, vedi sotto)

### 12. `cron_ogni_mezzora_43f7e1c2` — Cron ogni 30 minuti

Schedulazione aggiornata a:

```cron
*/30 * * * * /root/wp_uploads_ioc_clean.sh
```

Verifica operativa: `tail /var/log/wp-uploads-ioc-clean.log` mostra RUN BEGIN/END ciclici su maremma → trekking → parcopan → sentieri → **european-mountaineers.eu** → **outcropedia.org** → **selfguided-toscana.it** → **acquasorgente.cai.it** (volume con `root=/mnt/HC_Volume_102677298/html`).

---

## Stato hardening `.htaccess` (post-lavoro + audit)

Oltre ai plan, i quattro siti hanno protezioni uploads/root già presenti o sistemate:

| Controllo | maremma | parcopan | sentieri | trekking |
|-----------|---------|----------|----------|----------|
| Wordfence no-exec in `uploads/.htaccess` | Sì | Sì | Sì | Sì |
| FilesMatch anti-php extra | sottocartelle | — | `uploads/cache` | sì in root uploads (+ Deny) |
| Wordfence WAF (`auto_prepend`) | Sì | Sì | Sì | Sì |
| Blocco `xmlrpc.php` (root) | Sì | Sì | No (audit) | No (audit) |
| 410 uploads missing → `410-gone.php` | Sì | Sì | No | No |
| HTTPS Really Simple Security | Sì | Sì | No in root (audit) | Sì |

**EUMA + outcropedia + selfguided + acquasorgente (volume, 2026-09-14):** non in tabella sopra (bonifica diversa). Wordfence WAF `auto_prepend` attivo in root su tutti e quattro. Outcropedia, selfguided e acquasorgente: protezione uploads via Wordfence no-exec (come i quattro siti bonifica). Acquasorgente: allowlist cron `sucuri/*` per file PHP dati scanner Sucuri in uploads.

**Attenzione stack:** `php_flag` in `.htaccess` vale soprattutto con **mod_php**; con **PHP-FPM** verificare che il no-exec sia realmente applicato. Il cron IOC resta la rete di sicurezza su file PHP in uploads.

---

## Igiene EUMA (2026-09-14) — checklist volume

Checklist riutilizzabile per vhost su `/mnt/HC_Volume_102677298/html` (prima di lock write / update):

- Spostare fuori webroot `.wpress` (AI1WM), zip tema, copie WordPress nidificate, debug log in document root
- Correggere `WP_DEBUG` / `WP_DEBUG_LOG` se sono stringhe `'false'` (truthy in PHP)
- Disattivare All-in-One WP Migration in produzione dopo backup
- Lock `root:www-data` su codice; eccezione WRITE: `plugins/euma-tables/logs/` (`770`) per sync API

---

## Playbook se il problema torna

Seguire **questo ordine** (come nella remediation reale):

1. **Backup DB** (mysqldump come plan backup) → spostare subito fuori webroot.
2. **Identificare IOC:** grep `ushort.company`, falsa maintenance, `index.php` root/admin anomali, PHP in uploads fuori allowlist.
3. **Reinstall core ufficiale** della **stessa** versione (`wp-includes/version.php`); `rsync --delete` solo `wp-admin`/`wp-includes` + PHP root; mai sovrascrivere `wp-config` / `wp-content` dal tarball.
4. **Stub** i tappi; **non stubbare** bootstrap plugin reali (`wp-geohub`, `wm-package`, `cc-child-pages`, `bsf-core`, …) → ripristinare da git/tag ufficiale.
5. Se admin bianco: log fatal PHP (pattern UAVC/bsf-core già visto).
6. **Check DB:** siteurl/home, utenti admin, inject malware; non cancellare contenuti a caso.
7. **Lock write** se manca (`DISALLOW_FILE_EDIT/MODS`, upgrade non scrivibile).
8. **Uploads:** rimuovere shell; assicurarsi cron IOC attivo; `.htaccess` senza Allow sulle shell.
9. Verifica: homepage 200, login, admin, grep zero `ushort.company`, versione core invariata.

### Trappole già pagate

- Stubbare `wm-package/index.php` o `wp-geohub/index.php` spegne il plugin.
- Aggiornare il core “di incidentalmente” (maremma 6.8.2 vs altri 6.8.1): **non** allineare le versioni se non richiesto.
- Lasciare dump `.sql` in document root = esfiltrabili via HTTP.
- Su trekking, un `Allow from all` in uploads `.htaccess` riapriva le shell.

---

## Artefatti sul server

| Path | Ruolo |
|------|--------|
| `/root/.cursor/plans/*.plan.md` | Spec dettagliate dei passi |
| `/root/wp_uploads_ioc_clean.sh` | Pulizia periodica uploads |
| `/var/log/wp-uploads-ioc-clean.log` | Log cron |
| `/etc/logrotate.d/wp-uploads-ioc-clean` | Rotazione log |
| `/root/backups/` | Dump SQL + quarantena uploads |
| `/root/backups/uploads-quarantine/` | PHP spostati dal cron |
| `/root/docs/WORDPRESS-UPLOADS-SECURITY.md` | Questo handoff |
| `/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md` | Aggiornamenti core/plugin post-bonifica (WPML, OTGS Installer, chiavi sito, lock write) |
| `/root/docs/WORDPRESS-SENTIERI-HANDOFF.md` | Dettaglio sentierodeiducati.it |
| `/root/docs/WORDPRESS-PARCOPAN-HANDOFF.md` | Dettaglio parcopan.org |
| `/root/docs/WORDPRESS-TREKKING-HANDOFF.md` | Dettaglio trekking.parcoforestecasentinesi.it |
| `/root/docs/WORDPRESS-MAREMMA-HANDOFF.md` | Dettaglio parco-maremma.it |
| `/root/docs/WORDPRESS-EUMA-HANDOFF.md` | Dettaglio EUMA (path volume, backup, smoke) |
| `/root/docs/WORDPRESS-OUTCROPEDIA-HANDOFF.md` | Dettaglio outcropedia (path volume, backup, smoke) |
| `/root/docs/WORDPRESS-SELFGUIDED-HANDOFF.md` | Dettaglio selfguided (path volume, backup, smoke) |
| `/root/docs/WORDPRESS-ACQUASORGENTE-HANDOFF.md` | Dettaglio acquasorgente (path volume, backup, smoke) |

---

## Vincoli globali rispettati in tutta la remediation

- Nessun cambio password
- Nessun upgrade a WordPress 7.x
- Nessuna cancellazione di post/pagine/media legittimi
- **Bonifica malware:** solo i quattro vhost su `/var/www/html`; **hardening/cron IOC** esteso anche a **`european-mountaineers.eu`**, **`outcropedia.org`**, **`selfguided-toscana.it`** e **`acquasorgente.cai.it`** (volume, 2026-09-14)
- Child theme PHP custom lasciati intatti (salvo fix mirati documentati nei plan)

---

## WPML / OTGS Installer (post-remediation)

Gli aggiornamenti WPML **non** fanno parte della bonifica malware; la procedura operativa (installer, chiave sito, ordine String → CMS → add-on, WP-CLI perché `upgrade/` è locked, ri-lock `DISALLOW_*`) è documentata in:

[`WORDPRESS-CORE-PLUGIN-UPDATES.md`](WORDPRESS-CORE-PLUGIN-UPDATES.md) → sezione **WPML**.

Su `sentierodeiducati.it`, `parcopan.org`, `trekking.parcoforestecasentinesi.it` (2026-09-10) e **maremma** (2026-09-14) lo stack WPML è aggiornato — vedi handoff in `/root/docs/WORDPRESS-*-HANDOFF.md`.

**Nota permesso Commercial:** con `DISALLOW_FILE_MODS` true, `plugin-install.php?tab=commercial` risponde «Non hai il permesso di accedere a questa pagina» perché manca `install_plugins`. Per registrare la chiave OTGS commentare temporaneamente i `DISALLOW_*` in `wp-config.php`, poi riattivare. Non sbloccare `wp-content/upgrade/` a `www-data`.

---

## Follow-up 2026-10-01 — backdoor residue trovato fuori dalle webroot

**Contesto:** durante un controllo di routine (oc:8558) emerso un falso allarme Wordfence "sito giù" su `trekking.parcoforestecasentinesi.it`. Approfondendo via Gmail (alert Wordfence "Problems found" + ticket oc:8511/oc:8515), riaperti i 3 file del punto "Hunt completo backdoor" mai chiusi — trovati ancora presenti e funzionanti, rimossi (dettaglio in oc:8511). Durante la verifica che l'hunt coprisse anche gli altri 8 vhost, trovato un quarto artefatto **fuori da qualsiasi webroot**.

### Artefatto trovato: `/usr/share/python3/bcep/index.html`

- Directory di sistema usata da `py3compile` (installazione pacchetti Python), **non servita da Apache**, nessun visitatore può raggiungerla.
- Contenuto: **stesso identico payload** IOC già noto — falsa pagina "Briefly unavailable for scheduled maintenance" + redirect mobile verso `ushort.company/pxCXpSDmu0r6` (stesso path osservato su valdicecinaoutdoor.it).
- `stat`: proprietario **root:root**, permessi `0644`. Per scrivere lì serve accesso root (non basta una falla a livello `www-data`/WordPress).
- **Birth: 2026-09-09 01:32** (coincide con la finestra dell'attacco originale) — **Modify: 2026-09-15 07:18** (6 giorni dopo, **dopo** che oc:8511/oc:8515 erano già stati dichiarati "Rilasciato").
- Effetto collaterale reale: la presenza di questo file ha rotto `py3compile` (legge tutti i file in quella cartella aspettandosi un formato specifico), causando errori `apt`/`dpkg` su qualunque pacchetto Python — scoperto perché bloccava l'installazione di `fail2ban`.
- **Non rimosso**: lasciato sul posto per non alterare le prove, in attesa di completare l'audit sotto.

### Audit accessi root eseguito (in risposta al ritrovamento)

- **`authorized_keys` di root**: 3 chiavi presenti, tutte riconducibili a membri noti del team (Alessio Piccioli, Giuseppe Bonfanti, Rubens Garofalo). mtime del file: **15/09 09:11** — stesso giorno della modifica dell'artefatto sopra, da verificare se è una modifica legittima (es. aggiunta/rotazione chiave durante l'hardening) o no.
- **Utenti di sistema**: nessun account con shell di login oltre `root`; nessun UID 0 extra.
- **Cron di root e di sistema**: solo le voci note/legittime (certbot, script di questo repo, cron standard Debian). Nessuna voce sospetta in `/etc/cron.*` o nello spool di altri utenti.
- **`/var/log/auth.log*` (1 settembre → oggi)**: **solo 2 fingerprint di chiave SSH usati in tutto il periodo**, nessun accesso via password. L'attività SSH del 15/09 intorno agli orari sopra è compatibile con sessioni rapide ripetute (lavoro manuale/scriptato legittimo), non con un pattern anomalo.
- **`block-abuse-ips.service`** (systemd, trovato durante l'audit): servizio che blocca un IP specifico (`195.178.110.106`) via iptables ad ogni boot. Creato l'11/09, verosimilmente una contromisura legittima presa durante la risposta all'incidente (coincide con la sottorete `195.178.110.x` vista anche nello scan "Gravity SMTP" del 30/09) — da confermare con chi l'ha creato.

**Interpretazione sull'accesso**: nessuna prova di accesso SSH non autorizzato nel periodo osservato (solo 2 fingerprint noti, mai password, nessuna attività anomala). Se c'è stato un accesso root, oggi non risulta più attivo via SSH — non esclude altri canali non ancora controllati.

### Ricerca sistema-wide completata (2026-10-01) — portata reale dell'infezione

Eseguita una ricerca sull'intero filesystem (`/`, esclusi solo `/proc` `/sys` `/dev`) per il marcatore univoco `ushort.company` (non il testo "Briefly unavailable..." da solo, che ha falsi positivi noti — vedi `wp-includes/load.php`, funzione core WordPress legittima).

**Risultato grezzo:** 2379 file. Dopo aver scartato i falsi positivi (dati, non payload):
- `/var/lib/mysql/*` (binlog, `wp_wfissues.ibd`) → è **Wordfence stesso** che registra nel DB di aver trovato quella stringa durante le sue scansioni — non nuova infezione.
- `/root/.cursor*/**/*.jsonl` → trascrizioni delle conversazioni AI usate per la bonifica di settembre, menzionano l'IOC perché se ne discuteva — non malware.

**Risultato reale, verificato** (solo file `.html`/`.php`, contenuto rivisto a campione): **2175 file statici** con lo stesso payload (falsa maintenance + redirect `ushort.company`), **tutti fuori da qualunque webroot**, nessuno raggiungibile da un visitatore:
- **~2145 dentro `/usr/share/*`** — in pratica l'`index.html` di documentazione di quasi ogni pacchetto Debian installato (vim, apache2, aspell, dbus, ca-certificates, …).
- **4 file "orfani"** senza nessuna relazione con un pacchetto: `/srv/index.html`, `/home/index.html`, `/mnt/index.html`, `/mnt/HC_Volume_102677298/index.html`.
- **Solo 2 `.php`** trovati fuori webroot — ed **erano già in quarantena** da settembre (`/root/backups/uploads-quarantine/.../smile_fonts_Defaults_index.php` e `cfdb7_uploads_index.php`), non nuovi.

**Lettura**: la scala (migliaia di file, ovunque sul filesystem, proprietario root) è coerente con uno script automatico **non mirato** — verosimilmente qualcosa tipo `find / -name index.html -o -name index.php | xargs <sovrascrivi>` lanciato **con privilegi root**, senza restrizione alla sola webroot. Non è "un plugin WordPress bucato": è prova di **scrittura root sull'intero filesystem** durante l'incidente di settembre. Il vettore d'ingresso iniziale (come l'attaccante abbia ottenuto root) resta non identificato — già segnalato come gap aperto in oc:8515.

**Rischio pratico oggi**: basso nell'immediato (nessuno di questi file è servito dal web server, sono tutti statici e inerti), ma è una prova forte a favore di riconsiderare la **ricostruzione del server** già discussa e posticipata in oc:8547 — dopo un accesso root confermato, non c'è garanzia che "ripulire quello che si trova" sia sufficiente.

**Non ancora fatto:** rimozione/quarantena dei 2175 file (bassa priorità, sono inerti); decisione su ricostruzione server; eventuale rotazione credenziali; capire il vettore d'ingresso iniziale.

### Nuovo ritrovamento (2026-10-01): attività malware datata 21/09, non 15/09 — timeline da rivedere

Durante un'operazione non collegata (disattivazione del `git pull` da `/root/docs`, vedi sotto), trovato un secondo repository git a livello di **`/root`** (non `/root/docs`), con **"No commits yet"** — scheletro di un `git init` mai arrivato a un commit.

**Dentro `/root/.git` erano presenti 4 file `index.html`** (`branches/`, `hooks/`, `info/`, e la radice del repo) con **lo stesso identico payload malware** già noto (falsa pagina "Briefly unavailable for scheduled maintenance" + redirect mobile a `ushort.company/pxCXpSDmu0r6` — stesso path esatto già visto su `/usr/share/python3/bcep/index.html`, vedi sopra).

**Timestamp: 2026-09-21 06:15:53 UTC**, identico al millisecondo su tutti i file del repo — compresi quelli standard generati automaticamente da `git init` (`hooks/*.sample`, `config`, `HEAD`, `description`). Questo indica che la creazione del repository e la scrittura del payload sono avvenute nella **stessa azione/esecuzione**, non in due momenti separati.

**Significato:** questa è una data **successiva** a tutte le evidenze precedenti (attacco originale 9/9, modifica del file in `/usr/share` il 15/9) — e **successiva** alla chiusura di oc:8511/oc:8515 come "Rilasciato". Sposta in avanti la finestra temporale nota dell'incidente.

**Indagine eseguita sul meccanismo (esito: non determinato):**
- `auth.log` 21/09 06:00–06:20 UTC: nessuna sessione SSH autenticata con successo, solo rumore di bot con tentativi falliti/non autenticati (`preauth`) — nessuna corrispondenza con l'orario esatto.
- Unica sessione cron di root nella stessa finestra (06:15:01) è il nostro `wp-security-drift-deadman.sh`, schedulato in buona fede — non scrive `index.html` né esegue `git init`, e lo scarto di 52 secondi non lo rende una spiegazione plausibile.
- `atq` e `/var/spool/cron/atjobs/` (meccanismo di persistenza spesso trascurato): vuoti, nessun job pendente o residuo.
- Nessun'altra voce in `/var/log/syslog` riconducibile a quell'istante.
- **Verifica che non sia un problema ancora attivo oggi**: ricerca di nuovi file `index.html` creati dopo il 21/09 su tutto il filesystem — **nessun nuovo file malevolo trovato** (solo asset legittimi di Cursor Server, `.cursor-server/.../media/index.html`, estranei al malware). Nessun segnale di un processo ancora in esecuzione in questo momento.

**Conclusione:** il meccanismo con cui questa scrittura root è avvenuta il 21/09 **resta non determinato** (stesso esito già avuto per il vettore d'ingresso del 9/9) — ma è confermato che non è un'attività in corso oggi. Trattato come evidenza, non cancellato: spostato in quarantena in `/root/backups/backdoor-quarantine/root-git-sep21/<timestamp>/`.

**Impatto sulla raccomandazione già fatta:** rafforza, non introduce, la raccomandazione di ricostruzione del server — un accesso root confermato una settimana dopo la "chiusura" dell'incidente è coerente con l'ipotesi che la causa radice non fosse stata rimossa, non con un evento isolato e concluso il 9/9.

### Fix collaterale: log Apache del volume montato mai ruotati

Durante l'indagine scoperto che i log dei 4 siti su `/mnt/HC_Volume_102677298/logs/` (european-mountaineers.eu, outcropedia.org, selfguided-toscana.it, sicai.webmapp.it — più i due inattivi euma.webmapp.it e outcropedia.tectask.org) **non erano mai stati ruotati**: fino a **1.4 GB** (selfguided-toscana.it), 534 MB, 268 MB, 145 MB. A differenza del gruppo `/var/www/html`, non avevano nessuna voce in `/etc/logrotate.d/`. Rischio concreto di saturazione disco nel tempo.

**Fix**: nuovo `/etc/logrotate.d/apache2-volume-sites`, stesso schema già in uso per l'altro gruppo (giornaliera, 14 rotazioni, compressione, `create 640 root adm`, reload Apache post-rotazione). Testato in dry-run, poi forzata la prima rotazione reale — verificato dopo: Apache attivo, tutti e 4 i siti rispondono 200, nessun down.

**Effetto collaterale utile per l'indagine**: questo spiega perché questi log risalivano ancora a mesi fa (coprivano l'intera vita del sito) — ed è anche il motivo per cui abbiamo potuto controllare l'8-9 settembre su questi siti, a differenza del gruppo `/var/www/html` dove la rotazione a 14 giorni aveva già cancellato tutto.

### Tentativo di ricostruire il vettore d'ingresso iniziale (2026-10-01)

Controlli eseguiti, tutti in sola lettura:

| Pista | Esito |
|---|---|
| Log Apache dei 4 siti realmente colpiti (`/var/www/html`), 8-9/9 | **Non disponibili** — già ruotati via (retention 14 giorni) prima dell'inizio di questa indagine |
| Log Apache dei siti sul volume montato, finestra 8-9/9 | Disponibili (mai ruotati prima d'ora), nessuna richiesta chiaramente malevola trovata — un solo tentativo di login fallito isolato su outcropedia.org, non conclusivo |
| Permessi `sudo` di `www-data` | Nessuno. L'unico uso di `sudo` il 9/9 è root che impersona `www-data` per un test di permessi (`touch .write-test`, 10:12) — lavoro legittimo del team durante la bonifica |
| Binari SUID/SGID su tutto il filesystem | Nessuno sospetto. L'unica modifica recente (`pkexec`, notoriamente legato a CVE storiche di privilege escalation) è un aggiornamento di sicurezza Ubuntu regolare del 17/9 (`polkitd` 0.105-33ubuntu0.1→.2), tracciato in `dpkg.log` |
| Tentativi SSH falliti, 8-9/9 | 2516 tentativi — rumore di bot costante da internet (username tipo "admin", "addyson"), nessuno riuscito. Una sottorete (`195.178.110.x`) coincide con quella bloccata da `block-abuse-ips.service`, confermando che quel servizio è quasi certamente una contromisura legittima già presa dal team, non un artefatto malevolo |

**Conclusione**: il vettore d'ingresso iniziale (come l'attaccante abbia ottenuto scrittura root) **resta non determinato**. Escluse con buona confidenza le piste più comuni (SSH, sudo, SUID). I log che servirebbero per la risposta (Apache sui 4 siti colpiti, quella notte) non esistono più. Non è una conferma che la causa sia stata rimossa — resta un'ignoto aperto, coerente con la raccomandazione sopra di considerare la ricostruzione del server.

---

## Follow-up 2026-10-01 — fail2ban contro il bot che scansiona "Gravity SMTP"

**Contesto:** email Wordfence "Increased Attack Rate" ricorrenti su più siti, legate a uno scan per una vulnerabilità del plugin **Gravity SMTP** — plugin **non installato** su nessuno dei siti del server. Il bot colpisce comunque tutti i vhost sulla stessa IP: probabile scoperta dei domini via **Certificate Transparency log** (crt.sh), non una falla reale sfruttata. Nessun legame con le backdoor/IOC `ushort.company` descritte sopra — è un filone di indagine separato, aperto durante lo stesso controllo di routine.

Senza Wordfence Premium (niente blocco IP centralizzato), la soluzione scelta è **fail2ban** a livello di server, con un vincolo esplicito e non negoziabile: **nessun down dei siti, nessun impatto su SSH** (né per Rubens né per i colleghi).

### Blocco incontrato in installazione

`apt-get install fail2ban` falliva con un errore Python (`py3compile`, `ValueError: not enough values to unpack`). Causa: il file malevolo `/usr/share/python3/bcep/index.html` (vedi sezione sopra) veniva letto da `py3compile` aspettandosi un formato diverso, bloccando **qualunque** installazione di pacchetti Python sul server. Risolto mettendo in quarantena il file (`/root/backups/backdoor-quarantine/system-usr-share/<timestamp>/`), poi `dpkg --configure -a` è tornato pulito e l'installazione è proseguita.

### Configurazione

| File | Contenuto |
|---|---|
| `/etc/fail2ban/filter.d/wp-gravitysmtp-scan.conf` | Filtro dedicato: match su richieste `GET`/`POST` contenenti `gravitysmtp` nel path, qualunque vhost |
| `/etc/fail2ban/jail.d/wp-gravitysmtp-scan.conf` | Jail attivo su tutti i log Apache dei 9 siti (sia `/var/log/apache2/` che `/mnt/HC_Volume_102677298/logs/`); `maxretry = 3`, `findtime = 300`, `bantime = 3600`; **`action = iptables-multiport[... port="http,https" ...]`** — scoping esplicito alle sole porte 80/443 |
| `/etc/fail2ban/jail.d/disable-default-jails.conf` | `[sshd]\nenabled = false` — necessario perché il `jail.conf` di default di Debian abilita `[sshd]` automaticamente; senza questo override SSH sarebbe stata soggetta a ban |

`ignoreip` del jail include l'IP del server stesso, per non autobannarsi durante i test.

### Verifica eseguita

- `fail2ban-regex` in dry-run sul filtro prima di attivarlo: match corretti sulle righe con `gravitysmtp`, nessun match su righe normali.
- Dopo l'avvio: `fail2ban-client status` confermava **solo** `wp-gravitysmtp-scan` attivo — `[sshd]` correttamente disabilitato (controllo esplicito, perché il comportamento di default lo avrebbe attivato).
- **Falso allarme investigato e chiuso:** il chain iptables `f2b-wp-gravitysmtp-scan` non compariva né in `iptables -S` né in `nft list ruleset` subito dopo l'avvio del jail, anche dopo un `systemctl restart fail2ban` pulito. Causa trovata in `/etc/fail2ban/action.d/iptables-multiport.conf`: l'`actionstart` (creazione del chain) è **lazy by design** — gira solo al **primo ban reale**, non all'avvio del jail (`actionstart_on_demand = true`, default di fail2ban 0.11.2). Non è un bug.
- Confermato il meccanismo end-to-end forzando un ban di test con un IP non instradabile (`203.0.113.1`, RFC 5737 — nessun impatto reale): il ban ha creato correttamente il chain e la regola `REJECT` sulla porta 80/443; l'unban ha ripulito tutto senza lasciare residui.
- Durante tutto l'intervento: siti (trekking, parco-maremma, european-mountaineers, …) sempre raggiungibili (200), sessione SSH sempre attiva, nessun down.
- `systemctl is-enabled fail2ban` → `enabled`, sopravvive a un riavvio del server.

**Stato attuale:** protezione attiva e verificata, limitata alle porte 80/443, zero impatto su SSH. Nessuna azione pendente su questo filone.

---

## Follow-up 2026-10-01 — audit log non ruotati (rischio saturazione disco)

**Contesto:** dopo il fix dei log Apache del volume montato mai ruotati (sezione sopra), controllo esteso a tutto il server — disco principale e volume montato — per capire se esistono altri log in crescita non gestita.

**Spazio disco al momento del controllo:** `/` 56% usato (64G liberi su 150G), `/mnt/HC_Volume_102677298` 24% usato (72G liberi su 99G). **Nessun rischio di saturazione imminente.**

### Log trovati senza rotazione

| Log | Dimensione | Dettaglio |
|---|---|---|
| `/var/log/curl-monitor.log` | 25 MB | Scritto da `/root/curl_check_restart_apache.sh` (cron ogni 20 min) da giugno 2025, ~950 righe/giorno, crescita costante. Nessuna entry in `/etc/logrotate.d/`. |
| `/var/log/le-renew.log` | 644 KB | Output `certbot renew` (cron settimanale) in append (`>>`), stessa situazione ma crescita molto più lenta. |

Nessuno dei due è toccato da `/root/cleanup_logs.sh` (cron notturno, root, soglia 5GB su `/var/log`): le sue regole specifiche (Apache, `mail.log`, `*.gz`, `*.log.*` più vecchi di 30gg) non includono questi due nomi file, quindi in teoria potrebbero crescere indefinitamente anche se quello script scattasse.

### Gap strutturale

`cleanup_logs.sh` monitora solo `/var/log` (`LOG_DIR` hardcoded). Il volume montato (`/mnt/HC_Volume_102677298`) non ha nessuna rete di sicurezza generica — oggi l'unica copertura lì sono i 4 log Apache messi sotto `logrotate.d/apache2-volume-sites` (sezione sopra).

### Trovato ma non a rischio

`/mnt/HC_Volume_102677298/html/selfguided-toscana.it/wp-content/debug.log` — 40 MB, ma **fermo dal 3 giugno 2025** (nessuna scrittura successiva): non è un log in crescita, solo spazio occupato da un file ormai inerte.

**Deciso il 2026-10-01: nessuna azione per ora.** Nessuna entry logrotate aggiunta per `curl-monitor.log` / `le-renew.log`, nessuna pulizia del `debug.log` dormiente. Punti aperti per un intervento futuro, se richiesto.

---

## Follow-up 2026-10-02 — rumore email Wordfence "User locked out" (credential-stuffing distribuito)

**Contesto:** segnalate email Wordfence "User locked out from signing in" ricevute **a raffica** (es. 26 email in 16 secondi). Analizzate 207 email su 30 thread (4/9 → 2/10) via Gmail: concentrate soprattutto su `parco-maremma.it` (20 thread su 30, burst anche da 22 e 41 email), sporadiche su trekking, acquasorgente, selfguided-toscana, european-mountaineers.

**Natura del fenomeno:** analizzato il dettaglio di un burst (26 tentativi): **26 IP sorgente quasi tutti diversi** (range tipici di VPS/hosting abusati: `45.3.x.x`, `65.111.x.x`, `104.207.x.x`, `209.50.x.x`, `216.26.x.x` — Ashburn VA, Toronto, Berlino, Parigi), username casuali/dizionario (`site_admin`, `wplogin`, `zetgifari`, …). È un **botnet di credential-stuffing distribuito** generico, non mirato a questi siti specifici — fenomeno comune su qualunque installazione WordPress esposta, **non collegato** alle backdoor/IOC `ushort.company` documentate sopra.

**Perché fail2ban non è la soluzione qui:** a differenza dello scan "Gravity SMTP" (sezione sopra, un bot persistente da pochi IP → fail2ban efficace), un ban per-IP non scatta mai contro questo pattern: ogni IP tenta una volta sola e sparisce, sotto qualunque soglia ragionevole di `maxretry`.

**Verifica:** su tutte le 207 email controllate, **nessun accesso riuscito** — Wordfence sta già bloccando correttamente ogni tentativo (lockout 5 minuti). Le email non segnalano un fallimento della protezione, solo il volume del rumore di fondo.

### Fix applicato: tetto email/ora su Wordfence (non un blocco di rete)

Opzioni Wordfence lette/modificate via `wp db query` sulla tabella `wp_wfconfig` (non `wp_options` — Wordfence 9.x usa una tabella dedicata) di ciascun sito:

| Opzione | Prima | Dopo |
|---|---|---|
| `alertOn_throttle` | `0` (nessun limite) | `1` |
| `alert_maxHourly` | `0` | `5` |

Applicato su tutti gli **8 siti con Wordfence attivo** (verificato `wp plugin is-active wordfence` prima di procedere): parco-maremma, parcopan, sentierodeiducati, trekking, acquasorgente, european-mountaineers, outcropedia, selfguided-toscana. (`sicai.webmapp.it` non ha Wordfence attivo.)

`alertOn_loginLockout` (il flag che genera l'alert per ogni lockout) **lasciato invariato** — su parcopan e sentierodeiducati era già `0` da prima (nessuna email di questo tipo mai arrivata da questi due, coerente con l'assenza nei 30 thread controllati); sugli altri 6 resta `1`. La protezione reale (Wordfence che blocca il tentativo) non è stata toccata in nessun sito — solo il volume delle notifiche.

**Verifica post-modifica:** tutti e 8 i siti rispondono HTTP 200 dopo l'intervento, nessun down.

**Non ancora fatto:** nessuna azione sui range IP sorgente (valutata e scartata per ora, rischio falsi positivi su traffico legittimo); nessuna modifica a `alertOn_loginLockout`.
