# WordPress Sentieri dei Ducati — handoff operativo

> Sito: **sentierodeiducati.it**  
> Path: `/var/www/html/sentierodeiducati.it` (equiv. `/root/html/sentierodeiducati.it`)  
> Sessione Fase 1 (pilota) + WPML: **2026-09-10**.

Contesto generale:  
[`/root/docs/WORDPRESS-UPLOADS-SECURITY.md`](/root/docs/WORDPRESS-UPLOADS-SECURITY.md),  
[`/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md`](/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md).

---

## Stato post-intervento (2026-09-10)

| Voce | Valore |
|------|--------|
| Core | **6.8.8** |
| Tema | `wm-caire-child` (parent Impreza **8.23.2**) |
| `us-core` | **8.23.2** (congelato) |
| WPBakery `js_composer` | **7.6** (congelato) |
| Wordfence | **9.0.1** + WAF `auto_prepend` intatto |
| WPML CMS / String / ACFML / SEO-ML | **4.9.7** / **3.5.4** / **2.2.4** / **2.2.5** |
| OTGS Installer | **3.1.20** — chiave sito **registrata** |
| `DISALLOW_FILE_EDIT` / `DISALLOW_FILE_MODS` | `true` / `true` |
| Owner codice | `root:www-data` |
| `wp-content/upgrade/` | non scrivibile da `www-data` |

### Plugin aggiornati (Fase 1 + WPML)

| Plugin | Prima → Dopo |
|--------|----------------|
| contact-form-7 | 6.0.6 → **6.1.7** |
| add-to-any | 1.8.13 → **1.8.18** |
| disable-comments | 2.5.2 → **2.9.0** |
| contact-form-cfdb7 | 1.3.0 → **1.4.0** |
| wp-mail-smtp | 4.5.0 → **4.9.0** |
| ultimate-addons-for-gutenberg | 2.19.9 → **2.20.3** |
| advanced-custom-fields | 6.4.2 → **6.8.9** |
| wordfence | 8.2.1 → **9.0.1** |
| sitepress-multilingual-cms | 4.7.6 → **4.9.7** |
| wpml-string-translation | 3.3.3 → **3.5.4** |
| acfml | 2.1.5 → **2.2.4** |
| wp-seo-multilingual | 2.1.1 → **2.2.5** |

### Non toccati (congelati / fermi)

- Impreza / `us-core` / `js_composer`
- `wp-geohub` **1.0**, `wm-caire-child`
- `wordpress-seo` **25.3** (FERMI)

**Nota:** svuotato `wp-content/cache/index.html` con IOC `ushort`. Residui ushort possibili sotto `.git/`.

---

## Backup

| Artefatto | Path |
|-----------|------|
| Dump DB | `/root/backups/sentierodeiducati-db-backup-20260910-124148.sql` |
| Tar codice | `/root/backups/sentierodeiducati-files-backup-20260910-124148.tar.gz` |
| `.htaccess` pre-WF9 | `/root/backups/sentierodeiducati-htaccess-pre-wf9-20260910.bak` |
| `wordfence-waf.php` pre-WF9 | `/root/backups/sentierodeiducati-wordfence-waf-pre-wf9-20260910.bak` |
| Dump DB WPML | `/root/backups/sentierodeiducati-db-backup-wpml-20260910-132947.sql` |
| Tar WPML | `/root/backups/sentierodeiducati-wpml-plugins-20260910-132947.tar.gz` |

Rollback: ripristino tar + import SQL **solo sentieri**.

---

## WP-CLI

```bash
wp --allow-root --path="/var/www/html/sentierodeiducati.it" …
```

Update solo da root + WP-CLI. Non da dashboard (`DISALLOW_FILE_MODS`). Dashboard che fallisce su `upgrade/` locked = atteso.

---

## Smoke 2026-09-10

Homepage, `/en/`, contatti, login, poi: HTTP **200**, zero `ushort.company` / Fatal nel body pubblico.

---

## Registro interventi

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-10 | sentierodeiducati.it | agent | WPML: String→CMS→ACFML→SEO-ML; OTGS 3.1.20 + chiave; ri-lock | **OK** | Dump/tar WPML; smoke home/en/contatti/login 200 |
| 2026-09-10 | sentierodeiducati.it | agent | core **6.8.8**; lotto A; ACF **6.8.9**; Wordfence **9.0.1**; ri-lock; cache IOC | **OK** | Dump/tar `*-20260910-124148.*`; WAF ok; Impreza non toccato |

Template:

```
| AAAA-MM-GG | sentierodeiducati.it | nome | azioni | OK / KO | dump in /root/backups/… |
```
