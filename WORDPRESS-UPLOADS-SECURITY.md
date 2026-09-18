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
