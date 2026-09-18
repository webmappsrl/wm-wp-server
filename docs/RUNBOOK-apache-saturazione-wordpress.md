# Runbook: siti WordPress irraggiungibili (Apache saturo)

**Host:** `wordpress-php8` (`49.13.127.241`)  
**Data incidente:** 2026-09-11  
**Sintomo utente:** browser «impossibile raggiungere il sito»  
**Esito:** ripristinato; i siti del monitor rispondono di nuovo HTTP 200

---

## Sintomi tipici

- I siti WordPress non caricano (timeout / unreachable).
- Il monitor periodico (`/root/curl_check_restart_apache.sh`, log `/var/log/curl-monitor.log`) può ancora mostrare **All URLs OK** se l’ultimo check è **prima** del blackout.
- `systemctl is-active apache2` e `mysql` risultano **active**.
- Anche `curl` verso `127.0.0.1:80` / `:443` va in **timeout** (`http_code=000`).
- In `/var/log/apache2/error.log` compare:
  ```
  AH00161: server reached MaxRequestWorkers setting
  ```
- Su porta 443 la coda di ascolto è piena (`ss -ltn` → `Recv-Q` alto su `*:443`).

---

## Causa root

Stack: **Apache MPM prefork + mod_php 8.1** (non php-fpm).

| Fattore | Dettaglio |
|--------|-----------|
| Cap worker | `MaxRequestWorkers 30` — con ~180–200 MB/child e ~7.6 GB RAM **non va alzato** (rischio OOM/swap) |
| Abuso / carico | IP `195.178.110.106` (AS48090 TECHOFF, Amsterdam) apre decine di connessioni su 80/443 e satura da solo il pool |
| Timeout lunghi | `Timeout 300` + `KeepAlive On` tenevano i child occupati troppo a lungo |

Un **solo restart di Apache** (anche via monitor) **non basta**: senza blocco IP i 30 worker si riempiono di nuovo in pochi secondi.

```
Client → Apache :443 (backlog pieno) → 30 child prefork → mod_php / WordPress
                ↑
         IP abusivo satura i worker → nuove richieste timeout
```

---

## Soluzione applicata (2026-09-11)

Ordine obbligatorio: **bloccare l’IP prima del restart**.

### 1. Blocco IP runtime + persistenza

Regola attiva:

```bash
iptables -I INPUT 1 -s 195.178.110.106 -j DROP
```

Persistenza al boot (senza abilitare UFW / senza policy DROP globale):

- Unit: `/etc/systemd/system/block-abuse-ips.service`
- Stato atteso: `enabled` + `active (exited)`
- Comando unit: reinserisce la regola se manca (`iptables -C` … oppure `-I`)

```bash
systemctl status block-abuse-ips.service
iptables -C INPUT -s 195.178.110.106 -j DROP && echo OK
```

**Non** abilitare `ufw` in questo contesto (rischio lock-out SSH).  
**Non** bloccare a casaccio crawler legittimi (es. Meta `57.141.*`, Bing `52.167.*`).

### 2. Tuning Apache (senza alzare i worker)

File `/etc/apache2/apache2.conf`:

- `Timeout 300` → **`Timeout 60`**
- `KeepAlive On` → **`KeepAlive Off`**

File `/etc/apache2/mods-available/mpm_prefork.conf` (abilitato via symlink in `mods-enabled`):

- `MaxRequestWorkers` lasciato a **30**
- Aggiunto **`ServerLimit 30`**

Poi sempre:

```bash
apache2ctl configtest   # deve dare Syntax OK
```

### 3. Restart pulito (gestione orfani)

Come nello script monitor:

```bash
systemctl stop apache2
sleep 3
# se restano processi:
pgrep -x apache2 && pkill -9 apache2 && sleep 2
systemctl start apache2
systemctl is-active apache2
ss -ltn '( sport = :80 or sport = :443 )'   # Recv-Q deve essere basso
```

### 4. Verifica post-fix

```bash
# Locale
curl -sI -o /dev/null -w "%{http_code}\n" --connect-timeout 5 --max-time 15 http://127.0.0.1/
curl -skI -o /dev/null -w "%{http_code}\n" --connect-timeout 5 --max-time 15 https://127.0.0.1/

# URL del monitor (attesi 200, non 000)
for u in \
  https://parco-maremma.it/ \
  https://parcopan.org/ \
  https://sentierodeiducati.it/ \
  https://selfguided-toscana.it/ \
  https://acquasorgente.cai.it/
do
  curl -skI -o /dev/null -w "%{http_code} $u\n" --connect-timeout 5 --max-time 15 "$u"
done

# Controlli extra
pgrep -c apache2                                    # sotto 31
ss -tn '( sport = :80 or sport = :443 )' | grep -c 195.178.110.106 || true   # 0
grep MaxRequestWorkers /var/log/apache2/error.log | tail -3   # nessuna riga NUOVA dopo il restart
free -h
```

Esito del ripristino: monitor URL **200**; worker sotto il cap; IP bloccato assente da `ss`; nessun nuovo `MaxRequestWorkers`.

---

## Checklist se si ripresenta

1. Snapshot: top IP su 80/443, `pgrep -c apache2`, `free -h`, coda `ss -ltn`, coda `error.log`.
2. Se un IP satura il pool → `iptables -I INPUT 1 -s <IP> -j DROP` e aggiornare `/etc/systemd/system/block-abuse-ips.service` (o equivalente) per la persistenza.
3. Verificare `Timeout` / `KeepAlive` / `ServerLimit` / `MaxRequestWorkers` come sopra.
4. `apache2ctl configtest` → restart pulito (stop → kill orfani se serve → start).
5. Curl locale + URL monitor.
6. Se un sito dà **500** (non timeout): **non** riavviare MySQL a caso — isolare quel vhost/log.

---

## Cosa NON fare

- Alzare `MaxRequestWorkers` oltre 30 con mod_php su questa macchina (OOM).
- `ufw enable` o policy `INPUT DROP` globale senza regole SSH esplicite.
- Migrare a php-fpm/mpm_event **durante** un blackout senza piano dedicato.
- `echo 3 > /proc/sys/vm/drop_caches` o restart MySQL se MySQL è già healthy.
- `kill -9` **prima** di `systemctl stop` (meglio stop, poi eventuale kill orfani).

---

## File e tool di riferimento

| Percorso | Ruolo |
|----------|--------|
| `/etc/apache2/apache2.conf` | `Timeout`, `KeepAlive` |
| `/etc/apache2/mods-available/mpm_prefork.conf` | `ServerLimit`, `MaxRequestWorkers` |
| `/etc/systemd/system/block-abuse-ips.service` | DROP persistente `195.178.110.106` |
| `/root/curl_check_restart_apache.sh` | Health-check ogni ~20 min + restart se tutti gli URL falliscono |
| `/var/log/curl-monitor.log` | Log del monitor |
| `/var/log/apache2/error.log` | `MaxRequestWorkers`, segfault, restart |

Vhost abilitati tipici sotto `/etc/apache2/sites-enabled/` (DocumentRoot in `/var/www/html/...`).

---

## Note su anomalie non legate a questa saturazione

Riscontrate in verifica ma **fuori scope** del ripristino saturazione:

- **`acquasorgente.webmapp.it`** — HTTP 500 (problema applicazione/vhost; non risolto con restart Apache).
- **`discover.ilbagnolo.it`** — DNS punta a `188.166.15.99` (altro host), non a questo server.

---

## Follow-up strutturale (consigliato, non applicato il 2026-09-11)

Con ~12 siti WordPress su prefork+mod_php, la soluzione di lungo periodo è **php-fpm + mpm_event**: più connessioni con meno RAM per richiesta. Il monitor attuale può restare così com’è dopo il blocco IP; da solo un restart non basta contro un flood.

---

*Documento scritto dopo l’intervento del 2026-09-11. Aggiornare questo file se si aggiungono IP in blocklist o si cambia architettura (php-fpm).*
