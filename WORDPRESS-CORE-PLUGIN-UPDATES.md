# WordPress — aggiornamento core e plugin

> Handoff operativo per chi aggiorna i vhost WordPress Webmapp (bonifica `/var/www/html` + volume Hetzner).  
> Path siti bonifica: `/root/html/<vhost>` → `/var/www/html/<vhost>`.  
> Path siti volume: `/mnt/HC_Volume_102677298/html/<vhost>`.  
> Documento **vivo**: aggiornare la sezione [Registro interventi](#registro-interventi) a ogni sessione (data, sito, cosa è stato fatto, esito, rollback).
>
> Inventario e piano iniziali: **2026-09-10**.  
> Contesto sicurezza / lock write / IOC: [`WORDPRESS-UPLOADS-SECURITY.md`](WORDPRESS-UPLOADS-SECURITY.md).

**Stato al 2026-09-14:** documentazione operativa centralizzata in [`/root/docs/`](/root/docs/). Su **`/var/www/html`**, tutti e quattro i siti completati (core **6.8.8** + plugin Fase 1 + **WPML**): [`sentierodeiducati.it`](/root/docs/WORDPRESS-SENTIERI-HANDOFF.md), [`parcopan.org`](/root/docs/WORDPRESS-PARCOPAN-HANDOFF.md), [`trekking.parcoforestecasentinesi.it`](/root/docs/WORDPRESS-TREKKING-HANDOFF.md), [`parco-maremma.it`](/root/docs/WORDPRESS-MAREMMA-HANDOFF.md). Su **volume** (**otto** siti nel cron IOC): **`european-mountaineers.eu`** completato (core **6.8.8** + Fase 1, **no WPML**) — [`WORDPRESS-EUMA-HANDOFF.md`](/root/docs/WORDPRESS-EUMA-HANDOFF.md); **`outcropedia.org`** completato (core **6.8.8** + Fase 1 + **WPML**) — [`WORDPRESS-OUTCROPEDIA-HANDOFF.md`](/root/docs/WORDPRESS-OUTCROPEDIA-HANDOFF.md); **`selfguided-toscana.it`** completato (core **7.1** lasciato invariato, hardening + lotto A + OTGS + **WPML String/CMS**) — [`WORDPRESS-SELFGUIDED-HANDOFF.md`](/root/docs/WORDPRESS-SELFGUIDED-HANDOFF.md); **`acquasorgente.cai.it`** completato (core **6.8.8** + Fase 1 + **WPML** + OTGS) — [`WORDPRESS-ACQUASORGENTE-HANDOFF.md`](/root/docs/WORDPRESS-ACQUASORGENTE-HANDOFF.md).

---

## Perimetro

Solo questi quattro siti:

| Sito | Core attuale | Target Fase 1 | Theme parent | Child | Dettaglio |
|------|--------------|---------------|--------------|-------|-----------|
| `sentierodeiducati.it` | **6.8.8** (fatto) | — | Impreza 8.23.2 | `wm-caire-child` | [`WORDPRESS-SENTIERI-HANDOFF.md`](/root/docs/WORDPRESS-SENTIERI-HANDOFF.md) |
| `parcopan.org` | **6.8.8** (fatto) | — | Impreza 8.23.4 | `wm-parcopan-child` | [`WORDPRESS-PARCOPAN-HANDOFF.md`](/root/docs/WORDPRESS-PARCOPAN-HANDOFF.md) |
| `trekking.parcoforestecasentinesi.it` | **6.8.8** (fatto) | — | Impreza 8.22 | `wm-pnfc-child` | [`WORDPRESS-TREKKING-HANDOFF.md`](/root/docs/WORDPRESS-TREKKING-HANDOFF.md) |
| `parco-maremma.it` | **6.8.8** (fatto) | — | Impreza 8.19 | `wm-maremma-child` | [`WORDPRESS-MAREMMA-HANDOFF.md`](/root/docs/WORDPRESS-MAREMMA-HANDOFF.md) |

Altri vhost sotto `/root/html` **non** rientrano in questo piano (salvo sezione volume sotto).

Ambiente server (2026-09-10): PHP **8.1.2** (EOL), WP-CLI presente, Imagick PHP **non** caricato.

---

## Perimetro volume (`/mnt/HC_Volume_102677298/html`)

Siti su document root **diverso** da `/var/www/html`. Stessa procedura Fase 1, path WP-CLI dedicato.

| Sito | Path WP-CLI | Core | Tema | Congelati | Dettaglio |
|------|-------------|------|------|-----------|-----------|
| `european-mountaineers.eu` | `/mnt/HC_Volume_102677298/html/european-mountaineers.eu` | **6.8.8** (en_US) — fatto 2026-09-14 | Impreza **8.38.1** + `wm-euma-child` | `us-core` **8.38.2**, `js_composer` **8.6.1**, `euma-members`, `euma-tables` | [`WORDPRESS-EUMA-HANDOFF.md`](/root/docs/WORDPRESS-EUMA-HANDOFF.md) |
| `outcropedia.org` | `/mnt/HC_Volume_102677298/html/outcropedia.org` | **6.8.8** (en_US) — fatto 2026-09-14 | Impreza **8.36.1** + `wm-outcropedia-child` | `us-core` **8.36.3**, `js_composer` **8.5**, `wp-geohub` **1.2** | [`WORDPRESS-OUTCROPEDIA-HANDOFF.md`](/root/docs/WORDPRESS-OUTCROPEDIA-HANDOFF.md) |
| `selfguided-toscana.it` | `/mnt/HC_Volume_102677298/html/selfguided-toscana.it` | **7.1** (en_US) — **lasciato invariato** 2026-09-14 | Impreza **8.35.2** + `wm-child-sgt` | `us-core` **8.35.3**, `js_composer` **8.4.1**, `wp-geohub` **1.2**, Woo **11.1.0** FERMO; WPML **4.9.7** / String **3.5.4** | [`WORDPRESS-SELFGUIDED-HANDOFF.md`](/root/docs/WORDPRESS-SELFGUIDED-HANDOFF.md) |
| `acquasorgente.cai.it` | `/mnt/HC_Volume_102677298/html/acquasorgente.cai.it` | **6.8.8** (it_IT) — fatto 2026-09-14 | `acquasorgente` (custom CAI) | tema `acquasorgente`, Wordfence **9.0.1**, Yoast **25.4**, Sucuri **2.2**, WPForms **1.9.6.2**; WPML **4.9.7** / String **3.5.4** / ACFML **2.2.4** | [`WORDPRESS-ACQUASORGENTE-HANDOFF.md`](/root/docs/WORDPRESS-ACQUASORGENTE-HANDOFF.md) |

---

## Decisioni vincolanti

1. **Fase 1 (questa linea di lavoro):** core **6.8.8** (minor/security) + plugin wordpress.org a basso/medio rischio. Un sito alla volta.
2. **Non** aggiornare a WordPress **7.x** in Fase 1. La linea 6.8 non è più quella “attivamente mantenuta” da wordpress.org, ma 7.1 richiede Impreza/`us-core` recenti (fix WP 7.1 in us-core **9.2.x**). Con il tema fermo, 7.1 non è percorribile.
3. **Impreza non si aggiorna.** La stessa licenza Envato è stata usata su più siti: l’updater ufficiale non è utilizzabile. Trattare come **congelati**:
   - tema parent **Impreza**
   - plugin **`us-core`** (deve restare sulla stessa linea del tema installato; non aggiornare `us-core` da solo)
   - **`js_composer`** (WPBakery) — stack visivo di Impreza; aggiornarlo staccato dal tema rompe l’editor
   - **`Ultimate_VC_Addons`** (maremma + trekking)
   - child theme Webmapp
4. **Non** aggiornare da `wp-admin`. `DISALLOW_FILE_MODS` + `DISALLOW_FILE_EDIT` sono attivi; `wp-content/upgrade` non è scrivibile da PHP. Gli update si fanno da **root + WP-CLI** (o rsync da pacchetti ufficiali). Non `chown` a `www-data`.
5. Plugin custom Webmapp **non** si toccano da wordpress.org / `git pull` cieco:
   - `wm-embedmaps` (maremma)
   - `wp-geohub` (parcopan, sentieri)
   - `wm-package` (trekking) — working tree **sporco** (vedi sotto)
   - `euma-members`, `euma-tables` (EUMA)
6. Lasciare acceso il cron IOC uploads (`*/30 * * * * /root/wp_uploads_ioc_clean.sh`) — **otto** siti: quattro su `/var/www/html` + EUMA + outcropedia + selfguided + acquasorgente su volume.

---

## Ordine dei siti (rischio crescente)

1. ~~`sentierodeiducati.it`~~ — **fatto 2026-09-10** (pilota OK)
2. ~~`parcopan.org`~~ — **fatto 2026-09-10** (Woo + LiteSpeed OK)
3. ~~`trekking.parcoforestecasentinesi.it`~~ — **fatto 2026-09-10** (core/plugin Fase 1 + WPML)
4. ~~`parco-maremma.it`~~ — **fatto 2026-09-14** (stack complesso; TEC+Pro ancora **6.14.0/7.6.1**: ritento Pro 7.8.2 KO licenza PUE invalid/expired)

Se un sito va storto: **stop**, rollback di **quel** sito, non procedere sugli altri.

---

## Procedura sicura (ogni sito)

Eseguire nello stesso ordine. Non saltare backup né ri-lock.

1. Finestra di manutenzione: non pubblicare contenuti durante l’intervento.
2. **Backup fresco** fuori webroot, mode `600` (i dump del 2026-09-09 **non** bastano):
   - DB: `mysqldump --single-transaction --routines --triggers` (credenziali da `wp-config.php`, file extra `600`). Warning `PROCESS`/tablespaces: ignorabile se `test -s` sul dump; opzionale `--no-tablespaces`.
   - file: tar di `wp-admin`, `wp-includes`, PHP di root, `wp-content/plugins`, tema child, `wp-config.php`, `.htaccess`
   - destinazione: `/root/backups/`
   - Prima di Wordfence 9: copia anche `.htaccess` e `wordfence-waf.php` in `/root/backups/`
3. Baseline: grep `ushort.company` (esclusi dump SQL) + `tail` log IOC `/var/log/wp-uploads-ioc-clean.log`.
4. Maintenance WP.
5. Sbloccare **solo** la costante `DISALLOW_FILE_MODS` → `false` in `wp-config.php`. **Non** cambiare owner/mode del codice a `www-data`.
6. Core prima dei plugin:
   ```bash
   wp --allow-root --path="/root/html/<vhost>" core update --version=6.8.8
   wp --allow-root --path="/root/html/<vhost>" core update-db
   wp --allow-root --path="/root/html/<vhost>" core version
   ```
   Verifica: homepage, login, `wp-admin`, `wp-includes/version.php` = `6.8.8`.
7. Plugin **lotto A** (solo voci “OK” delle tabelle sotto). Pochi alla volta. Dopo ogni lotto: homepage + una pagina chiave (mappa / form / shop).
8. Plugin **lotto B** (CAUTELA), **uno per volta**.
9. **Non** in questa finestra: Impreza, `us-core`, WPBakery, UAVC, plugin custom, WP 7.x.
10. Ripristinare `DISALLOW_FILE_MODS` → `true`. Verificare owner `root:www-data` e che `wp-content/upgrade` resti non scrivibile da PHP.
11. Togliere maintenance. Test: homepage, login, dashboard (maremma/trekking: niente admin bianco), una pagina WPML, form, mappa GeoHub/embedmaps; su parcopan anche shop/checkout.
12. Grep malware + log IOC. Aggiornare il [Registro interventi](#registro-interventi) in questo file.

**Rollback:** ripristino tar + import SQL **di quel sito**, non degli altri.

**WP-CLI:** `--allow-root`. I file restano di `root`; PHP-FPM non deve poter scrivere core/plugin/theme.

**Path WP-CLI per document root:**

- Bonifica (maremma, parcopan, sentieri, trekking): `--path="/var/www/html/<vhost>"` (o `/root/html/<vhost>`).
- Volume (EUMA e futuri vhost Hetzner): `--path="/mnt/HC_Volume_102677298/html/<vhost>"`.

---

## Cosa non fare

- Aggiornare da dashboard WordPress.
- Saltare a WordPress 7.1 (o 7.0 / 6.9) mentre Impreza è fermo su 8.19–8.23.
- Aggiornare `us-core` senza Impreza (mismatch builder).
- Aggiornare `js_composer` o `Ultimate_VC_Addons`.
- `git pull` su `wm-package` (modifiche locali non committate).
- Stubbare `index.php` bootstrap (`wp-geohub`, `wm-package`, `cc-child-pages`, `us-core/templates`, `bsf-core`). In bonifica questo ha già spento plugin.
- Aggiornare WPML a pezzi (CMS senza String / Media / ACFML / SEO).
- Cambiare password utenti o versione PHP nella stessa finestra degli update.
- Lasciare dump `.sql` in document root.

---

## Inventario plugin (2026-09-10)

Legenda azioni Fase 1:

| Etichetta | Significato |
|-----------|-------------|
| **OK** | wordpress.org, lotto A |
| **CAUTELA** | lotto B, uno alla volta, backup già fatto |
| **WPML** | insieme, da account WPML; non mescolare al lotto A |
| **VENDOR** | licenza / ThemeForest — fuori Fase 1 |
| **CONGELATO** | Impreza / us-core / WPBakery / UAVC / child / custom |
| **FERMI** | WP-CLI non offre update; verificare a mano prima di forzare |
| **INACTIVE** | spento; preferire rimozione se inutilizzato, non update “tanto per” |

Versioni “disponibili” rilevate con WP-CLI il **2026-09-10**. Rileggere `wp plugin list` prima di ogni sessione: i numeri si muovono.

### sentierodeiducati.it

> Aggiornato **2026-09-10** (pilota + WPML). Core **6.8.8**. Backup:  
> `/root/backups/sentierodeiducati-db-backup-20260910-124148.sql`  
> `/root/backups/sentierodeiducati-files-backup-20260910-124148.tar.gz`  
> WPML: `/root/backups/sentierodeiducati-db-backup-wpml-20260910-132947.sql`  
> `/root/backups/sentierodeiducati-wpml-plugins-20260910-132947.tar.gz`  
> Dettaglio: [`WORDPRESS-SENTIERI-HANDOFF.md`](/root/docs/WORDPRESS-SENTIERI-HANDOFF.md)

| Plugin | Installata | Disponibile WP-CLI | Azione |
|--------|------------|--------------------|--------|
| contact-form-7 | **6.1.7** | — | fatto (era 6.0.6) |
| add-to-any | **1.8.18** | — | fatto (era 1.8.13) |
| disable-comments | **2.9.0** | — | fatto (era 2.5.2) |
| contact-form-cfdb7 | **1.4.0** | — | fatto (era 1.3.0) |
| wp-mail-smtp | **4.9.0** | — | fatto (era 4.5.0) |
| ultimate-addons-for-gutenberg | **2.20.3** | — | fatto (era 2.19.9) |
| advanced-custom-fields | **6.8.9** | — | fatto (era 6.4.2) |
| acfml | **2.2.4** | — | fatto WPML (era 2.1.5) |
| wordfence | **9.0.1** | — | fatto (era 8.2.1); WAF `auto_prepend` ok |
| sitepress-multilingual-cms | **4.9.7** | — | fatto WPML (era 4.7.6) |
| wpml-string-translation | **3.5.4** | — | fatto WPML (era 3.3.3) |
| wp-seo-multilingual | **2.2.5** | — | fatto WPML (era 2.1.1) |
| otgs-installer-plugin | **3.1.20** | — | attivo; chiave sito registrata |
| wordpress-seo | 25.3 | — | FERMI |
| js_composer | 7.6 | — | CONGELATO |
| us-core | 8.23.2 | — | CONGELATO (allineato Impreza 8.23.2) |
| wp-geohub | 1.0 | — | CONGELATO (git `webmappsrl/wp-geohub`) |
| wm-caire-child | 8.23.2… | — | CONGELATO |

### parcopan.org

> Aggiornato **2026-09-10** (core/plugin + WPML). Core **6.8.8**. Backup:  
> `/root/backups/parcopan-db-backup-20260910-134820.sql`  
> `/root/backups/parcopan-files-backup-20260910-134820.tar.gz`  
> WAF pre-WF9: `parcopan-htaccess-pre-wf9-20260910.bak`, `parcopan-wordfence-waf-pre-wf9-20260910.bak`  
> WPML: `/root/backups/parcopan-db-backup-wpml-20260910-142422.sql`  
> `/root/backups/parcopan-wpml-plugins-20260910-142422.tar.gz`  
> Dettaglio: [`WORDPRESS-PARCOPAN-HANDOFF.md`](/root/docs/WORDPRESS-PARCOPAN-HANDOFF.md)

| Plugin | Installata | Disponibile WP-CLI | Azione |
|--------|------------|--------------------|--------|
| contact-form-7 | **6.1.7** | — | fatto (era 6.1) |
| add-to-any | **1.8.18** | — | fatto (era 1.8.13) |
| disable-comments | **2.9.0** | — | fatto (era 2.5.2) |
| iubenda-cookie-law-solution | **3.13.5** | — | fatto (era 3.12.4) |
| wp-mail-smtp | **4.9.0** | — | fatto (era 4.5.0) |
| wp-accessibility | **2.3.5** | — | fatto (era 2.1.18) |
| wp-sitemap-page | **1.9.6** | — | fatto (era 1.9.5) |
| really-simple-ssl | **9.8.1** | — | fatto (era 9.4.2); **attenzione `.htaccess` owner** |
| litespeed-cache | **7.9.1** | — | fatto (era 7.2); purge dopo; **post-fix**: blocco LSCACHE root 7.9.1 + `wp-content/litespeed/` 770 |
| wordfence | **9.0.1** | — | fatto (era 8.0.5); WAF ok |
| contact-form-7-multilingual | **1.3.3** | — | fatto WPML (era 1.3.2) |
| sitepress-multilingual-cms | **4.9.7** | — | fatto WPML (era 4.7.6) |
| wpml-string-translation | **3.5.4** | — | fatto WPML (era 3.3.3) |
| otgs-installer-plugin | **3.1.20** | — | attivo; chiave sito registrata |
| woocommerce | 10.0.2 | — | FERMI |
| woocommerce-checkout-manager | 7.7.2 | 7.9.6 | INACTIVE |
| woocommerce-multilingual | 5.5.1 | 5.5.7 | INACTIVE |
| wordpress-seo | 25.5 | — | FERMI |
| advanced-custom-fields-pro | 6.2.7 | — | VENDOR |
| js_composer | 7.6 | — | CONGELATO |
| us-core | 8.23.4 | — | CONGELATO |
| wp-geohub | 1.0 | — | CONGELATO |
| wm-parcopan-child | — | — | CONGELATO |

### trekking.parcoforestecasentinesi.it

> Aggiornato **2026-09-10** (core/plugin Fase 1 + WPML). Core **6.8.8**. Backup:  
> `/root/backups/trekking-db-backup-20260910-143519.sql`  
> `/root/backups/trekking-files-backup-20260910-143519.tar.gz`  
> WAF pre-WF9: `trekking-htaccess-pre-wf9-20260910-143519.bak`, `trekking-wordfence-waf-pre-wf9-20260910-143519.bak`  
> Redirection export: `trekking-redirection-export-20260910-143519.json` + `trekking-redirection-tables-20260910-143519.sql`  
> WPML: `/root/backups/trekking-db-backup-wpml-20260910-145438.sql`  
> `/root/backups/trekking-wpml-plugins-20260910-145438.tar.gz`  
> Dettaglio: [`WORDPRESS-TREKKING-HANDOFF.md`](/root/docs/WORDPRESS-TREKKING-HANDOFF.md)

| Plugin | Installata | Disponibile WP-CLI | Azione |
|--------|------------|--------------------|--------|
| disable-comments | **2.9.0** | — | fatto (era 2.5.2) |
| carousel-block | **2.1.5** | — | fatto (era 2.0.1) |
| iubenda-cookie-law-solution | **3.13.5** | — | fatto (era 3.12.3) |
| really-simple-ssl | **9.8.1** | — | fatto (era 9.4.0); `.htaccess` resta `root:www-data` **644** (su questo vhost `640` ha dato 403); blocco HTTPS rewrite RSS rimosso dall’update (resta `$_SERVER["HTTPS"]="on"` in wp-config) |
| wp-mail-smtp | **4.9.0** | — | fatto (era 4.5.0) |
| redirection | **5.10.0** | — | fatto (era 5.5.2); export 20 regole prima |
| stops-core-theme-and-plugin-updates | **9.0.22** | — | fatto (era 9.0.19) |
| advanced-custom-fields | **6.8.9** | — | fatto (era 6.4.2) |
| wordfence | **9.0.1** | — | fatto (era 8.0.5); WAF `auto_prepend` ok |
| sitepress-multilingual-cms | **4.9.7** | — | fatto WPML (era 4.7.6) |
| wpml-string-translation | **3.5.4** | — | fatto WPML (era 3.3.3) |
| wp-seo-multilingual | **2.2.5** | — | fatto WPML (era 2.1.1) |
| otgs-installer-plugin | **3.1.20** | — | attivo; chiave sito registrata |
| wordpress-seo | 25.3 | — | FERMI |
| Ultimate_VC_Addons | 3.19.9 | — | CONGELATO (+ patch `bsf_registration_page_url`, non perdere) |
| js_composer | 7.4 | — | CONGELATO |
| us-core | 8.22.2 | — | CONGELATO (Impreza 8.22) |
| wm-package | 2.0 | — | CONGELATO — **non `git pull`** |
| wm-pnfc-child | 0.0.1 | — | CONGELATO |

`wm-package` (2026-09-10): origin `github.com/webmappsrl/wp-geohub`, branch `main` con modifiche locali non committate:

- `admin_page.php`
- `shortcodes/grid_poi.php`
- `shortcodes/grid_track.php`
- `shortcodes/single_poi.php`

Un pull sovrascrive queste customizzazioni e può disattivare il plugin (già successo in bonifica stubbando `index.php`).

### european-mountaineers.eu

> Aggiornato **2026-09-14** (hardening + Fase 1, **no WPML**). Core **6.8.8**. Backup:  
> `/root/backups/euma-db-backup-20260914-073024.sql`  
> `/root/backups/euma-files-backup-20260914-073024.tar.gz`  
> Dettaglio: [`WORDPRESS-EUMA-HANDOFF.md`](/root/docs/WORDPRESS-EUMA-HANDOFF.md)

| Plugin | Versione | Azione |
|--------|----------|--------|
| contact-form-7 | **6.1.7** | fatto (era 6.1.1) |
| disable-comments | **2.9.0** | fatto (era 2.5.3) |
| duplicate-post | **4.7** | fatto (era 4.5) |
| wp-mail-smtp | **4.9.0** | fatto (era 4.6.0) |
| the-events-calendar | **6.17.4.1** | fatto (era 6.17.0) |
| wordfence | **9.0.1** | fatto (era 8.1.0); WAF `auto_prepend` ok |
| iubenda-cookie-law-solution | **3.13.5** | install + activate 2026-09-14; **attivo e configurato** |
| wordpress-seo | **25.5** | install + activate 2026-09-14; **non aggiornare a 28.x** (requires WP 6.9) finché core resta 6.8 |
| js_composer | 8.6.1 | CONGELATO |
| us-core | 8.38.2 | CONGELATO (Impreza 8.38.1) |
| euma-members | 2.0.0 | CONGELATO |
| euma-tables | 4.1.0 | CONGELATO — **`plugins/euma-tables/logs/`** resta WRITE (`770`) |
| euma-import | — | CONGELATO (mu-plugin) |
| advanced-custom-fields-pro | 6.5.0.1 | INACTIVE — non aggiornato |
| tablepress | 3.2.1 | INACTIVE — non aggiornato |
| wps-hide-login | 1.9.17.2 | INACTIVE — non aggiornato |
| all-in-one-wp-migration | 7.99 | INACTIVE — **disattivato**; `.wpress` fuori webroot |

### outcropedia.org

> Aggiornato **2026-09-14** (hardening + Fase 1 + WPML). Core **6.8.8**. Backup:  
> `/root/backups/outcropedia-db-backup-20260914-095002.sql`  
> `/root/backups/outcropedia-files-backup-20260914-095002.tar.gz`  
> WPML: `/root/backups/outcropedia-db-backup-wpml-20260914-101623.sql`  
> `/root/backups/outcropedia-wpml-plugins-20260914-101623.tar.gz`  
> OTGS completamento: `/root/backups/outcropedia-db-backup-wpml2-20260914-103857.sql`  
> `/root/backups/outcropedia-wpml2-plugins-20260914-103857.tar.gz`  
> Dettaglio: [`WORDPRESS-OUTCROPEDIA-HANDOFF.md`](/root/docs/WORDPRESS-OUTCROPEDIA-HANDOFF.md)

| Plugin | Versione | Azione |
|--------|----------|--------|
| add-to-any | **1.8.18** | fatto |
| advanced-custom-fields | **6.8.10** | fatto |
| custom-post-type-ui | **1.19.3** | fatto |
| duplicate-post | **4.7** | fatto |
| wp-mail-smtp | **4.9.0** | fatto |
| wordfence | **9.0.1** | fatto; WAF `auto_prepend` ok |
| wpml-string-translation | **3.5.4** | fatto WPML |
| sitepress-multilingual-cms | **4.9.7** | fatto WPML |
| acfml | **2.2.4** | fatto WPML |
| wp-seo-multilingual | **2.2.5** | fatto WPML |
| otgs-installer-plugin | **3.1.20** | attivo; chiave sito **registrata** |
| wordpress-seo | **25.5** | FERMI — non aggiornare a 28.x (requires WP 6.9) |
| js_composer | 8.5 | CONGELATO |
| us-core | 8.36.3 | CONGELATO (Impreza 8.36.1) |
| wp-geohub | 1.2 | CONGELATO |
| wm-outcropedia-child | 8.36.1… | CONGELATO |
| all-in-one-wp-migration | 7.97 | INACTIVE — **disattivato** |
| all-in-one-wp-migration-unlimited-extension | 2.73 | INACTIVE — non aggiornato |

### selfguided-toscana.it

> Aggiornato **2026-09-14** (hardening + lotto A + OTGS + WPML). Core **7.1** lasciato invariato. Backup:  
> `/root/backups/selfguided-db-backup-20260914-105708.sql`  
> `/root/backups/selfguided-files-backup-20260914-105708.tar.gz`  
> WPML: `/root/backups/selfguided-db-backup-wpml-20260914-111350.sql`  
> `/root/backups/selfguided-wpml-plugins-20260914-111350.tar.gz`  
> Dettaglio: [`WORDPRESS-SELFGUIDED-HANDOFF.md`](/root/docs/WORDPRESS-SELFGUIDED-HANDOFF.md)

| Plugin | Versione | Azione |
|--------|----------|--------|
| accessibility-widget | **3.2.6** | fatto (era 3.2.5) |
| head-footer-code | **1.5.9** | fatto (era 1.5.8) |
| wordfence | **9.0.1** | fatto (era 9.0.0); WAF `auto_prepend` ok |
| otgs-installer-plugin | **3.1.20** | attivo; chiave sito **registrata** |
| wpml-string-translation | **3.5.4** | fatto WPML (era 3.5.3) |
| sitepress-multilingual-cms | **4.9.7** | fatto WPML (era 4.9.5) |
| acfml | **2.2.4** | fatto WPML (già a target) |
| wp-seo-multilingual | **2.2.5** | fatto WPML (già a target) |
| woocommerce-multilingual | **5.5.7** | fatto WPML (già a target) |
| woocommerce | **11.1.0** | FERMO |
| js_composer | 8.4.1 | CONGELATO |
| us-core | 8.35.3 | CONGELATO (Impreza 8.35.2) |
| wp-geohub | 1.2 | CONGELATO |
| wm-child-sgt | 2.0 | CONGELATO |
| wordpress-seo | 28.4 | FERMO — non toccato |

### acquasorgente.cai.it

> Aggiornato **2026-09-14** (hardening + Fase 1 + WPML + OTGS). Core **6.8.8**. Backup:  
> `/root/backups/acquasorgente-db-backup-20260914-113900.sql`  
> `/root/backups/acquasorgente-files-backup-20260914-113900.tar.gz`  
> WPML: `/root/backups/acquasorgente-wpml-plugins-20260914-114430.tar.gz`  
> Dettaglio: [`WORDPRESS-ACQUASORGENTE-HANDOFF.md`](/root/docs/WORDPRESS-ACQUASORGENTE-HANDOFF.md)

| Plugin | Versione | Azione |
|--------|----------|--------|
| advanced-custom-fields | **6.8.10** | fatto |
| wp-mail-smtp | **4.9.0** | fatto |
| wp-crontrol | **1.21.2** | fatto |
| wpml-string-translation | **3.5.4** | fatto WPML (era 3.3.3) |
| sitepress-multilingual-cms | **4.9.7** | fatto WPML (era 4.7.6) |
| acfml | **2.2.4** | fatto WPML (era 2.1.5) |
| otgs-installer-plugin | **3.1.20** | attivo; chiave sito **registrata** (rsync da sentieri) |
| wordfence | **9.0.1** | già a target; WAF `auto_prepend` ok |
| wordpress-seo | **25.4** | FERMI — non aggiornare a 28.x |
| sucuri-scanner | **2.2** | FERMO |
| wpforms-lite | **1.9.6.2** | FERMO |
| acquasorgente (tema) | — | CONGELATO (custom CAI) |
| all-in-one-wp-migration | 7.96 | INACTIVE — **disattivato** |
| all-in-one-wp-migration-unlimited-extension | 2.73 | INACTIVE — non aggiornato |

### parco-maremma.it

> Aggiornato **2026-09-14** (core/plugin Fase 1 + WPML). Core **6.8.8**. Backup:  
> `/root/backups/maremma-db-backup-20260914-091819.sql`  
> `/root/backups/maremma-files-backup-20260914-091819.tar.gz`  
> WAF pre-WF9: `maremma-htaccess-pre-wf9-20260914-091819.bak`, `maremma-wordfence-waf-pre-wf9-20260914-091819.bak`  
> WPML: `/root/backups/maremma-db-backup-wpml-20260914-092912.sql`  
> `/root/backups/maremma-wpml-plugins-20260914-092912.tar.gz`  
> Dettaglio: [`WORDPRESS-MAREMMA-HANDOFF.md`](/root/docs/WORDPRESS-MAREMMA-HANDOFF.md)

| Plugin | Installata | Disponibile WP-CLI | Azione |
|--------|------------|--------------------|--------|
| wp-asset-clean-up | **1.4.0.5** | — | fatto (era 1.4.0.3) |
| contact-form-7 | **6.1.7** | — | fatto (era 6.1) |
| mailchimp-for-wp | **4.14.1** | — | fatto (era 4.10.5) |
| pixelyoursite | **11.4.1** | — | fatto (era 11.0.1) |
| really-simple-ssl | **9.8.1** | — | fatto (era 9.4.2); `.htaccess` era `root:root` `640` → 403, fix `root:www-data` **644**; blocco HTTPS rewrite ripristinato + `$_SERVER['HTTPS']='on'` in wp-config |
| wp-accessibility | **2.3.5** | — | fatto (era 2.1.18) |
| wp-mail-smtp | **4.9.0** | — | fatto (era 4.5.0) |
| duplicate-post | **4.7** | — | fatto (era 4.5) |
| ultimate-addons-for-gutenberg | **2.20.3** | — | fatto (era 2.19.11) |
| carousel-block | **2.1.5** | — | fatto (era 2.0.2) |
| cc-child-pages | **2.1.2** | — | fatto (era 1.43) |
| facetwp | **4.5** | — | fatto (era 4.4.1) |
| flow-flow-social-streams | **5.0.5** | — | fatto (era 4.7.5) |
| the-events-calendar | **6.14.0** | 6.17.4.1 | **FERMI** — non aggiornare senza Pro OK; ritentato 2026-09-14 dopo renew: Pro ancora KO → free invariato |
| events-calendar-pro | **7.6.1** | 7.8.2 | **FERMI** — ritento 2026-09-14: stesso errore licenza; PUE `invalid`/`expired` su `parco-maremma.it` (valid solo su `.local`); zip 7.6.0.1 in backups, non installato |
| wordfence | **9.0.1** | — | fatto (era 8.0.5); WAF `auto_prepend` ok |
| sitepress-multilingual-cms | **4.9.7** | — | fatto WPML (era 4.7.6) |
| wpml-string-translation | **3.5.4** | — | fatto WPML (era 3.3.3) |
| wpml-media-translation | **3.1.2** | — | fatto WPML (era 2.7.7) |
| otgs-installer-plugin | **3.1.20** | — | attivo; chiave sito già registrata |
| wordpress-seo | 25.5 | — | FERMI |
| Ultimate_VC_Addons | 3.19.9 | — | CONGELATO (+ patch `bsf_registration_page_url`, intatta) |
| js_composer | **6.6.0** | — | CONGELATO |
| us-core | 8.19.2 | — | CONGELATO (Impreza 8.19) |
| admin-columns-pro | 6.4.14 | 7.1.5 | VENDOR — non aggiornato |
| advanced-custom-fields-pro | 6.2.3 | — | VENDOR |
| monarch | 1.4.14 | — | VENDOR |
| really-simple-captcha | 2.4 | — | nessun update |
| regenerate-thumbnails | 3.1.6 | — | nessun update |
| ssl-insecure-content-fixer | 2.7.2 | — | nessun update |
| update-alt-attribute | 2.4.2 | — | nessun update |
| wm-embedmaps | 0.0.2 | — | CONGELATO |
| wm-maremma-child | 2.0 | — | CONGELATO |
| local-by-flywheel-live-link-helper (mu-plugin) | 2.0 | — | residuo Local; lasciato (inerte senza `X-Original-Host`) |

---

## Note tecniche da non perdere

### Hardening (non disfare)

Tutti e 4: `DISALLOW_FILE_EDIT` + `DISALLOW_FILE_MODS`.  
`FS_METHOD=direct` resta; non implica che PHP possa scrivere.  
`WP_AUTO_UPDATE_CORE` è `false` su maremma e parcopan; su sentieri e trekking non è definito — non attivare auto-update.

Dopo ogni sessione: `wp-content/upgrade` deve restare non scrivibile da `www-data` (`750 root:www-data`; verificare con `sudo -u www-data test ! -w …/upgrade`).

### UAVC / admin bianco

Su maremma e trekking, `Ultimate_VC_Addons` 3.19.9 ha già causato dashboard bianca (`#wpwrap` troncato, fatal PHP in `bsf-core`). C’è una guard `function_exists('bsf_registration_page_url')` in `admin/admin.php` e un `admin/bsf-core/index.php` ripristinato. **Qualsiasi** aggiornamento UAVC va fatto solo con pacchetto vendor e re-applicazione di questa patch, fuori Fase 1.

### Wordfence 8 → 9

Salto major. Farlo come passo dedicato. Dopo: WAF `auto_prepend`, login, scanner. Non disinstallare/reinstallare “a pulire” senza backup: tabelle `wf*` e `wordfence-waf.php`.

Sul pilota sentieri (8.2.1 → 9.0.1) WAF e `wordfence-waf.php` sono restati al posto; su parcopan, trekking e **maremma** (partivano da **8.0.5**) stesso esito. Su maremma backup WAF fatto: `maremma-htaccess-pre-wf9-20260914-091819.bak`, `maremma-wordfence-waf-pre-wf9-20260914-091819.bak`.

### WPML

Aggiornare CMS + String (+ Media su maremma) (+ ACFML / SEO / CF7 multilingual dove presenti) **nello stesso lotto**. Su sentieri (2026-09-10) lo stack è già aggiornato: String **3.5.4**, CMS **4.9.7**, ACFML **2.2.4**, SEO **2.2.5**. Su parcopan (2026-09-10): String **3.5.4**, CMS **4.9.7**, CF7 multilingual **1.3.3** (niente ACFML/SEO-ML su questo sito). Su trekking (2026-09-10): String **3.5.4**, CMS **4.9.7**, SEO-ML **2.2.5**. Su maremma (2026-09-14): String **3.5.4**, CMS **4.9.7**, Media **3.1.2**.

#### OTGS Installer + chiave sito

Su questi vhost gli update WPML **non** vanno fatti da dashboard se `wp-content/upgrade/` è locked (errore tipico: *Impossibile creare la directory …/upgrade/…*). Usare **WP-CLI da root**.

Se manca l’installer commerciale:

1. Scaricare lo zip ufficiale **OTGS Installer** da wpml.org (es. `otgs-installer-plugin.x.y.z.zip`).
2. Estrarlo in `wp-content/plugins/otgs-installer-plugin/`, `chown root:www-data`, attivare (`wp plugin activate otgs-installer-plugin`).
3. Non lasciare lo zip in `plugins/` (scaricabile via HTTP).
4. In admin: voce **OTGS Installer** oppure **Plugin → Aggiungi nuovo → Commercial**; inserire la **chiave sito** associata al dominio su wpml.org (stato “Registrato”).
5. L’installer può restare attivo dopo gli update; non è un sostituto del lock write.

Nota: WPML Multilingual CMS include già un OTGS Installer *bundled* in `vendor/otgs/installer`. Il plugin standalone serve quando manca la scheda Commercial / la registrazione sito.

##### Scheda Commercial e `DISALLOW_FILE_MODS` (visto su parcopan)

`plugin-install.php?tab=commercial` richiede la capability `install_plugins`. Con `DISALLOW_FILE_MODS` a `true`, WordPress mappa quella capability a `do_not_allow` (`wp-includes/capabilities.php`, case `install_plugins` / `wp_is_file_mod_allowed`). Risultato in admin: **«Non hai il permesso di accedere a questa pagina.»** anche da amministratore. Il menu OTGS Installer punta comunque a quell’URL.

Workaround: commentare **temporaneamente** `DISALLOW_FILE_MODS` (e `DISALLOW_FILE_EDIT`) in `wp-config.php` solo per aprire Commercial e registrare la chiave, poi ri-lock. **Non** dare WRITE a `www-data` su `wp-content/upgrade/`. Gli update restano via WP-CLI da root.

#### Ordine di aggiornamento (obbligatorio)

1. `wpml-string-translation` (String Translation)
2. `sitepress-multilingual-cms` (WPML Multilingual CMS)
3. Add-on nello stesso lotto: `acfml`, `wp-seo-multilingual`, e dove presenti Media / Woo multilingual / CF7 multilingual

Non lasciare CMS nuovo con String vecchio (o viceversa) tra una sessione e l’altra.

#### Dopo gli update

- `chown -R root:www-data` sulle cartelle plugin WPML
- `DISALLOW_FILE_MODS` + `DISALLOW_FILE_EDIT` di nuovo `true`
- **Non** dare WRITE a `www-data` su `wp-content/upgrade/`
- Smoke: homepage, URL seconda lingua, form, login

### Core 6.8.8

Security release 2026-08-12 (tra cui RCE Author+ via upload se Imagick+Ghostscript). Su questo server Imagick PHP non è caricato, ma 6.8.1/6.8.2 restano indietro sulle altre fix della linea 6.8. Non usare il pacchetto “partial” se si fa rsync: preferire tarball completo ufficiale `wordpress-6.8.8`, stesso metodo della bonifica (`rsync --delete` solo `wp-admin`/`wp-includes` + PHP root; mai `wp-config` / `wp-content` dal tarball).

### PHP

8.1.2 è EOL. Un upgrade PHP è **Fase 3**, non nella stessa finestra di core/plugin. Non è un prerequisito di 6.8.8.

---

## Lezioni dal pilota sentieri (2026-09-10)

Da riusare su parcopan / trekking / maremma. Stack sentieri era il più semplice (niente Woo, niente UAVC, niente LiteSpeed).

### Cosa ha funzionato

| Passo | Esito | Nota operativa |
|-------|-------|----------------|
| `wp core update --version=6.8.8` | OK | Con `DISALLOW_FILE_MODS=false` basta WP-CLI; scarica lo zip **it_IT**. Fallback rsync **non** servito. |
| `wp core update-db` | OK | Messaggio “already at latest db version 60421” — normale su patch 6.8.x. |
| Lotto A (6 plugin) | OK | Un `plugin update` alla volta. Smoke: homepage + `/contatti/` (CF7). |
| ACF 6.4.2 → 6.8.9 | OK | GeoHub + CPT `poi` ancora attivi; pagina POI 200. |
| Wordfence 8.2.1 → 9.0.1 | OK | **Non** ha rimosso `wordfence-waf.php` né le righe `auto_prepend_file` in `.htaccess`. Comunque fare copia di sicurezza di entrambi **prima** dell’update (fatto: `…-htaccess-pre-wf9-…bak`, `…-wordfence-waf-pre-wf9-…bak` in `/root/backups/`). |

### Trappole / dettagli pratici

1. **`mysqldump` e privilege PROCESS**  
   Compare spesso: `Access denied … PROCESS privilege(s) … tablespaces`. Il dump **viene creato lo stesso** se il file non è vuoto (`test -s`). Usare `--defaults-extra-file` temp mode `600`, credenziali da `wp-config`, output **solo** in `/root/backups/` (mai in webroot). Opzionale: `--no-tablespaces` per togliere il warning.

2. **Maintenance e WP-CLI**  
   Ogni `wp plugin update` attiva e **disattiva** da solo la maintenance. Non contare su `.maintenance` lasciato acceso per tutta la sessione. Alla fine: `wp maintenance-mode deactivate` (o rimuovere `.maintenance`) e verificare che non resti attivo.

3. **Owner dopo WP-CLI**  
   Dopo core/plugin: `chown -R root:www-data` su `wp-admin`, `wp-includes`, PHP di root e cartelle plugin aggiornate. Ripristinare `chmod 750` + `chown root:www-data` su `wp-content/upgrade`.

   **Really Simple SSL / LiteSpeed riscrivono `.htaccess`:** dopo l’update verificare subito `ls -la .htaccess`. Su parcopan RSS ha lasciato `.htaccess` come `root:root` `640` → Apache: *Server unable to read htaccess file* → **HTTP 403** su tutto il sito. Fix tipico: `chown root:www-data` + `chmod 640`. Su **trekking** (2026-09-10) owner era già `root:www-data`, ma `chmod 640` ha dato **403** e `644` ha ripristinato il 200 — tenere `root:www-data` **644** su questo vhost se 640 fallisce. Inoltre l’update RSS 9.8.1 ha **rimosso** il blocco `#Begin Really Simple Security` (rewrite HTTPS); resta `$_SERVER["HTTPS"]="on"` in `wp-config.php`. WAF Wordfence `auto_prepend` è rimasto. Rifare il check dopo ogni plugin che tocca `.htaccess`.

4. **Unlock / ri-lock**  
   Solo `DISALLOW_FILE_MODS` → `false` durante gli update; lasciare `DISALLOW_FILE_EDIT` a `true`. A fine sessione **obbligatorio** tornare a `true` e verificare con WP-CLI `eval`.

5. **IOC `ushort.company` residui**  
   Grep di baseline può trovare payload ancora in:
   - `wp-content/cache/index.html` → **svuotare** (fatto su sentieri)
   - path tipo `.tmb/index.html`, `images/**/index.php` (parcopan) → stub/empty
   - `**/.git/index.html` (plugin/theme con repo git) → non sono serviti come codice WP; annotare, non stubbare file git a caso  
   Escludere dump SQL e, in lettura, distinguere path `.git` vs codice attivo.

6. **Verifica smoke minima**  
   Homepage, `/wp-login.php` (form `#loginform`), una pagina form, una URL lingua WPML (`/en/`), una pagina CPT/mappa se presente. Su parcopan: **carrello** + **checkout** (non `/acquisti-online/` / `/negozio-online/` — sono `Redirect gone` 410 di proposito). Tutte HTTP 200, zero `Fatal` / `ushort.company` nel body.

7. **LiteSpeed**  
   Dopo update: purge (`wp litespeed-purge all` può dare 400 se non c’è API key; fallback `do_action('litespeed_purge_all')`). Su Apache+mod_php/PHP-FPM i blocchi `CacheLookup` / `CacheKeyModify` in `.htaccess` sono no-op; restano utili le regole `mod_rewrite` che bloccano `litespeed/debug/*.log` e `.litespeed_conf.dat`.

   **Dopo LiteSpeed 7.9+** (visto su parcopan) la dashboard può mostrare due avvisi se il lock write è attivo:

   1. *Please add/replace … codes into …/.htaccess* — il blocco `# BEGIN LSCACHE` va aggiornato **a mano** (o via root): protezione log/conf in `<IfModule mod_rewrite.c>`, CacheLookup/ASYNC/DROPQS in `<IfModule LiteSpeed>`. **Non** dare WRITE a `www-data` sul `.htaccess` di root. Dopo ogni edit: `chown root:www-data` + `chmod 640`.
   2. *could not create wp-content/litespeed/.htaccess* — eccezione permessi sulla **sola** cartella dati: `chown -R root:www-data`, dir `770`, file `.htaccess` `660` (template `LSCACHE_STATIC_PROTECT_V2`), `robots.txt` con `Disallow: /`. Non aprire WRITE su `plugins/` o `upgrade/`.

   Backup utile: `/root/backups/parcopan-htaccess-pre-lscache-fix-20260910.bak`.

### Backup del pilota (rollback)

| File | Path |
|------|------|
| DB | `/root/backups/sentierodeiducati-db-backup-20260910-124148.sql` |
| File (tar.gz) | `/root/backups/sentierodeiducati-files-backup-20260910-124148.tar.gz` |
| `.htaccess` pre-WF9 | `/root/backups/sentierodeiducati-htaccess-pre-wf9-20260910.bak` |
| `wordfence-waf.php` pre-WF9 | `/root/backups/sentierodeiducati-wordfence-waf-pre-wf9-20260910.bak` |

### Cosa resta fuori su sentieri

- Yoast 25.3 (FERMI in WP-CLI)
- Impreza / `us-core` / WPBakery / `wp-geohub` (congelati)

WPML su sentieri: **completato 2026-09-10** (vedi registro).  
WPML su parcopan: **completato 2026-09-10** (String → CMS → CF7 multilingual; vedi registro).  
WPML su trekking: **completato 2026-09-10** (String → CMS → SEO-ML; vedi registro).  
WPML su maremma: **completato 2026-09-14** (String → CMS → Media; vedi registro).

### Implicazioni per i siti successivi

- Fase 1 sui **quattro** vhost `/var/www/html` + EUMA volume: **completa** al 2026-09-14.
- Su siti con Really Simple SSL, **sempre** ricontrollare owner/mode di `.htaccess` subito dopo l’update RSS (parcopan: `root:root`→403; trekking: `640`→403, ok con `644`; maremma: stesso pattern `root:root` `640`→403, fix `644` + ripristino blocco HTTPS + `$_SERVER['HTTPS']='on'`).
- Events Calendar Pro richiede licenza valida: se l’update Pro fallisce, **non** lasciare TEC free avanti da solo — rollback del free (fatto su maremma).
- WPML: OTGS Installer + chiave; update via WP-CLI (String → CMS → Media/add-on).

WPML su maremma: **completato 2026-09-14** (vedi registro).

---

## Fase 2 / 3 (non ora)

**Fase 2** — sbloccabile solo con licenza Envato **valida per sito** (o altra fonte legittima del pacchetto Impreza):

1. Impreza + `us-core` stessa minor, poi WPBakery abbinato.
2. UAVC con re-patch admin se serve.
3. Solo dopo, valutare WP 6.9 → 7.0/7.1 su clone/staging.

**Fase 3:** PHP 8.2 o 8.3, giorno diverso da core 7.x.

Senza nuova licenza Impreza, Fase 2 e WP 7.x restano **chiuse**.

---

## Artefatti correlati

| Path | Ruolo |
|------|--------|
| `/root/docs/WORDPRESS-UPLOADS-SECURITY.md` | Bonifica malware, lock write, cron IOC |
| `/root/docs/WORDPRESS-CORE-PLUGIN-UPDATES.md` | Questo file |
| `/root/docs/WORDPRESS-SENTIERI-HANDOFF.md` | Dettaglio sentierodeiducati.it |
| `/root/docs/WORDPRESS-PARCOPAN-HANDOFF.md` | Dettaglio parcopan.org |
| `/root/docs/WORDPRESS-TREKKING-HANDOFF.md` | Dettaglio trekking.parcoforestecasentinesi.it |
| `/root/docs/WORDPRESS-MAREMMA-HANDOFF.md` | Dettaglio parco-maremma.it |
| `/root/docs/WORDPRESS-EUMA-HANDOFF.md` | Dettaglio EUMA (path volume, backup, smoke) |
| `/root/docs/WORDPRESS-OUTCROPEDIA-HANDOFF.md` | Dettaglio outcropedia (path volume, backup, smoke) |
| `/root/docs/WORDPRESS-SELFGUIDED-HANDOFF.md` | Dettaglio selfguided (path volume, backup, smoke) |
| `/root/docs/WORDPRESS-ACQUASORGENTE-HANDOFF.md` | Dettaglio acquasorgente (path volume, backup, smoke) |
| `/root/.cursor/plans/` | Plan Cursor della remediation |
| `/root/backups/` | Dump SQL + quarantena uploads |
| `/root/wp_uploads_ioc_clean.sh` | Pulizia periodica PHP in uploads |
| `/var/log/wp-uploads-ioc-clean.log` | Log cron |

---

## Registro interventi

Aggiungere una riga **in cima** a ogni sessione. Se un plugin della tabella cambia versione, aggiornare anche l’inventario sopra.

| Data | Sito | Operatore | Azioni | Esito | Note / rollback |
|------|------|-----------|--------|-------|-----------------|
| 2026-09-15 | sentieri + parcopan + trekking + maremma | agent | Ricaduta index malware (`ushort.company` / falsa maintenance): core ufficiale **6.8.8** (maremma **6.8.2**); stub `index.php`/`index.html` in wp-content; restore bootstrap `us-core/templates`, `wp-geohub`, `wm-package`, UAVC `bsf-core`, `cc-child-pages` (+ `define CC_CHILD_PAGES_VERSION`); cleanup `.tmb`/`images`/theme `home.html`/WPML queue | **OK** | Nessun rollback plugin; cron uploads **non** toccato; `ushort.company` assente (esclusi dump/.git); smoke home/login/admin 200 su tutti e 4; `wp-geohub`/`wm-package`/`cc-child-pages`/`UAVC` active |
| 2026-09-14 | parco-maremma.it | agent | Tentativo update TEC Pro 7.6.1→7.8.2 (licenza rinnovata lato utente); free non toccato | **KO** | `Check your license details first`; PUE invalid/expired su dominio prod; zip 7.6.0.1 (downgrade) → `/root/backups/events-calendar-pro-7.6.0.1-from-webroot-20260914-131818.zip`; backup `maremma-*-tec-20260914-131818.*`; ri-lock; smoke home/eventi/en/login/admin 200; handoff maremma aggiornato |
| 2026-09-14 | european-mountaineers.eu | agent | Allineamento docs: iubenda **attivo e configurato** (handoff + inventario) | **OK** | Rimosse note “config da fare / non configurato” |
| 2026-09-14 | — | agent | Centralizzazione docs: mv runbook+handoff → `/root/docs`; creati handoff sentieri/parcopan/trekking/maremma | **OK** | Path canonici `/root/docs/WORDPRESS-*.md`; nessun stub in DocumentRoot/volume |
| 2026-09-14 | acquasorgente.cai.it | agent | Hardening completo: backup; lock FS; core 6.8.1→**6.8.8**; lotto A (ACF **6.8.10**, smtp, crontrol); AI1WM off; WPML String→CMS→acfml; OTGS **3.1.20**; cron volume + allowlist `sucuri/*`; ri-lock `DISALLOW_*` | **OK** | Dump/tar `/root/backups/acquasorgente-*-20260914-113900.*` + WPML `*-114430.*`; handoff [`WORDPRESS-ACQUASORGENTE-HANDOFF.md`](/root/docs/WORDPRESS-ACQUASORGENTE-HANDOFF.md); smoke home/en/faq/eventi/il-progetto/login 200; 7.1 rimandato |
| 2026-09-14 | selfguided-toscana.it | agent | WPML: String **3.5.3→3.5.4**, CMS **4.9.5→4.9.7**; acfml/seo-ml/wcml già a target; ri-lock `DISALLOW_FILE_MODS=true`; smoke | **OK** | Dump/tar WPML `/root/backups/selfguided-*-wpml-20260914-111350.*`; core **7.1** e Woo **11.1.0** invariati; chiave OTGS registrata; smoke home/en/login/shop/cart/checkout 200/302 |
| 2026-09-14 | selfguided-toscana.it | agent | Hardening FS; wp-config `EDIT=true` `MODS=false`; lotto A (accessibility, head-footer-code, Wordfence **9.0.1**); OTGS **3.1.10→3.1.20** (rsync sentieri); cron volume; smoke | **OK** | Dump/tar `/root/backups/selfguided-*-20260914-105708.*`; core **7.1** invariato; Woo/WPML non toccati; handoff [`WORDPRESS-SELFGUIDED-HANDOFF.md`](/root/docs/WORDPRESS-SELFGUIDED-HANDOFF.md); chiave OTGS da registrare |
| 2026-09-14 | outcropedia.org | agent | OTGS **3.1.3→3.1.20** (rsync sentieri; WP-CLI no update); WPML stack già a target; chiave sito registrata; ri-lock `DISALLOW_*` | **OK** | Dump/tar `/root/backups/outcropedia-*-wpml2-20260914-103857.*`; smoke home/it/map/about/login 200 |
| 2026-09-14 | outcropedia.org | agent | core **6.8.8**; lotto A; Wordfence **9.0.1**; WPML String→CMS→ACFML→SEO-ML; otgs 3.1.3 (no key); AI1WM off; lock FS; cron volume; ri-lock `DISALLOW_*` | **OK** | Dump/tar `/root/backups/outcropedia-*-20260914-095002.*` + WPML `*-101623.*`; handoff [`WORDPRESS-OUTCROPEDIA-HANDOFF.md`](/root/docs/WORDPRESS-OUTCROPEDIA-HANDOFF.md); smoke home/login/map/about/it 200 |
| 2026-09-14 | parco-maremma.it | agent | core 6.8.2→**6.8.8**; lotto A (asset-clean-up, CF7, mailchimp, PYS, RSS 9.8.1, accessibility, smtp, duplicate-post, Spectra, carousel); CAUTELA (cc-child-pages 2.1.2, facetwp 4.5, flow-flow 5.0.5); Wordfence 8.0.5→**9.0.1**; WPML String→CMS→Media; OTGS 3.1.20; ri-lock | **OK** | Dump `/root/backups/maremma-*-20260914-091819.*` + WPML `*-092912.*`; RSS `root:root`→403, fix 644 + HTTPS rewrite ripristinato + HTTPS in wp-config; TEC free aggiornato poi **rollback a 6.14.0** (Pro 7.6.1 licenza KO); UAVC/`js_composer`/`us-core`/`wm-embedmaps` non toccati; handoff [`WORDPRESS-MAREMMA-HANDOFF.md`](/root/docs/WORDPRESS-MAREMMA-HANDOFF.md); smoke home/en/login/admin/eventi/contatti 200 |
| 2026-09-14 | european-mountaineers.eu | agent | `blog_public` 0→**1** (indicizzazione attiva) | **OK** | Meta robots `index, follow`; home/contacts 200; X-Robots-Tag noindex sulla sitemap XML = default Yoast |
| 2026-09-14 | european-mountaineers.eu | agent | Install + activate `wordpress-seo` (Yoast) **25.5**; ri-lock `DISALLOW_FILE_MODS` | **OK** | Pin 25.5 (compat WP 6.8.8); non 28.4 (requires 6.9); smoke home/contacts 200 |
| 2026-09-14 | european-mountaineers.eu | agent | Install + activate `iubenda-cookie-law-solution` **3.13.5**; ri-lock `DISALLOW_FILE_MODS` | **OK** | attivo e configurato; smoke home/contacts 200 |
| 2026-09-14 | european-mountaineers.eu | agent | Igiene wpress/zip/nested/`false`; WP_DEBUG boolean; AI1WM off; lock FS; core 6.8.3→**6.8.8**; lotto A + Events + WF **9.0.1**; cron volume | **OK** | `/root/backups/euma-*-20260914-073024.*`; handoff [`WORDPRESS-EUMA-HANDOFF.md`](/root/docs/WORDPRESS-EUMA-HANDOFF.md); smoke home/login/contacts/events/members/map 200 |
| 2026-09-10 | trekking.parcoforestecasentinesi.it | agent | WPML: String 3.3.3→**3.5.4**, CMS 4.7.6→**4.9.7**, SEO-ML 2.1.1→**2.2.5**; OTGS Installer 3.1.20 + chiave sito; ri-lock `DISALLOW_FILE_MODS`+`EDIT` | **OK** | Dump `/root/backups/trekking-db-backup-wpml-20260910-145438.sql` + tar WPML; handoff [`WORDPRESS-TREKKING-HANDOFF.md`](/root/docs/WORDPRESS-TREKKING-HANDOFF.md); smoke home/en/login/admin/track 200; UAVC/`wm-package` ok |
| 2026-09-10 | trekking.parcoforestecasentinesi.it | agent | core 6.8.1→**6.8.8**; lotto A (disable-comments, carousel, iubenda, RSS 9.8.1, smtp, Easy Updates Manager); Redirection 5.5.2→**5.10.0** (export 20 regole); ACF 6.4.2→**6.8.9**; Wordfence 8.0.5→**9.0.1**; ri-lock | **OK** | Dump `/root/backups/trekking-db-backup-20260910-143519.sql` + tar; RSS ha rimosso blocco HTTPS rewrite (resta wp-config HTTPS); `.htaccess` `644` (640→403 su questo vhost); WAF auto_prepend ok; smoke home/en/login/admin/track/poi + redirect mtb-1 301; UAVC/`wm-package` non toccati; WPML fuori scope |
| 2026-09-10 | parcopan.org | agent | WPML: String 3.3.3→**3.5.4**, CMS 4.7.6→**4.9.7**, CF7-ML 1.3.2→**1.3.3**; OTGS Installer 3.1.20 + chiave sito; ri-lock `DISALLOW_FILE_MODS`+`EDIT` | **OK** | Dump `/root/backups/parcopan-db-backup-wpml-20260910-142422.sql` + tar WPML; handoff [`WORDPRESS-PARCOPAN-HANDOFF.md`](/root/docs/WORDPRESS-PARCOPAN-HANDOFF.md); Commercial bloccata da `DISALLOW_FILE_MODS` (atteso: no `install_plugins`); smoke home/en/contatti/login/carrello/checkout 200 |
| 2026-09-10 | parcopan.org | agent | Fix avvisi LiteSpeed 7.9.1: blocco LSCACHE root aggiornato (mod_rewrite + LiteSpeed); `wp-content/litespeed/` → 770 + `.htaccess` STATIC_PROTECT_V2 660 | **OK** | Backup `/root/backups/parcopan-htaccess-pre-lscache-fix-20260910.bak`; root `.htaccess` resta non scrivibile da PHP; smoke home/login/checkout 200; debug log path 403 |
| 2026-09-10 | parcopan.org | agent | core 6.8.1→**6.8.8**; lotto A (CF7, add-to-any, disable-comments, iubenda, smtp, accessibility, sitemap, RSS 9.8.1); LiteSpeed 7.2→**7.9.1**; Wordfence 8.0.5→**9.0.1**; stub IOC `.tmb`/`images`; ri-lock | **OK** | Dump `/root/backups/parcopan-db-backup-20260910-134820.sql` + tar; **RSS aveva lasciato `.htaccess` root:root → 403**, fix `chown root:www-data`; shop `/acquisti-online/` è 410 intenzionale; smoke home/en/contatti/carrello/checkout/login 200; WPML non toccato (manca OTGS Installer) |
| 2026-09-10 | sentierodeiducati.it | agent | WPML: String 3.3.3→**3.5.4**, CMS 4.7.6→**4.9.7**, ACFML 2.1.5→**2.2.4**, SEO 2.1.1→**2.2.5**; OTGS Installer 3.1.20 già attivo + chiave sito; ri-lock `DISALLOW_FILE_MODS`+`EDIT` | **OK** | Dump `/root/backups/sentierodeiducati-db-backup-wpml-20260910-132947.sql` + tar WPML; handoff [`WORDPRESS-SENTIERI-HANDOFF.md`](/root/docs/WORDPRESS-SENTIERI-HANDOFF.md); dashboard falliva su `upgrade/` locked (atteso); WP-CLI da root; smoke home/en/contatti/login 200 |
| 2026-09-10 | sentierodeiducati.it | agent | core 6.8.1→**6.8.8**; lotto A (CF7 6.1.7, add-to-any 1.8.18, disable-comments 2.9.0, cfdb7 1.4.0, wp-mail-smtp 4.9.0, Spectra 2.20.3); ACF 6.4.2→**6.8.9**; Wordfence 8.2.1→**9.0.1**; ri-lock `DISALLOW_FILE_MODS`; svuotato `wp-content/cache/index.html` con IOC ushort | **OK** | Dump `/root/backups/sentierodeiducati-db-backup-20260910-124148.sql` + tar files; WAF auto_prepend intatto; homepage/login/contatti/poi/en 200; WPML e Impreza non toccati. Residui ushort ancora possibili sotto `.git/` |
| 2026-09-10 | — | — | Inventario WP-CLI + piano Fase 1 (core 6.8.8, plugin OK/CAUTELA, Impreza congelato) | Piano scritto | Licenza Impreza condivisa tra i siti: tema/`us-core`/WPBakery/UAVC fuori scope |

Template riga:

```
| AAAA-MM-GG | vhost | nome | es. core 6.8.1→6.8.8; CF7 6.0.6→6.1.7 | OK / KO | dump in /root/backups/… ; eventuale rollback |
```
