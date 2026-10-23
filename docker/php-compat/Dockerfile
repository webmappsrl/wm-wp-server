# Ambiente di test di compatibilità PHP per i siti del server WordPress — oc:8834
# Riproduce lo stack di produzione: Apache + mod_php (immagine ufficiale *-apache).
ARG PHP_VERSION=8.4.27
FROM php:${PHP_VERSION}-apache

RUN apt-get update && apt-get install -y --no-install-recommends \
        libbz2-dev libcurl4-openssl-dev libfreetype6-dev libgmp-dev libicu-dev libjpeg62-turbo-dev \
        libpng-dev libtidy-dev libwebp-dev libxml2-dev libxslt1-dev libzip-dev default-mysql-client \
        ssl-cert \
    && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
    && docker-php-ext-install -j"$(nproc)" bz2 exif gd gmp intl mysqli opcache pdo_mysql soap tidy xsl zip \
    && pecl install apcu xmlrpc-1.0.0RC3 \
    && docker-php-ext-enable apcu xmlrpc \
    && rm -rf /var/lib/apt/lists/* /tmp/pear

RUN curl -fsSL -o /usr/local/bin/wp https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x /usr/local/bin/wp

COPY php.ini /usr/local/etc/php/conf.d/99-oc8834.ini
COPY site.conf /etc/apache2/sites-available/site.conf
RUN a2enmod rewrite headers ssl expires \
    && a2dissite 000-default \
    && a2ensite site \
    && mkdir -p /var/log/php && chown www-data:www-data /var/log/php
