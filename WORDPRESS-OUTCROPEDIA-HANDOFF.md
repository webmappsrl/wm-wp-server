# WordPress Outcropedia — handoff operativo (volume)

> Sito: **outcropedia.org**  
> Path: `/mnt/HC_Volume_102677298/html/outcropedia.org`  
> DocumentRoot Apache: stesso path (non `/var/www/html`).  
> Sessione hardening + Fase 1 + WPML: **2026-09-14**.

Contesto generale:  
[`/root/docs/WORDPRESS-UPLOADS-SECURITY.md`](/root/docs/WORDPRESS-UPLOADS-SECURITY.md),  
[`/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md`](/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md).

---

## Stato post-intervento (2026-09-14)

| Voce | Valore |
|------|--------|
| Core | **6.8.8** (en_US) |
| Tema | Impreza **8.36.1** + `wm-outcropedia-child` |
| `us-core` | **8.36.3** (congelato) |
| WPBakery `js_composer` | **8.5** (congelato) |
| `wp-geohub` | **1.2** (congelato) |
| Wordfence | **9.0.1** + WAF `auto_prepend` intatto |
| `DISALLOW_FILE_EDIT` / `DISALLOW_FILE_MODS` | `true` / `true` |
| Owner codice | `root:www-data` |
| `wp-config.php` | `640 root:www-data` |
| `wp-content/upgrade/` | `750 root:www-data` (PHP non scrive) |
| WRITE lasciato | `uploads/`, `languages/`, `wflogs/` (`770`) |
| AI1WM | **disattivato**; zip `.wpress` / estensioni in quarantena |
| Lingua secondaria | `/it/` (WPML) |
| Yoast SEO | **25.5** (FERMI — non aggiornare a 28.x su core 6.8) |

### Plugin aggiornati (Fase 1 + WPML)

| Plugin | Prima → Dopo |
|--------|----------------|
| add-to-any | → **1.8.18** |
| advanced-custom-fields | → **6.8.10** |
| custom-post-type-ui | → **1.19.3** |
| duplicate-post | → **4.7** |
| wp-mail-smtp | → **4.9.0** |
| wordfence | → **9.0.1** |
| wpml-string-translation | → **3.5.4** |
| sitepress-multilingual-cms | → **4.9.7** |
| acfml | → **2.2.4** |
| wp-seo-multilingual | → **2.2.5** |
| otgs-installer-plugin | **3.1.3** → **3.1.20** (rsync da sentieri; chiave sito **registrata**) |
| wordpress-seo | **25.5** (già presente; FERMI) |

### Non toccati (congelati / inactive)

- Impreza / `us-core` / `js_composer` / `wp-geohub`
- inactive: AI1WM + unlimited extension (non aggiornati)

**Nota OTGS:** installer **3.1.20**; chiave sito **registrata** in admin (valore mascherato). La scheda Commercial resta bloccata da `DISALLOW_FILE_MODS` (atteso). Gli update WPML restano via WP-CLI da root.

**Nota Yoast:** **25.5** compatibile WP 6.8.8. La 28.x richiede WP 6.9 — non aggiornare finché il core resta sulla linea 6.8.

---

## Backup / quarantena

| Artefatto | Path |
|-----------|------|
| Dump DB (pre-intervento) | `/root/backups/outcropedia-db-backup-20260914-095002.sql` |
| Tar codice | `/root/backups/outcropedia-files-backup-20260914-095002.tar.gz` |
| Dump DB WPML | `/root/backups/outcropedia-db-backup-wpml-20260914-101623.sql` |
| Tar plugin WPML | `/root/backups/outcropedia-wpml-plugins-20260914-101623.tar.gz` |
| Dump DB OTGS/WPML (completamento) | `/root/backups/outcropedia-db-backup-wpml2-20260914-103857.sql` |
| Tar plugin OTGS/WPML (completamento) | `/root/backups/outcropedia-wpml2-plugins-20260914-103857.tar.gz` |
| `.htaccess` pre-WF9 | `/root/backups/outcropedia-htaccess-pre-wf9-20260914-095002.bak` |
| `wordfence-waf.php` pre-WF9 | `/root/backups/outcropedia-wordfence-waf-pre-wf9-20260914-095002.bak` |
| Quarantena igiene | `/root/backups/outcropedia-quarantine-20260914-095002/` (zip WPML legacy, AI1WM) |

Rollback: ripristino tar + import SQL **solo outcropedia**.

---

## Cron IOC

Script: `/root/wp_uploads_ioc_clean.sh` (cron `*/30` già presente).

- Siti `/var/www/html`: parco-maremma, trekking, parcopan, sentieri (invariati).
- Volume: EUMA + **outcropedia.org** → root `/mnt/HC_Volume_102677298/html`.
- Allowlist già presente: `cache/wpml/twig/*` (Twig cache WPML).

Log: `/var/log/wp-uploads-ioc-clean.log`.

---

## WP-CLI

```bash
wp --allow-root --path="/mnt/HC_Volume_102677298/html/outcropedia.org" …
```

Update solo da root + WP-CLI. Non da dashboard (`DISALLOW_FILE_MODS`). Non dare WRITE a `www-data` su codice/`upgrade/`.

---

## Smoke 2026-09-14

| URL | HTTP |
|-----|------|
| `/` | **200** |
| `/wp-login.php` | **200** |
| `/wp-admin/` | **302** (redirect login) |
| `/the-outcropedia-map/` | **200** |
| `/about-us/` | **200** |
| `/it/` | **200** |

Zero `ushort.company` / Fatal. Zero `.php` inattesi in `uploads/`. WAF `auto_prepend_file` presente in `.htaccess`.

---

## Cosa non fare

- Aggiornare da dashboard WordPress.
- Aggiornare Impreza / `us-core` / `js_composer` / `wp-geohub` senza piano Fase 2.
- Aggiornare Yoast oltre **25.5** finché core resta 6.8.x.
- Aggiornare WPML a pezzi (String senza CMS / viceversa).
- Dare WRITE a `www-data` su `plugins/`, `themes/`, `upgrade/` o codice core.
- Riattivare AI1WM in produzione senza spostare `.wpress` fuori webroot.
- Forzare update OTGS Installer senza chiave sito registrata.

---

## Registro interventi

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-14 | outcropedia.org | agent | OTGS **3.1.3→3.1.20** (rsync sentieri; WP-CLI no update); WPML stack già a target; chiave sito registrata; ri-lock `DISALLOW_*`; chown plugin WPML | **OK** | Dump/tar `/root/backups/outcropedia-*-wpml2-20260914-103857.*`; smoke home/it/map/about/login 200 |
| 2026-09-14 | outcropedia.org | agent | core **6.8.8**; lotto A; Wordfence **9.0.1**; WPML String→CMS→ACFML→SEO-ML; otgs 3.1.3 (no key); AI1WM off; lock FS `root:www-data`; cron volume; ri-lock `DISALLOW_*` | **OK** | Dump/tar `/root/backups/outcropedia-*-20260914-095002.*` + WPML `*-101623.*`; smoke home/login/map/about/it 200 |

Template:

```
| AAAA-MM-GG | outcropedia.org | nome | azioni | OK / KO | dump in /root/backups/… |
```
