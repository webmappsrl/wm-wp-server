# WordPress Parco della Maremma — handoff operativo

> Sito: **parco-maremma.it**  
> Path: `/var/www/html/parco-maremma.it` (equiv. `/root/html/parco-maremma.it`)  
> Sessione Fase 1 + WPML: **2026-09-14**.

Contesto generale:  
[`/root/docs/WORDPRESS-UPLOADS-SECURITY.md`](/root/docs/WORDPRESS-UPLOADS-SECURITY.md),  
[`/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md`](/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md).

---

## Stato post-intervento (2026-09-14)

| Voce | Valore |
|------|--------|
| Core | **6.8.8** (era 6.8.2) |
| Tema | `wm-maremma-child` (parent Impreza **8.19**) |
| `us-core` | **8.19.2** (congelato) |
| WPBakery `js_composer` | **6.6.0** (congelato) |
| UAVC `Ultimate_VC_Addons` | **3.19.9** (congelato + patch `bsf_registration_page_url` intatta) |
| Wordfence | **9.0.1** + WAF `auto_prepend` ok |
| TEC free / Pro | **6.14.0** / **7.6.1** (FERMI — update Pro 7.8.2 KO: licenza `invalid`/`expired` su `parco-maremma.it`) |
| WPML CMS / String / Media | **4.9.7** / **3.5.4** / **3.1.2** |
| OTGS Installer | **3.1.20** — chiave già registrata |
| `DISALLOW_FILE_EDIT` / `DISALLOW_FILE_MODS` | `true` / `true` |
| `WP_AUTO_UPDATE_CORE` | `false` |

### Plugin aggiornati (Fase 1 + WPML)

| Plugin | Prima → Dopo |
|--------|----------------|
| wp-asset-clean-up | 1.4.0.3 → **1.4.0.5** |
| contact-form-7 | 6.1 → **6.1.7** |
| mailchimp-for-wp | 4.10.5 → **4.14.1** |
| pixelyoursite | 11.0.1 → **11.4.1** |
| really-simple-ssl | 9.4.2 → **9.8.1** |
| wp-accessibility | 2.1.18 → **2.3.5** |
| wp-mail-smtp | 4.5.0 → **4.9.0** |
| duplicate-post | 4.5 → **4.7** |
| ultimate-addons-for-gutenberg | 2.19.11 → **2.20.3** |
| carousel-block | 2.0.2 → **2.1.5** |
| cc-child-pages | 1.43 → **2.1.2** |
| facetwp | 4.4.1 → **4.5** |
| flow-flow-social-streams | 4.7.5 → **5.0.5** |
| wordfence | 8.0.5 → **9.0.1** |
| sitepress-multilingual-cms | 4.7.6 → **4.9.7** |
| wpml-string-translation | 3.3.3 → **3.5.4** |
| wpml-media-translation | 2.7.7 → **3.1.2** |

### Non toccati (congelati / fermi / vendor)

- Impreza / `us-core` / `js_composer` / UAVC (patch) / `wm-embedmaps` / child
- TEC free **6.14.0** + Pro **7.6.1** (update free poi rollback 2026-09-14; ritentato Pro→7.8.2 stesso giorno → KO licenza; free non toccato)
- Yoast **25.5** FERMI; Admin Columns Pro / ACF Pro / Monarch vendor
- mu-plugin `local-by-flywheel-live-link-helper` (inerte, lasciato)

### Note tipiche del sito

- **RSS → 403:** `.htaccess` `root:root` `640` → fix `root:www-data` **644**; ripristino blocco HTTPS rewrite + `$_SERVER['HTTPS']='on'` in wp-config.
- **TEC:** non aggiornare free senza Pro licenza valida (restare in coppia 6.14.0 / 7.6.1). Stato PUE 2026-09-14: `pue_key_status_…_parco-maremma.it` = **invalid**; `…_parco-maremma.local` = valid; notice `expired_key` su Pro. Zip `events-calendar-pro-7.6.0.1.zip` era un **downgrade** rispetto a 7.6.1: spostato fuori webroot, **non** installato.
- **UAVC / admin bianco:** stessa patch di trekking — non aggiornare senza re-patch.
- Stack complesso: CAUTELA uno alla volta (cc-child-pages, facetwp, flow-flow).

---

## Backup

| Artefatto | Path |
|-----------|------|
| Dump DB | `/root/backups/maremma-db-backup-20260914-091819.sql` |
| Tar codice | `/root/backups/maremma-files-backup-20260914-091819.tar.gz` |
| `.htaccess` / WAF pre-WF9 | `/root/backups/maremma-htaccess-pre-wf9-20260914-091819.bak`, `maremma-wordfence-waf-pre-wf9-20260914-091819.bak` |
| Dump DB WPML | `/root/backups/maremma-db-backup-wpml-20260914-092912.sql` |
| Tar WPML | `/root/backups/maremma-wpml-plugins-20260914-092912.tar.gz` |
| Dump DB pre-TEC retry | `/root/backups/maremma-db-backup-tec-20260914-131818.sql` |
| Tar TEC plugins pre-retry | `/root/backups/maremma-tec-plugins-20260914-131818.tar.gz` |
| Zip Pro 7.6.0.1 (da webroot, non installato) | `/root/backups/events-calendar-pro-7.6.0.1-from-webroot-20260914-131818.zip` |

Rollback: ripristino tar + import SQL **solo maremma**.

---

## WP-CLI

```bash
wp --allow-root --path="/var/www/html/parco-maremma.it" …
```

---

## Smoke 2026-09-14

Home, `/en/`, login, admin (niente bianco), eventi, contatti: HTTP **200**.  
Post-tentativo TEC (stesso giorno): home / `/eventi/` / `/en/` / login / admin **200**, zero Fatal; Pro+free ancora **7.6.1** / **6.14.0** active; `DISALLOW_FILE_MODS` true.

---

## Registro interventi

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-14 | parco-maremma.it | agent | Tentativo TEC Pro 7.6.1→**7.8.2** (licenza rinnovata lato utente); free lasciato fermo | **KO** | WP-CLI: `Failed to update plugin. Check your license details first`; PUE `invalid`/`expired` su dominio prod; zip 7.6.0.1 spostato in backups (downgrade, non installato); free non toccato; ri-lock; smoke OK; backup `maremma-*-tec-20260914-131818.*` |
| 2026-09-14 | parco-maremma.it | agent | core **6.8.8**; lotto A + CAUTELA; Wordfence **9.0.1**; WPML String→CMS→Media; OTGS 3.1.20; ri-lock | **OK** | Dump/tar `*-20260914-091819.*` + WPML `*-092912.*`; RSS 403 fix; TEC rollback 6.14.0; UAVC/js_composer/us-core/wm-embedmaps non toccati |

Template:

```
| AAAA-MM-GG | parco-maremma.it | nome | azioni | OK / KO | dump in /root/backups/… |
```
