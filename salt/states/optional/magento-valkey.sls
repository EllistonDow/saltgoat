# Magento Valkey 集成（Salt 原生）
#
# 目标：
# - 为指定 Magento 站点写入 Redis/Valkey 配置（缓存与会话）
# - 保持幂等：如配置已匹配则跳过
# - 仅在配置变更时触发缓存刷新及 Valkey 清理

{% set site_name = pillar.get('site_name') %}
{% set valkey_password = pillar.get('valkey_password', '') %}
{% set cache_db = pillar.get('cache_db') %}
{% set page_db = pillar.get('page_db') %}
{% set session_db = pillar.get('session_db') %}
{% set valkey_host = pillar.get('valkey_host', '127.0.0.1') %}
{% set valkey_port = pillar.get('valkey_port', 6379) %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set cache_prefix = pillar.get('cache_prefix', site_name ~ '_cache_' if site_name else None) %}
{% set session_prefix = pillar.get('session_prefix', site_name ~ '_session_' if site_name else None) %}
{% set redis_compress = pillar.get('compress_data', '1') %}
{% set redis_timeout = pillar.get('timeout', '2.5') %}
{% set redis_max_concurrency = pillar.get('max_concurrency', '6') %}
{% set redis_break_after_frontend = pillar.get('break_after_frontend', '5') %}
{% set redis_break_after_adminhtml = pillar.get('break_after_adminhtml', '30') %}
{% set redis_first_lifetime = pillar.get('first_lifetime', '600') %}
{% set redis_bot_first_lifetime = pillar.get('bot_first_lifetime', '60') %}
{% set redis_bot_lifetime = pillar.get('bot_lifetime', '7200') %}
{% set redis_disable_locking = pillar.get('disable_locking', '0') %}
{% set redis_min_lifetime = pillar.get('min_lifetime', '60') %}
{% set redis_max_lifetime = pillar.get('max_lifetime', '2592000') %}
{% set magento_user = pillar.get('magento_user', 'www-data') %}
{% set magento_user_prefix = 'sudo -u {0} '.format(magento_user) if magento_user else '' %}
{% set magento_php = magento_user_prefix + 'php' %}
{% set magento_cli = magento_php + ' bin/magento' %}
{% set rendered_payload = {
  'site_path': site_path,
  'cache': {
    'host': valkey_host,
    'port': valkey_port,
    'password': valkey_password,
    'cache_db': cache_db,
    'page_db': page_db,
    'cache_prefix': cache_prefix,
    'compress_data': redis_compress,
  },
  'session': {
    'host': valkey_host,
    'port': valkey_port,
    'password': valkey_password,
    'session_db': session_db,
    'session_prefix': session_prefix,
    'timeout': redis_timeout,
    'max_concurrency': redis_max_concurrency,
    'break_after_frontend': redis_break_after_frontend,
    'break_after_adminhtml': redis_break_after_adminhtml,
    'first_lifetime': redis_first_lifetime,
    'bot_first_lifetime': redis_bot_first_lifetime,
    'bot_lifetime': redis_bot_lifetime,
    'disable_locking': redis_disable_locking,
    'min_lifetime': redis_min_lifetime,
    'max_lifetime': redis_max_lifetime,
  }
} %}

{% if not site_name %}
magento_valkey_missing_site_name:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法配置 Magento Valkey。"
{% elif cache_db is none or page_db is none or session_db is none %}
magento_valkey_missing_databases:
  test.fail_without_changes:
    - comment: "必须通过 pillar 传入 cache_db、page_db、session_db。"
{% elif not site_path %}
magento_valkey_missing_site_path:
  test.fail_without_changes:
    - comment: "无法推导站点路径，请在 pillar 中提供 site_path。"
{% else %}

{% set env_file = site_path ~ '/app/etc/env.php' %}
{% set site_path_exists = salt['file.directory_exists'](site_path) %}
{% set env_file_exists = salt['file.file_exists'](env_file) %}

{% if not site_path_exists %}
magento_valkey_site_missing:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not env_file_exists %}
magento_valkey_env_missing:
  test.fail_without_changes:
    - comment: "未找到 {{ env_file }}，请确认 Magento 已正确安装。"
{% else %}

magento_valkey_configure:
  cmd.run:
    - name: |
        {{ magento_php }} <<'PHP'
        <?php
        $payload = json_decode(<<<'JSON'
        {{ rendered_payload | json }}
        JSON
        , true);
        if (!is_array($payload)) {
            fwrite(STDERR, "解析 Magento Valkey 配置失败。\n");
            exit(1);
        }

        $envFile = 'app/etc/env.php';
        $config = include $envFile;
        if (!is_array($config)) {
            fwrite(STDERR, "env.php 未返回数组，无法继续。\n");
            exit(1);
        }

        $cacheData = $payload['cache'];
        $sessionData = $payload['session'];

        $config['cache']['frontend']['default'] = [
            'backend' => 'Magento\\Framework\\Cache\\Backend\\Redis',
            'backend_options' => [
                'server' => (string)$cacheData['host'],
                'port' => (string)$cacheData['port'],
                'database' => (string)$cacheData['cache_db'],
                'password' => (string)$cacheData['password'],
                'compress_data' => (string)$cacheData['compress_data'],
                'id_prefix' => (string)$cacheData['cache_prefix'],
            ],
        ];

        $config['cache']['frontend']['page_cache'] = [
            'backend' => 'Magento\\Framework\\Cache\\Backend\\Redis',
            'backend_options' => [
                'server' => (string)$cacheData['host'],
                'port' => (string)$cacheData['port'],
                'database' => (string)$cacheData['page_db'],
                'password' => (string)$cacheData['password'],
                'compress_data' => (string)$cacheData['compress_data'],
                'id_prefix' => (string)$cacheData['cache_prefix'],
            ],
        ];

        $config['session'] = [
            'save' => 'redis',
            'redis' => [
                'host' => (string)$sessionData['host'],
                'port' => (string)$sessionData['port'],
                'password' => (string)$sessionData['password'],
                'timeout' => (string)$sessionData['timeout'],
                'persistent_identifier' => '',
                'database' => (string)$sessionData['session_db'],
                'compression_threshold' => '2048',
                'compression_library' => 'gzip',
                'log_level' => '1',
                'max_concurrency' => (string)$sessionData['max_concurrency'],
                'break_after_frontend' => (string)$sessionData['break_after_frontend'],
                'break_after_adminhtml' => (string)$sessionData['break_after_adminhtml'],
                'first_lifetime' => (string)$sessionData['first_lifetime'],
                'bot_first_lifetime' => (string)$sessionData['bot_first_lifetime'],
                'bot_lifetime' => (string)$sessionData['bot_lifetime'],
                'disable_locking' => (string)$sessionData['disable_locking'],
                'min_lifetime' => (string)$sessionData['min_lifetime'],
                'max_lifetime' => (string)$sessionData['max_lifetime'],
                'id_prefix' => (string)$sessionData['session_prefix'],
            ],
        ];

        $export = "<?php\nreturn " . var_export($config, true) . ";\n";
        if (false === file_put_contents($envFile, $export, LOCK_EX)) {
            fwrite(STDERR, "写入 env.php 失败。\n");
            exit(1);
        }
        ?>
        PHP
    - cwd: {{ site_path }}
    - unless: |
        {{ magento_php }} <<'PHP'
        <?php
        $payload = json_decode(<<<'JSON'
        {{ rendered_payload | json }}
        JSON
        , true);
        $config = include 'app/etc/env.php';
        if (!is_array($config) || !is_array($payload)) {
            exit(1);
        }

        $cacheData = $payload['cache'];
        $sessionData = $payload['session'];

        $default = $config['cache']['frontend']['default']['backend_options'] ?? [];
        $page = $config['cache']['frontend']['page_cache']['backend_options'] ?? [];
        $session = $config['session']['redis'] ?? [];

        $checks = [
            isset($config['cache']['frontend']['default']['backend']) &&
            $config['cache']['frontend']['default']['backend'] === 'Magento\\Framework\\Cache\\Backend\\Redis',

            isset($default['database']) && (string)$default['database'] === (string)$cacheData['cache_db'],
            isset($default['password']) && (string)$default['password'] === (string)$cacheData['password'],
            isset($default['id_prefix']) && (string)$default['id_prefix'] === (string)$cacheData['cache_prefix'],
            isset($default['server']) && (string)$default['server'] === (string)$cacheData['host'],
            isset($default['port']) && (string)$default['port'] === (string)$cacheData['port'],

            isset($page['database']) && (string)$page['database'] === (string)$cacheData['page_db'],
            isset($page['password']) && (string)$page['password'] === (string)$cacheData['password'],
            isset($page['id_prefix']) && (string)$page['id_prefix'] === (string)$cacheData['cache_prefix'],
            isset($page['server']) && (string)$page['server'] === (string)$cacheData['host'],
            isset($page['port']) && (string)$page['port'] === (string)$cacheData['port'],

            isset($session['database']) && (string)$session['database'] === (string)$sessionData['session_db'],
            isset($session['password']) && (string)$session['password'] === (string)$sessionData['password'],
            isset($session['id_prefix']) && (string)$session['id_prefix'] === (string)$sessionData['session_prefix'],
            isset($session['host']) && (string)$session['host'] === (string)$sessionData['host'],
            isset($session['port']) && (string)$session['port'] === (string)$sessionData['port'],
            isset($session['timeout']) && (string)$session['timeout'] === (string)$sessionData['timeout'],
            isset($session['max_concurrency']) && (string)$session['max_concurrency'] === (string)$sessionData['max_concurrency'],
            isset($session['break_after_frontend']) && (string)$session['break_after_frontend'] === (string)$sessionData['break_after_frontend'],
            isset($session['break_after_adminhtml']) && (string)$session['break_after_adminhtml'] === (string)$sessionData['break_after_adminhtml'],
            isset($session['first_lifetime']) && (string)$session['first_lifetime'] === (string)$sessionData['first_lifetime'],
            isset($session['bot_first_lifetime']) && (string)$session['bot_first_lifetime'] === (string)$sessionData['bot_first_lifetime'],
            isset($session['bot_lifetime']) && (string)$session['bot_lifetime'] === (string)$sessionData['bot_lifetime'],
            isset($session['disable_locking']) && (string)$session['disable_locking'] === (string)$sessionData['disable_locking'],
            isset($session['min_lifetime']) && (string)$session['min_lifetime'] === (string)$sessionData['min_lifetime'],
            isset($session['max_lifetime']) && (string)$session['max_lifetime'] === (string)$sessionData['max_lifetime'],
        ];

        foreach ($checks as $passed) {
            if (!$passed) {
                exit(1);
            }
        }
        exit(0);
        ?>
        PHP

{% set redis_auth = '-a "$VALKEY_PASSWORD"' if valkey_password else '' %}

magento_valkey_flush_databases:
  cmd.wait:
    - name: |
        redis-cli {{ redis_auth }} -n {{ cache_db }} flushdb
        redis-cli {{ redis_auth }} -n {{ page_db }} flushdb
        redis-cli {{ redis_auth }} -n {{ session_db }} flushdb
    - env:
        VALKEY_PASSWORD: {{ valkey_password }}
    - onchanges:
      - cmd: magento_valkey_configure

magento_valkey_cache_clean:
  cmd.wait:
    - name: {{ magento_cli }} cache:clean
    - cwd: {{ site_path }}
    - onchanges:
      - cmd: magento_valkey_configure

magento_valkey_cache_flush:
  cmd.wait:
    - name: {{ magento_cli }} cache:flush
    - cwd: {{ site_path }}
    - onchanges:
      - cmd: magento_valkey_cache_clean

magento_valkey_session_status:
  cmd.wait:
    - name: {{ magento_cli }} cache:status
    - cwd: {{ site_path }}
    - onchanges:
      - cmd: magento_valkey_cache_flush

{% endif %}
{% endif %}
