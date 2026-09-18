# WordPress Selfguided Toscana — handoff operativo (volume)

> Sito: **selfguided-toscana.it**  
> Path: `/mnt/HC_Volume_102677298/html/selfguided-toscana.it`  
> DocumentRoot Apache: stesso path (non `/var/www/html`).  
> Sessione hardening + lotto A + OTGS: **2026-09-14**.  
> Sessione WPML: **2026-09-14** (String + CMS).

Contesto generale:  
[`/root/docs/WORDPRESS-UPLOADS-SECURITY.md`](/root/docs/WORDPRESS-UPLOADS-SECURITY.md),  
[`/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md`](/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md).

---

## Stato post-intervento (2026-09-14)

| Voce | Valore |
|------|--------|
| Core | **7.1** (en_US) — **LASCIATO INVARIATO** |
| Tema | Impreza **8.35.2** + `wm-child-sgt` **2.0** |
| `us-core` | **8.35.3** (congelato) |
| WPBakery `js_composer` | **8.4.1** (congelato) |
| `wp-geohub` | **1.2** (congelato) |
| WooCommerce | **11.1.0** (FERMO) |
| Wordfence | **9.0.1** + WAF `auto_prepend` intatto |
| `DISALLOW_FILE_EDIT` / `DISALLOW_FILE_MODS` | `true` / **`true`** (ri-lock dopo WPML 2026-09-14) |
| `AUTOMATIC_UPDATER_DISABLED` / `WP_AUTO_UPDATE_CORE` | `true` / `false` |
| Owner codice | `root:www-data` |
| `wp-config.php` | `640 root:www-data` |
| `.htaccess` | `644 root:www-data` |
| `wp-content/upgrade/` | `750 root:www-data` (PHP non scrive) |
| WRITE lasciato | `uploads/`, `languages/`, `wflogs/` (`770 www-data:www-data`) |

### WPML stack (aggiornato 2026-09-14)

| Plugin | Prima → Dopo |
|--------|----------------|
| wpml-string-translation | 3.5.3 → **3.5.4** |
| sitepress-multilingual-cms | 4.9.5 → **4.9.7** |
| acfml | **2.2.4** (già aggiornato) |
| wp-seo-multilingual | **2.2.5** (già aggiornato) |
| woocommerce-multilingual | **5.5.7** (già aggiornato) |
| otgs-installer-plugin | **3.1.20** (ACTIVE — chiave sito **registrata**) |

### Plugin aggiornati (lotto A, sessione mattina)

| Plugin | Prima → Dopo |
|--------|----------------|
| accessibility-widget | 3.2.5 → **3.2.6** |
| head-footer-code | 1.5.8 → **1.5.9** |
| wordfence | 9.0.0 → **9.0.1** |
| otgs-installer-plugin | 3.1.10 → **3.1.20** (rsync da sentieri; attivato) |

### Non toccati (congelati / Woo / vendor)

- Impreza / `us-core` / `js_composer` / `wp-geohub` / `wm-child-sgt`
- **Tutto lo stack WooCommerce core + payments** (woocommerce **11.1.0**, payments, stripe, checkout*, satispay, facebook, GLA, print invoices, brands, GTM, GA, woo-update-manager, woocarousel) — **woocommerce-multilingual** aggiornato solo se disponibile (nessun update)
- ACF free/Pro, FacetWP, Yoast **28.4**, Burst, Complianz, Media Cleaner, Jetpack, Really Simple SSL, RSS mu-plugins

**Nota OTGS:** installer **3.1.20** attivo; chiave sito **registrata** (update WPML via WP-CLI OK). `DISALLOW_FILE_MODS` riportato a **`true`** dopo update.

**Nota checkout:** `/pagamento/` risponde **302 → `/carrello/`** con carrello vuoto (comportamento WooCommerce atteso).

---

## Backup

| Artefatto | Path |
|-----------|------|
| Dump DB (hardening) | `/root/backups/selfguided-db-backup-20260914-105708.sql` |
| Tar codice (hardening) | `/root/backups/selfguided-files-backup-20260914-105708.tar.gz` |
| `.htaccess` pre-WF9 | `/root/backups/selfguided-htaccess-pre-wf-update-20260914-105708.bak` |
| `wordfence-waf.php` pre-WF9 | `/root/backups/selfguided-wordfence-waf-pre-wf-update-20260914-105708.bak` |
| OTGS pre-rsync | `/root/backups/selfguided-otgs-pre-rsync-20260914-105708.bak` |
| Dump DB (WPML) | `/root/backups/selfguided-db-backup-wpml-20260914-111350.sql` |
| Tar plugin WPML | `/root/backups/selfguided-wpml-plugins-20260914-111350.tar.gz` |

Rollback: ripristino tar + import SQL **solo selfguided-toscana**.

---

## Cron IOC

Script: `/root/wp_uploads_ioc_clean.sh` (cron `*/30` già presente).

- Siti `/var/www/html`: parco-maremma, trekking, parcopan, sentieri (invariati).
- Volume: EUMA + outcropedia + **selfguided-toscana.it** → root `/mnt/HC_Volume_102677298/html`.
- Allowlist già presente: `cache/wpml/twig/*` (Twig cache WPML).

Log: `/var/log/wp-uploads-ioc-clean.log` — verificare riga `START site=selfguided-toscana.it root=/mnt/HC_Volume_102677298/html`.

---

## WP-CLI

```bash
wp --allow-root --path="/mnt/HC_Volume_102677298/html/selfguided-toscana.it" …
```

Update da root + WP-CLI. Non da dashboard (`DISALLOW_FILE_MODS=true`). Non dare WRITE a `www-data` su codice/`upgrade/`.

---

## Smoke 2026-09-14 (WPML, verifica finale 11:14 UTC)

| URL | HTTP |
|-----|------|
| `/` | **200** |
| `/wp-login.php` | **200** |
| `/offerte-selfguided/` (shop) | **200** |
| `/carrello/` | **200** |
| `/pagamento/` | **302** → `/carrello/` (carrello vuoto, atteso Woo) |
| `/en/` (seconda lingua) | **200** |
| `/wp-admin/` | **302** (redirect login) |

Core **7.1** e WooCommerce **11.1.0** invariati. Zero Fatal. WAF `auto_prepend_file` punta a `/mnt/HC_Volume_102677298/html/selfguided-toscana.it/wordfence-waf.php`.

---

## Cosa non fare

- Aggiornare o downgrade core (resta **7.1**).
- Aggiornare da dashboard WordPress.
- Aggiornare Impreza / `us-core` / `js_composer` / `wp-geohub` senza piano Fase 2.
- Toccare **qualsiasi** plugin WooCommerce core/payments (Woo **11.1.0** FERMO).
- Stubbare `wp-geohub/index.php` o template `us-core`.
- `chmod` ricorsivo su tutto `wp-content`.
- Dare WRITE a `www-data` su `plugins/`, `themes/`, `upgrade/` o codice core.
- Dopo edit `.htaccess`: owner **`root:www-data`**, mode **`644`**.

---

## Registro interventi

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-14 | selfguided-toscana.it | agent | WPML: String **3.5.3→3.5.4**, CMS **4.9.5→4.9.7**; acfml/seo-ml/wcml già a target; ri-lock `DISALLOW_FILE_MODS=true`; smoke | **OK** | Dump/tar WPML `/root/backups/selfguided-*-wpml-20260914-111350.*`; core **7.1** e Woo **11.1.0** invariati; chiave OTGS registrata |
| 2026-09-14 | selfguided-toscana.it | agent | Hardening FS; wp-config `DISALLOW_FILE_EDIT=true`, `MODS=false`; lotto A (accessibility, head-footer-code, Wordfence **9.0.1**); OTGS **3.1.10→3.1.20** (rsync sentieri); cron volume; smoke | **OK** | Dump/tar `/root/backups/selfguided-*-20260914-105708.*`; core **7.1** invariato; Woo/WPML non toccati |

Template:

```
| AAAA-MM-GG | selfguided-toscana.it | nome | azioni | OK / KO | dump in /root/backups/… |
```
