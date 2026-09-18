# WordPress EUMA — handoff operativo (volume)

> Sito: **european-mountaineers.eu**  
> Path: `/mnt/HC_Volume_102677298/html/european-mountaineers.eu`  
> DocumentRoot Apache: stesso path (non `/var/www/html`).  
> Sessione hardening + Fase 1: **2026-09-14**.

Contesto generale:  
[`/root/docs/WORDPRESS-UPLOADS-SECURITY.md`](/root/docs/WORDPRESS-UPLOADS-SECURITY.md),  
[`/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md`](/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md).

---

## Stato post-intervento (2026-09-14)

| Voce | Valore |
|------|--------|
| Core | **6.8.8** (en_US) |
| Tema | `wm-euma-child` (parent Impreza **8.38.1**) |
| `us-core` | **8.38.2** (congelato) |
| WPBakery `js_composer` | **8.6.1** (congelato) |
| Wordfence | **9.0.1** + WAF `auto_prepend` intatto |
| `DISALLOW_FILE_EDIT` / `DISALLOW_FILE_MODS` | `true` / `true` |
| `WP_DEBUG` / `WP_DEBUG_LOG` | boolean `false` (prima erano stringhe `'false'` → truthy) |
| Owner codice | `root:www-data` |
| `wp-config.php` | `640 root:www-data` |
| `wp-content/upgrade/` | `750 root:www-data` (PHP non scrive) |
| WRITE lasciato | `uploads/`, `languages/`, `wflogs/`, `plugins/euma-tables/logs/` (`770`) |
| Login | `/wp-login.php` (`wps-hide-login` inactive) |
| AI1WM | **disattivato**; `.wpress` fuori webroot |
| Indicizzazione (`blog_public`) | **1** (abilitata 2026-09-14; prima era 0 → meta `noindex`) |

### Plugin aggiornati (Fase 1)

| Plugin | Prima → Dopo |
|--------|----------------|
| contact-form-7 | 6.1.1 → **6.1.7** |
| disable-comments | 2.5.3 → **2.9.0** |
| duplicate-post | 4.5 → **4.7** |
| wp-mail-smtp | 4.6.0 → **4.9.0** |
| the-events-calendar | 6.17.0 → **6.17.4.1** |
| wordfence | 8.1.0 → **9.0.1** |
| iubenda-cookie-law-solution | **3.13.5** (install + activate 2026-09-14; **attivo e configurato**) |
| wordpress-seo (Yoast SEO) | **25.5** (install + activate 2026-09-14; non aggiornare a 28.x su core 6.8) |

### Non toccati (congelati / inactive)

- Impreza / `us-core` / `js_composer`
- `euma-members`, `euma-tables`, mu-plugin `euma-import`
- inactive: ACF Pro, TablePress, wps-hide-login
- AI1WM (disattivato, non aggiornato)

**Nota iubenda:** plugin **attivo e configurato** (account/chiavi, privacy/cookie policy e banner ok).

**Nota Yoast:** installata **25.5** (compatibile WP 6.8.8). La 28.4 richiede WP 6.9 — non aggiornare finché il core resta sulla linea 6.8. Config SEO (titoli, sitemap, social) da wp-admin. Sitemap XML può avere `X-Robots-Tag: noindex` sul file stesso (comportamento Yoast normale); le pagine del sito sono `index, follow`.
---

## Backup / quarantena

| Artefatto | Path |
|-----------|------|
| Dump DB | `/root/backups/euma-db-backup-20260914-073024.sql` |
| Tar codice | `/root/backups/euma-files-backup-20260914-073024.tar.gz` |
| `.htaccess` pre-WF9 | `/root/backups/euma-htaccess-pre-wf9-20260914-073024.bak` |
| `wordfence-waf.php` pre-WF9 | `/root/backups/euma-wordfence-waf-pre-wf9-20260914-073024.bak` |
| Quarantena igiene | `/root/backups/euma-quarantine-20260914-073024/` (`.wpress` 1.9G, zip Impreza, WP nidificato, `false-debug.log`) |

Rollback: ripristino tar + import SQL **solo EUMA**.

---

## Cron IOC

Script: `/root/wp_uploads_ioc_clean.sh` (cron `*/30` già presente).

- Siti `/var/www/html`: parco-maremma, trekking, parcopan, sentieri (invariati).
- EUMA: root `/mnt/HC_Volume_102677298/html`.
- Allowlist aggiunta: `wpforms/cache/*`.

Log: `/var/log/wp-uploads-ioc-clean.log`.

---

## WP-CLI

```bash
wp --allow-root --path="/mnt/HC_Volume_102677298/html/european-mountaineers.eu" …
```

Update solo da root + WP-CLI. Non da dashboard (`DISALLOW_FILE_MODS`). Non dare WRITE a `www-data` su codice/`upgrade/`.

---

## Smoke 2026-09-14

Homepage, `/wp-login.php` (`#loginform`), `/contacts/`, `/events/`, `/members/`, `/map/`: HTTP **200**, zero `ushort.company` / Fatal.  
Plugin attivi: euma-members, euma-tables, us-core, js_composer, wordfence, **iubenda-cookie-law-solution**, **wordpress-seo** 25.5.

---

## Registro interventi

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-14 | european-mountaineers.eu | agent | `blog_public` 0→**1** (indicizzazione attiva) | **OK** | Meta robots `index, follow`; home/contacts 200; sitemap Yoast può avere X-Robots-Tag noindex sul XML (normale) |
| 2026-09-14 | european-mountaineers.eu | agent | Install + activate `wordpress-seo` (Yoast) **25.5**; ri-lock | **OK** | Non aggiornare a 28.x (requires WP 6.9); smoke home/contacts 200 |
| 2026-09-14 | european-mountaineers.eu | agent | Install + activate `iubenda-cookie-law-solution` **3.13.5**; ri-lock | **OK** | attivo e configurato; smoke home/contacts 200 |
| 2026-09-14 | european-mountaineers.eu | agent | Igiene (wpress/zip/nested/`false`); fix WP_DEBUG boolean; AI1WM off; lock FS `root:www-data`; core 6.8.3→**6.8.8**; CF7/disable-comments/duplicate-post/smtp; Events 6.17.4.1; Wordfence **9.0.1**; ri-lock; cron volume + allowlist wpforms | **OK** | Dump/tar `/root/backups/euma-*-20260914-073024.*`; quarantena igiene in `euma-quarantine-20260914-073024/`; smoke home/login/contacts/events/members/map 200 |

Template:

```
| AAAA-MM-GG | european-mountaineers.eu | nome | azioni | OK / KO | dump in /root/backups/… |
```
