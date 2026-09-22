# Pinned: a moving tag (wordpress:latest, :apache) would rebase every deploy of
# this template at once. Bump deliberately. This fixes PHP, Apache and the
# WordPress version of the first install; after that WordPress updates itself
# from the dashboard as usual.
FROM wordpress:7.1.2-php8.3-apache

# phpredis for the object cache, and the MariaDB client that `wp db export` runs.
RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends $PHPIZE_DEPS; \
	pecl install redis-6.3.0; \
	docker-php-ext-enable redis; \
	apt-mark auto '.*' > /dev/null; \
	apt-mark manual $savedAptMark > /dev/null; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	apt-get install -y --no-install-recommends mariadb-client; \
	rm -rf /var/lib/apt/lists/* /tmp/pear

# WP-CLI, checksum-verified, and the Redis Object Cache plugin. The plugin goes
# into the image's WordPress source, so the first boot copies it with the rest.
RUN set -eux; \
	curl -fsSL -o /usr/local/lib/wp-cli.phar https://github.com/wp-cli/wp-cli/releases/download/v2.12.0/wp-cli-2.12.0.phar; \
	echo 'be928f6b8ca1e8dfb9d2f4b75a13aa4aee0896f8a9a0a1c45cd5d2c98605e6172e6d014dda2e27f88c98befc16c040cbb2bd1bfa121510ea5cdf5f6a30fe8832  /usr/local/lib/wp-cli.phar' | sha512sum -c -; \
	curl -fsSL -o /tmp/redis-cache.zip https://downloads.wordpress.org/plugin/redis-cache.3.0.0.zip; \
	echo '7a03342d3defbe94cac8d0470b42dc1a1c34331b19c47205df20ceccd3c8f54a  /tmp/redis-cache.zip' | sha256sum -c -; \
	php -r '$z = new ZipArchive; exit($z->open("/tmp/redis-cache.zip") === true && $z->extractTo("/usr/src/wordpress/wp-content/plugins") ? 0 : 1);'; \
	rm /tmp/redis-cache.zip; \
	printf 'path: /var/www/html\n' > /etc/wp-cli.yml
ENV WP_CLI_CONFIG_PATH=/etc/wp-cli.yml WP_CLI_CACHE_DIR=/tmp/wp-cli-cache

# The object cache plugin reads its settings from constants only; the first boot
# writes wp-config.php from this template, so add the block that defines them from
# the WP_REDIS_* variables.
COPY wp-config-redis.php /tmp/
RUN set -eux; \
	f=/usr/src/wordpress/wp-config-docker.php; \
	awk 'FNR == NR { block = block $0 "\n"; next } /That.s all, stop editing/ { printf "%s\n", block } { print }' /tmp/wp-config-redis.php "$f" > /tmp/wp-config.php; \
	mv /tmp/wp-config.php "$f"; \
	rm /tmp/wp-config-redis.php; \
	grep -q WP_REDIS_PASSWORD "$f"; \
	php -l "$f"

# The stock limits reject most themes, plugins and media (2 MB uploads).
RUN printf '%s\n' 'upload_max_filesize = 128M' 'post_max_size = 128M' 'memory_limit = 256M' 'max_execution_time = 300' 'expose_php = Off' \
	> /usr/local/etc/php/conf.d/railway.ini

# Apache on Railway's $PORT, IPv6 and IPv4 (the [::] socket takes both where it can,
# and Apache falls back to IPv4 alone on hosts without IPv6). Errors go to stdout:
# Railway paints all of stderr red, including Apache's startup notices.
ENV PORT=8080
RUN set -eux; \
	printf 'Listen [::]:${PORT}\nListen 0.0.0.0:${PORT}\n' > /etc/apache2/ports.conf; \
	sed -i 's/<VirtualHost \*:80>/<VirtualHost *:${PORT}>/' /etc/apache2/sites-available/000-default.conf; \
	grep -q 'VirtualHost \*:${PORT}' /etc/apache2/sites-available/000-default.conf; \
	ln -sfT /dev/stdout /var/log/apache2/error.log; \
	sed -i 's/^ServerTokens OS/ServerTokens Prod/; s/^ServerSignature On/ServerSignature Off/' /etc/apache2/conf-available/security.conf; \
	mkdir -p /usr/local/share/railway; \
	echo ok > /usr/local/share/railway/healthz
COPY railway.conf /etc/apache2/conf-enabled/railway.conf

# The visitor's address: Railway's edge connects from 100.64.0.0/10 and sets X-Real-IP
# to the client (overwriting what the client sent). The image reads X-Forwarded-For
# from private ranges only; on Railway that logged the edge, and X-Forwarded-For also
# ends in an edge hop, so WordPress (comments, login limits) saw the proxy for everyone.
RUN printf '%s\n' 'RemoteIPHeader X-Real-IP' 'RemoteIPInternalProxy 100.64.0.0/10' > /etc/apache2/conf-available/remoteip.conf

COPY --chmod=0755 wp wordpress-backup wordpress-restore /usr/local/bin/
COPY --chmod=0755 railway-entrypoint.sh /railway-entrypoint.sh
ENTRYPOINT ["/railway-entrypoint.sh"]
# The PHP image stops Apache with SIGWINCH; the entrypoint handles SIGTERM, which is
# also what Railway sends.
STOPSIGNAL SIGTERM
