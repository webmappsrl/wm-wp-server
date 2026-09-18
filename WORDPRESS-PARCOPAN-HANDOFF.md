# WordPress Parco Nazionale Appennino Tosco-Emiliano — handoff operativo

> Sito: **parcopan.org**  
> Path: `/var/www/html/parcopan.org` (equiv. `/root/html/parcopan.org`)  
> Sessione Fase 1 + LiteSpeed fix + WPML: **2026-09-10**.

Contesto generale:  
[`/root/docs/WORDPRESS-UPLOADS-SECURITY.md`](/root/docs/WORDPRESS-UPLOADS-SECURITY.md),  
[`/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md`](/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md).

---

## Stato post-intervento (2026-09-10)

| Voce | Valore |
|------|--------|
| Core | **6.8.8** |
| Tema | `wm-parcopan-child` (parent Impreza **8.23.4**) |
| `us-core` | **8.23.4** (congelato) |
| WPBakery `js_composer` | **7.6** (congelato) |
| Wordfence | **9.0.1** + WAF ok |
| LiteSpeed Cache | **7.9.1** (post-fix LSCACHE + `wp-content/litespeed/` 770) |
| WPML CMS / String / CF7-ML | **4.9.7** / **3.5.4** / **1.3.3** |
| OTGS Installer | **3.1.20** — chiave sito **registrata** |
| WooCommerce | **10.0.2** (FERMO) |
| `DISALLOW_FILE_EDIT` / `DISALLOW_FILE_MODS` | `true` / `true` |
| `WP_AUTO_UPDATE_CORE` | `false` |

### Plugin aggiornati (Fase 1 + WPML)

| Plugin | Prima → Dopo |
|--------|----------------|
| contact-form-7 | 6.1 → **6.1.7** |
| add-to-any | 1.8.13 → **1.8.18** |
| disable-comments | 2.5.2 → **2.9.0** |
| iubenda-cookie-law-solution | 3.12.4 → **3.13.5** |
| wp-mail-smtp | 4.5.0 → **4.9.0** |
| wp-accessibility | 2.1.18 → **2.3.5** |
| wp-sitemap-page | 1.9.5 → **1.9.6** |
| really-simple-ssl | 9.4.2 → **9.8.1** |
| litespeed-cache | 7.2 → **7.9.1** |
| wordfence | 8.0.5 → **9.0.1** |
| contact-form-7-multilingual | 1.3.2 → **1.3.3** |
| sitepress-multilingual-cms | 4.7.6 → **4.9.7** |
| wpml-string-translation | 3.3.3 → **3.5.4** |

### Non toccati (congelati / fermi / inactive)

- Impreza / `us-core` / `js_composer` / `wp-geohub` / child
- WooCommerce **10.0.2** FERMO; checkout-manager e Woo-ML inactive
- `wordpress-seo` **25.5** FERMI; ACF Pro vendor

### Note tipiche del sito

- **RSS → 403:** dopo update Really Simple SSL, `.htaccess` era `root:root` → Apache *unable to read htaccess*. Fix: `chown root:www-data`.
- **LiteSpeed 7.9+:** con lock write, aggiornare blocco LSCACHE root + `wp-content/litespeed/` 770 + `.htaccess` STATIC_PROTECT_V2 660. Backup: `parcopan-htaccess-pre-lscache-fix-20260910.bak`.
- Shop `/acquisti-online/` e `/negozio-online/` → **410** intenzionale (`Redirect gone`). Smoke su **carrello** e **checkout**.
- Stub IOC: `.tmb/index.html`, `images/**/index.php`.

---

## Backup

| Artefatto | Path |
|-----------|------|
| Dump DB | `/root/backups/parcopan-db-backup-20260910-134820.sql` |
| Tar codice | `/root/backups/parcopan-files-backup-20260910-134820.tar.gz` |
| `.htaccess` / WAF pre-WF9 | `/root/backups/parcopan-htaccess-pre-wf9-20260910.bak`, `parcopan-wordfence-waf-pre-wf9-20260910.bak` |
| `.htaccess` pre-LSCACHE | `/root/backups/parcopan-htaccess-pre-lscache-fix-20260910.bak` |
| Dump DB WPML | `/root/backups/parcopan-db-backup-wpml-20260910-142422.sql` |
| Tar WPML | `/root/backups/parcopan-wpml-plugins-20260910-142422.tar.gz` |

Rollback: ripristino tar + import SQL **solo parcopan**.

---

## WP-CLI

```bash
wp --allow-root --path="/var/www/html/parcopan.org" …
```

Commercial OTGS bloccata da `DISALLOW_FILE_MODS` (atteso: no `install_plugins`).

---

## Smoke 2026-09-10

Home, `/en/`, contatti, login, **carrello**, **checkout**: HTTP **200**. Shop legacy 410 intenzionale.

---

## Registro interventi

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-10 | parcopan.org | agent | WPML String→CMS→CF7-ML; OTGS 3.1.20 + chiave; ri-lock | **OK** | Dump/tar WPML; smoke home/en/contatti/login/carrello/checkout 200 |
| 2026-09-10 | parcopan.org | agent | Fix avvisi LiteSpeed 7.9.1 (LSCACHE + litespeed/ 770) | **OK** | Backup htaccess pre-lscache-fix |
| 2026-09-10 | parcopan.org | agent | core **6.8.8**; lotto A; LiteSpeed **7.9.1**; Wordfence **9.0.1**; stub IOC; ri-lock | **OK** | RSS→403 fix chown; WPML fuori scope in quel passo |

Template:

```
| AAAA-MM-GG | parcopan.org | nome | azioni | OK / KO | dump in /root/backups/… |
```
