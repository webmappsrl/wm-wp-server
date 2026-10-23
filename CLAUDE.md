# wm-wp-server

Script e strumenti per il server WordPress di produzione Webmapp (alias ssh `php8`, Ubuntu 22.04,
Apache prefork + mod_php) che ospita i siti WordPress dei clienti.

Questo repository è **pubblico**. La documentazione operativa del server (stato, incidenti,
registro interventi, runbook, piani e note dei lavori, liste di eccezioni del drift-check) sta nel
repository **privato** `webmappsrl/wm-wp-server-ops`.

## Prima di tutto

- **Nessun dato del server in questo repo.** IP, percorsi di backup e quarantene, storia degli
  incidenti, versioni dei componenti vulnerabili e liste di eccezioni vanno solo nel repo privato.
  La storia di questo repo è stata ripulita il 23/10/2026 (oc:8834): non reintrodurli.
- **Gli script lavorano sulla produzione.** Quelli in `scripts/` parlano col server via `ssh php8`.
  Leggi uno script prima di lanciarlo; quelli che scrivono sul server (aggiornamenti di pacchetti,
  deploy del drift-check, quarantene) solo con l'ok esplicito del dev.
- **I backup contengono dati personali.** `scripts/php-migration/backup-sites.sh` porta sul Mac
  i dump dei DB, con clienti e ordini WooCommerce: restano sul disco esterno, mai in un repo.
- **Non dichiarare concluso un aggiornamento dei pacchetti PHP sul server senza aver verificato
  che Apache sia ripartito**: il dettaglio è nel runbook di Apache del repo privato.

## Regole del repo

- Documentazione in italiano.
- I test sono script bash in `tests/`, stile `assert_eq`, exit 1 se fallisce.
- Overview, piano e note di ogni lavoro vanno nel repo privato, in `docs/features/<ID>-<slug>/`.

## Comandi

| Cosa | Comando |
|---|---|
| Test (uno) | `bash tests/<file>.sh` — `tests/test-php-compat-env.sh` richiede Docker |
| Smoke test di un sito in produzione | `scripts/php-migration/smoke-test.sh <sito>` |
| Backup senza media | `scripts/php-migration/backup-sites.sh <cartella> [sito…]` |
| Test di compatibilità PHP in Docker | `scripts/php-migration/run-compat-tests.sh <backup> <risultati> <versione>…` — dettagli in [docker/php-compat/README.md](docker/php-compat/README.md) |

## Trappole

- Script di migrazione PHP e ambiente Docker di test: [.claude/rules/php-migration.md](.claude/rules/php-migration.md)
