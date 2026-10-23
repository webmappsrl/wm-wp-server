<?php
/**
 * Plugin Name: oc8834 — nessuna uscita dal container di test
 * Description: Blocca email e richieste HTTP uscenti nei test di compatibilità PHP (oc:8834).
 *              Seconda barriera oltre alla rete Docker senza internet. Non va mai in produzione.
 */

add_filter( 'pre_wp_mail', '__return_false', PHP_INT_MAX );

add_filter(
	'pre_http_request',
	static function () {
		return new WP_Error( 'oc8834_blocked', 'Richieste HTTP uscenti bloccate nel container di test' );
	},
	PHP_INT_MAX
);
