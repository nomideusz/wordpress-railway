#!/bin/bash
# Railway entrypoint for WordPress: installed on first boot with a generated admin
# password (no public installer, not even for a moment), Apache sized from the
# plan's memory, Redis object cache on, nightly backup to the Railway bucket.
set -euo pipefail

# Railway flattens the image layers, which brings back the mpm_event links the PHP
# image deleted, and Apache then refuses to start: "AH00534: More than one MPM
# loaded". mod_php needs prefork only.
rm -f /etc/apache2/mods-enabled/mpm_event.* /etc/apache2/mods-enabled/mpm_worker.*

# Prefork runs one process per concurrent request: ~10 MB at rest plus the page's
# PHP memory (~35 MB for a stock page, more with heavy plugins). Budget 64 MB a
# worker after 256 MB for Apache, OPcache and the backup job, sized from the plan's
# memory limit (Railway sets the cgroup limit to it), never from the host's 48 CPUs.
mem=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)
[ "$mem" = max ] && mem=$((8 << 30))
workers=$(( (mem / 1048576 - 256) / 64 ))
workers=${WP_APACHE_WORKERS:-$(( workers < 4 ? 4 : workers > 64 ? 64 : workers ))}
printf '<IfModule mpm_prefork_module>\n\tMaxRequestWorkers %s\n</IfModule>\n' "$workers" \
  > /etc/apache2/conf-enabled/zz-workers.conf

# Copy WordPress onto the volume and write wp-config.php, with its salts randomized
# once and kept on the volume, the way the official image does before Apache starts.
docker-ensure-installed.sh true 2>&1  # its notices are not errors; keep them out of the red stderr

# On a fresh deploy MariaDB may still be initializing.
for i in $(seq 90); do
  php -r 'mysqli_report(MYSQLI_REPORT_OFF);
          exit(@mysqli_connect(getenv("WORDPRESS_DB_HOST"), getenv("WORDPRESS_DB_USER"),
                               getenv("WORDPRESS_DB_PASSWORD"), getenv("WORDPRESS_DB_NAME")) ? 0 : 1);' && break
  [ "$i" = 90 ] && { echo "railway: database not reachable after 3 minutes"; exit 1; }
  sleep 2
done

if ! wp core is-installed 2>/dev/null; then
  echo "railway: first boot, installing WordPress"
  wp core install --url="https://${RAILWAY_PUBLIC_DOMAIN:?no public domain; generate one in the service settings}" \
    --title="My WordPress Site" --admin_user=admin --admin_password="${WP_ADMIN_PASSWORD:?WP_ADMIN_PASSWORD is not set}" \
    --admin_email="${WP_ADMIN_EMAIL:-admin@example.com}" --skip-email
  wp rewrite structure '/%postname%/'  # the image's .htaccess already routes pretty URLs
fi

# Redis object cache: turned on while WP_REDIS_HOST is set. Enabling checks the
# connection, so if Redis isn't up yet the next start tries again.
if [ -n "${WP_REDIS_HOST:-}" ] && [ ! -e /var/www/html/wp-content/object-cache.php ]; then
  { wp plugin activate redis-cache && wp redis enable 2>/dev/null; } ||
    echo "railway: Redis is unreachable; the object cache stays off until the next start"
fi

trap 'kill $(jobs -p) 2>/dev/null; wait; exit 0' TERM INT
apache2-foreground &
apache_pid=$!

if [ -n "${S3_BUCKET:-}" ]; then
  # 03:00 UTC daily; a failed backup is logged, it never takes the site down.
  while sleep $(( (97200 - $(date +%s) % 86400) % 86400 )); do wordpress-backup || true; done &
fi

# Apache exiting means the site is down: exit so Railway restarts the service.
wait -n "$apache_pid"
exit 1
