# WordPress Acquasorgente CAI — handoff operativo (volume)

> Sito: **acquasorgente.cai.it**  
> Path: `/mnt/HC_Volume_102677298/html/acquasorgente.cai.it`  
> DocumentRoot Apache: stesso path (non `/var/www/html`).  
> Sessione hardening + Fase 1 + WPML + OTGS: **2026-09-14**.

Contesto generale:  
[`/root/docs/WORDPRESS-UPLOADS-SECURITY.md`](/root/docs/WORDPRESS-UPLOADS-SECURITY.md),  
[`/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md`](/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md).

---

## Stato post-intervento (2026-09-14)

| Voce | Valore |
|------|--------|
| Core | **6.8.8** (en_US) |
| Tema | **`acquasorgente`** (custom Webmapp; nessun Impreza/WPBakery) |
| Wordfence | **9.0.1** + WAF `auto_prepend` intatto |
| Sucuri Scanner | **2.2** (congelato — non aggiornato) |
| `DISALLOW_FILE_EDIT` / `DISALLOW_FILE_MODS` | `true` / **`true`** (ri-lock dopo WPML 2026-09-14) |
| `AUTOMATIC_UPDATER_DISABLED` / `WP_AUTO_UPDATE_CORE` | `true` / `false` |
| Owner codice | `root:www-data` |
| `wp-config.php` | `640 root:www-data` |
| `wp-content/upgrade/` | `750 root:www-data` (PHP non scrive) |
| WRITE lasciato | `uploads/` (incluso `uploads/sucuri/`), `languages/`, `wflogs/` (`770`) |
| AI1WM | **disattivato** (+ unlimited extension inactive) |
| Lingua secondaria | `/en/` (WPML) |
| Yoast SEO | **25.4** (FERMI — non aggiornare a 28.x su core 6.8) |

### Plugin aggiornati (Fase 1 + WPML)

| Plugin | Prima → Dopo |
|--------|----------------|
| advanced-custom-fields | → **6.8.10** |
| wp-mail-smtp | → **4.9.0** |
| wp-crontrol | → **1.21.2** |
| wpml-string-translation | 3.3.3 → **3.5.4** |
| sitepress-multilingual-cms | 4.7.6 → **4.9.7** |
| acfml | 2.1.5 → **2.2.4** |
| otgs-installer-plugin | 3.1.3 → **3.1.20** (rsync da sentieri; chiave sito **registrata**) |

### Non toccati (congelati / inactive)

- Tema **`acquasorgente`** (custom)
- **Yoast** `wordpress-seo` **25.4** (FERMI)
- **Sucuri** `sucuri-scanner` **2.2** (FERMI)
- **WPForms** `wpforms-lite` **1.9.6.2** (FERMO)
- **Wordfence** **9.0.1** (già a target; non reinstallato)
- inactive: AI1WM **7.96** + unlimited **2.73** (non aggiornati)

**Nota OTGS:** installer **3.1.20** attivo; chiave sito **registrata** (update WPML via WP-CLI OK). `DISALLOW_FILE_MODS` riportato a **`true`** dopo update.

**Nota Sucuri:** dati scanner in `uploads/sucuri/` — allowlist nel cron IOC (`sucuri/*`); **non** quarantenare.

---

## Backup

| Artefatto | Path |
|-----------|------|
| Dump DB (pre-intervento) | `/root/backups/acquasorgente-db-backup-20260914-113900.sql` |
| Tar codice (no uploads) | `/root/backups/acquasorgente-files-backup-20260914-113900.tar.gz` |
| `.htaccess` pre-intervento | `/root/backups/acquasorgente-htaccess-pre-20260914-113900.bak` |
| `wordfence-waf.php` pre-intervento | `/root/backups/acquasorgente-wordfence-waf-pre-20260914-113900.bak` |
| Tar plugin WPML (pre-update) | `/root/backups/acquasorgente-wpml-plugins-20260914-114430.tar.gz` |

Rollback: ripristino tar + import SQL **solo acquasorgente.cai.it**.

---

## Cron IOC

Script: `/root/wp_uploads_ioc_clean.sh` (cron `*/30` già presente).

- Siti `/var/www/html`: parco-maremma, trekking, parcopan, sentieri (invariati).
- Volume: EUMA + outcropedia + selfguided + **acquasorgente.cai.it** → root `/mnt/HC_Volume_102677298/html`.
- Allowlist già presente: `cache/wpml/twig/*` (Twig cache WPML), **`sucuri/*`** (Sucuri scanner data).

Log: `/var/log/wp-uploads-ioc-clean.log` — verificare riga `START site=acquasorgente.cai.it root=/mnt/HC_Volume_102677298/html`.

---

## WP-CLI

```bash
wp --allow-root --path="/mnt/HC_Volume_102677298/html/acquasorgente.cai.it" …
```

Update da root + WP-CLI. Non da dashboard (`DISALLOW_FILE_MODS=true`). Non dare WRITE a `www-data` su codice/`upgrade/`.

---

## Smoke 2026-09-14 (verifica finale)

| URL | HTTP |
|-----|------|
| `/` | **200** |
| `/en/` | **200** |
| `/faq/` | **200** |
| `/eventi/` | **200** |
| `/il-progetto/` | **200** |
| `/wp-login.php` | **200** |

Core **6.8.8** invariato. Zero Fatal / `ushort.company`. WAF `auto_prepend_file` punta a `wordfence-waf.php` nel document root volume.

---

## Cosa non fare

- Aggiornare o downgrade core (resta **6.8.8**).
- Aggiornare da dashboard WordPress.
- Toccare Yoast / Sucuri / WPForms / Wordfence senza piano dedicato.
- Aggiornare tema custom **`acquasorgente`** senza staging.
- Quarantenare `uploads/sucuri/*` nel cron IOC.
- `chmod` ricorsivo su tutto `wp-content`.
- Dare WRITE a `www-data` su `plugins/`, `themes/`, `upgrade/` o codice core.

---

## Registro interventi

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-14 | acquasorgente.cai.it | agent | WPML: String **3.3.3→3.5.4**, CMS **4.7.6→4.9.7**, ACFML **2.1.5→2.2.4**; OTGS **3.1.3→3.1.20** (rsync sentieri); ri-lock `DISALLOW_FILE_MODS=true`; cron IOC; smoke | **OK** | Tar WPML `/root/backups/acquasorgente-wpml-plugins-20260914-114430.tar.gz`; chiave OTGS registrata; sucuri allowlist OK |
| 2026-09-14 | acquasorgente.cai.it | agent | Hardening FS; core **6.8.8**; ACF **6.8.10**, smtp **4.9.0**, crontrol **1.21.2**; AI1WM off; `MODS=false` per update | **OK** | Dump/tar `/root/backups/acquasorgente-*-20260914-113900.*` |

Template:

```
| AAAA-MM-GG | acquasorgente.cai.it | nome | azioni | OK / KO | dump in /root/backups/… |
```
