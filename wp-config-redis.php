// Redis object cache: the connection comes from the WP_REDIS_* variables. While
// Redis is unreachable (a restart, a redeploy) pages are served uncached instead of
// the plugin's "Error establishing a Redis connection" screen.
foreach (['WP_REDIS_HOST', 'WP_REDIS_PORT', 'WP_REDIS_PASSWORD'] as $redisSetting) {
	if (!defined($redisSetting) && ($redisValue = getenv_docker($redisSetting, '')) !== '') {
		define($redisSetting, $redisValue);
	}
}
defined('WP_REDIS_GRACEFUL') || define('WP_REDIS_GRACEFUL', true);
