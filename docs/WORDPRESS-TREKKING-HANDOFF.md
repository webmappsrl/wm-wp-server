# WordPress Trekking Parco Foreste Casentinesi — handoff operativo

> Sito: **trekking.parcoforestecasentinesi.it**  
> Path: `/var/www/html/trekking.parcoforestecasentinesi.it` (equiv. `/root/html/trekking.parcoforestecasentinesi.it`)  
> Sessione Fase 1 + WPML: **2026-09-10**.

Contesto generale:  
[`/root/docs/WORDPRESS-UPLOADS-SECURITY.md`](/root/docs/WORDPRESS-UPLOADS-SECURITY.md),  
[`/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md`](/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md).

---

## Stato post-intervento (2026-09-10)

| Voce | Valore |
|------|--------|
| Core | **6.8.8** |
| Tema | `wm-pnfc-child` (parent Impreza **8.22**) |
| `us-core` | **8.22.2** (congelato) |
| WPBakery `js_composer` | **7.4** (congelato) |
| UAVC `Ultimate_VC_Addons` | **3.19.9** (congelato + patch `bsf_registration_page_url`) |
| Wordfence | **9.0.1** + WAF `auto_prepend` ok |
| WPML CMS / String / SEO-ML | **4.9.7** / **3.5.4** / **2.2.5** |
| OTGS Installer | **3.1.20** — chiave sito **registrata** |
| `.htaccess` | `root:www-data` **644** (su questo vhost `640` → 403) |
| `DISALLOW_FILE_EDIT` / `DISALLOW_FILE_MODS` | `true` / `true` |

### Plugin aggiornati (Fase 1 + WPML)

| Plugin | Prima → Dopo |
|--------|----------------|
| disable-comments | 2.5.2 → **2.9.0** |
| carousel-block | 2.0.1 → **2.1.5** |
| iubenda-cookie-law-solution | 3.12.3 → **3.13.5** |
| really-simple-ssl | 9.4.0 → **9.8.1** |
| wp-mail-smtp | 4.5.0 → **4.9.0** |
| redirection | 5.5.2 → **5.10.0** (export 20 regole prima) |
| stops-core-theme-and-plugin-updates | 9.0.19 → **9.0.22** |
| advanced-custom-fields | 6.4.2 → **6.8.9** |
| wordfence | 8.0.5 → **9.0.1** |
| sitepress-multilingual-cms | 4.7.6 → **4.9.7** |
| wpml-string-translation | 3.3.3 → **3.5.4** |
| wp-seo-multilingual | 2.1.1 → **2.2.5** |

### Non toccati (congelati / fermi)

- Impreza / `us-core` / `js_composer` / UAVC (con patch)
- `wm-package` **2.0** — **non `git pull`** (modifiche locali non committate in `admin_page.php`, `shortcodes/grid_*.php`, `single_poi.php`)
- `wm-pnfc-child`, `wordpress-seo` **25.3** FERMI

### Note tipiche del sito

- **RSS:** update ha rimosso blocco `#Begin Really Simple Security` HTTPS rewrite; resta `$_SERVER["HTTPS"]="on"` in `wp-config.php`. Dopo RSS: verificare `ls -la .htaccess` — tenere **644**.
- **UAVC / admin bianco:** guard `function_exists('bsf_registration_page_url')` in `admin/admin.php` + bootstrap `bsf-core/index.php`. Non aggiornare UAVC senza re-patch.
- **wm-package:** origin `webmappsrl/wp-geohub`; un pull sovrascrive custom e può disattivare il plugin.

---

## Backup

| Artefatto | Path |
|-----------|------|
| Dump DB | `/root/backups/trekking-db-backup-20260910-143519.sql` |
| Tar codice | `/root/backups/trekking-files-backup-20260910-143519.tar.gz` |
| `.htaccess` / WAF pre-WF9 | `/root/backups/trekking-htaccess-pre-wf9-20260910-143519.bak`, `trekking-wordfence-waf-pre-wf9-20260910-143519.bak` |
| Redirection export | `/root/backups/trekking-redirection-export-20260910-143519.json` + `trekking-redirection-tables-20260910-143519.sql` |
| Dump DB WPML | `/root/backups/trekking-db-backup-wpml-20260910-145438.sql` |
| Tar WPML | `/root/backups/trekking-wpml-plugins-20260910-145438.tar.gz` |

Rollback: ripristino tar + import SQL **solo trekking**.

---

## WP-CLI

```bash
wp --allow-root --path="/var/www/html/trekking.parcoforestecasentinesi.it" …
```

---

## Smoke 2026-09-10

Home, `/en/`, login, admin (niente bianco), track, poi; redirect mtb-1 **301**. HTTP **200** sulle pagine chiave.

---

## Registro interventi

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-10 | trekking… | agent | WPML String→CMS→SEO-ML; OTGS 3.1.20 + chiave; ri-lock | **OK** | Dump/tar WPML; UAVC/wm-package ok |
| 2026-09-10 | trekking… | agent | core **6.8.8**; lotto A; Redirection **5.10.0**; ACF **6.8.9**; Wordfence **9.0.1**; ri-lock | **OK** | `.htaccess` 644; RSS rewrite rimosso; UAVC/wm-package non toccati |

Template:

```
| AAAA-MM-GG | trekking.parcoforestecasentinesi.it | nome | azioni | OK / KO | dump in /root/backups/… |
```
