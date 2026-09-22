# Deploy and Host WordPress on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/wordpress-pro?utm_medium=integration&utm_source=button&utm_campaign=wordpress-pro)

[WordPress](https://wordpress.org/) is the open-source CMS behind over 40% of the web: blogs, company sites, portfolios and, with WooCommerce, online shops, with thousands of themes and plugins. This template runs the official WordPress image the way a managed WordPress host sets it up: MariaDB, a Redis object cache, nightly backups, and no open installer.

## About Hosting WordPress

The stack is four pieces: WordPress (Apache and PHP 8.3), a private MariaDB, a private Redis, and a Railway bucket for backups.

- **Installed before it goes public.** A fresh WordPress shows its setup page to whoever opens the URL first, and bots scan new domains for exactly that. This template installs WordPress on the first boot, before the site answers, with the login `admin` and a generated password, never `admin`/`admin`. MariaDB and Redis have generated passwords and no public proxy. The security keys and salts are random, written once and kept on the volume, so logins survive redeploys.
- **Redis object cache.** The Redis Object Cache plugin is installed and switched on, so the queries WordPress repeats on every page come from memory. If Redis restarts, pages are served without the cache for those seconds instead of an error screen.
- **Nightly backups.** Every night at 03:00 UTC the database and `wp-content` (themes, plugins, uploads) go to the bundled bucket, one archive per weekday, so the last 7 days are always there. Restoring is one command.
- **Limits for real sites.** 128 MB uploads (the stock image stops at 2 MB), 256 MB of PHP memory and 5-minute requests for imports and big plugin installs. Apache is sized to your plan's memory, pretty permalinks are on, and WP-CLI is built in.

## Common Use Cases

- A blog, portfolio or company site, with themes and plugins updated from the dashboard as usual
- A WooCommerce shop, where the object cache takes load off the database
- Client sites for freelancers and agencies, with backups from day one

## Dependencies for WordPress Hosting

- MariaDB 11.8 LTS (included, private network only)
- Redis 8 (included, private network only, cache only)
- A Railway bucket for backups (included)

### Deployment Dependencies

- [WordPress documentation](https://wordpress.org/documentation/)
- [WP-CLI commands](https://developer.wordpress.org/cli/commands/)
- [Template source on GitHub](https://github.com/nomideusz/wordpress-railway)

### Implementation Details

**Sign in** at `https://<your domain>/wp-admin` with the username `admin` and the `WP_ADMIN_PASSWORD` value from the WordPress service's Variables tab. Afterwards, change the password (Users → Profile) and the admin email (Settings → General). Both variables are read on the first boot only.

**Email.** WordPress sends password resets and notifications by email, and the container has no mail server. Railway allows outbound SMTP only on the Pro plan. On any plan, install a mail plugin that sends through an email provider's HTTPS API, such as FluentSMTP or WP Mail SMTP with Brevo, Mailgun, Postmark or SendGrid. On Pro, a plain SMTP login works too. Until you set one up, WordPress can't send email: give new users a password yourself (Users → Add New). If you lose the admin password, set a new one from a `railway ssh` session on the WordPress service: `wp user update admin --user_pass='new-password'`.

**Backups and restore.** Backups appear in the Backups bucket as `wordpress-Mon.tar.gz` … `wordpress-Sun.tar.gz`, each holding the database, `wp-content` and `wp-config.php`. For an extra backup before a risky change, run `wordpress-backup` in a `railway ssh` session on the WordPress service. It replaces today's file. To roll back, run `wordpress-restore Mon` (or any other weekday) there. It replaces the database and `wp-content` with that backup's.

**Memory.** About 150 MB for WordPress once it has served some traffic (40 MB right after a start), 150 MB for MariaDB and 20 MB for Redis. Apache runs one process per concurrent request and sizes the pool from the plan's memory: 4 processes on a 512 MB plan, up to 64. Set `WP_APACHE_WORKERS` on the WordPress service to choose the number yourself.

**Custom domain.** Add it in the WordPress service's Settings → Networking, then move the site over from `railway ssh`: `wp search-replace 'https://<old domain>' 'https://<new domain>' --all-tables && wp cache flush`. This updates the site address and the links inside your posts.

**Updates.** WordPress, themes and plugins live on the volume and update from the dashboard as usual. Redeploys never overwrite them. The image pins PHP 8.3 and Apache.

**More wp-config.php settings.** Put PHP in the `WORDPRESS_CONFIG_EXTRA` variable, for example `define('DISALLOW_FILE_EDIT', true);`, and redeploy.

## Why Deploy WordPress on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying WordPress on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
