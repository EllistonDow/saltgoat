# Magento Valkey 配置检测（Salt 原生）
#
# 通过 Salt 状态验证指定 Magento 站点的 Valkey/Redis 配置是否正确：
# - env.php 是否存在且可读
# - 缓存与会话配置是否指向 Redis 后端
# - 主机/端口/数据库/前缀/密码是否完整
# - 指定数据库能否成功 PING
# - env.php 所有者/权限是否符合预期
#
# 需要通过 pillar 传入：
#   site_name        （必填）
#   site_path        （可选，默认 /var/www/<site_name>）
#   expected_owner   （可选，默认 www-data）
#   expected_group   （可选，默认 www-data）
#   expected_perms   （可选，留空则不校验具体权限）
#   valkey_conf      （可选，用于补充信息）

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set expected_owner = pillar.get('expected_owner', 'www-data') %}
{% set expected_group = pillar.get('expected_group', 'www-data') %}
{% set expected_perms = pillar.get('expected_perms', '') %}
{% set valkey_conf = pillar.get('valkey_conf', '/etc/valkey/valkey.conf') %}

{% if not site_name %}
magento_valkey_check_missing_site_name:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法执行 Magento Valkey 检测。"

{% elif not site_path %}
magento_valkey_check_missing_site_path:
  test.fail_without_changes:
    - comment: "无法推导站点路径，请在 pillar 中提供 site_path。"

{% else %}

{% set env_file = site_path ~ '/app/etc/env.php' %}
{% set site_exists = salt['file.directory_exists'](site_path) %}
{% set env_exists = salt['file.file_exists'](env_file) %}

{% if not site_exists %}
magento_valkey_check_site_missing:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"

{% elif not env_exists %}
magento_valkey_check_env_missing:
  test.fail_without_changes:
    - comment: "未找到 {{ env_file }}，请确认 Magento 已正确安装。"

{% else %}

magento_valkey_check:
  cmd.run:
    - name: |
        php <<'PHP'
        <?php
        $expectedOwner = getenv('EXPECTED_OWNER') ?: '';
        $expectedGroup = getenv('EXPECTED_GROUP') ?: '';
        $expectedPerms = getenv('EXPECTED_PERMS') ?: '';
        $valkeyConf = getenv('VALKEY_CONF') ?: '/etc/valkey/valkey.conf';
        $siteName = getenv('SITE_NAME') ?: '';
        $envFile = 'app/etc/env.php';

        $errors = [];
        $warnings = [];
        $info = [];

        $redisCli = trim(shell_exec('command -v redis-cli 2>/dev/null') ?? '');
        if ($redisCli === '') {
            $errors[] = "未找到 redis-cli 命令，无法检测 Valkey 连接。";
        }

        if (!file_exists($envFile)) {
            $errors[] = "未找到 env.php 文件。";
        } elseif (!is_readable($envFile)) {
            $errors[] = "env.php 文件不可读。";
        }

        $cacheHost = $cachePort = $cacheDb = $cachePassword = $cachePrefix = null;
        $pageHost = $pagePort = $pageDb = $pagePassword = null;
        $sessionHost = $sessionPort = $sessionDb = $sessionPrefix = $sessionPassword = null;

        if (!$errors) {
            $config = include $envFile;
            if (!is_array($config)) {
                $errors[] = "env.php 未返回数组，无法检测。";
            } else {
                $cache = $config['cache']['frontend']['default'] ?? [];
                if (($cache['backend'] ?? '') !== 'Magento\\Framework\\Cache\\Backend\\Redis') {
                    $errors[] = "默认缓存未启用 Redis 后端。";
                }
                $cacheOptions = $cache['backend_options'] ?? [];
                $cacheHost = isset($cacheOptions['server']) ? (string)$cacheOptions['server'] : '';
                $cachePort = isset($cacheOptions['port']) ? (string)$cacheOptions['port'] : '';
                $cacheDb = isset($cacheOptions['database']) ? (string)$cacheOptions['database'] : '';
                $cachePassword = isset($cacheOptions['password']) && $cacheOptions['password'] !== false ? (string)$cacheOptions['password'] : '';
                $cachePrefix = isset($cacheOptions['id_prefix']) && $cacheOptions['id_prefix'] !== false ? (string)$cacheOptions['id_prefix'] : '';

                if ($cacheHost === '') {
                    $errors[] = "默认缓存未配置 server。";
                }
                if ($cachePort === '') {
                    $errors[] = "默认缓存未配置 port。";
                }
                if ($cacheDb === '') {
                    $errors[] = "默认缓存未配置 database。";
                }
                if ($cachePrefix === '') {
                    $warnings[] = "默认缓存未设置 id_prefix。";
                }

                $page = $config['cache']['frontend']['page_cache'] ?? [];
                if (($page['backend'] ?? '') !== 'Magento\\Framework\\Cache\\Backend\\Redis') {
                    $errors[] = "页面缓存未启用 Redis 后端。";
                }
                $pageOptions = $page['backend_options'] ?? [];
                $pageHost = isset($pageOptions['server']) ? (string)$pageOptions['server'] : '';
                $pagePort = isset($pageOptions['port']) ? (string)$pageOptions['port'] : '';
                $pageDb = isset($pageOptions['database']) ? (string)$pageOptions['database'] : '';
                $pagePassword = isset($pageOptions['password']) && $pageOptions['password'] !== false ? (string)$pageOptions['password'] : '';
                if ($pageHost === '') {
                    $warnings[] = "页面缓存未配置 server，默认沿用缓存配置。";
                    $pageHost = $cacheHost ?: '127.0.0.1';
                }
                if ($pagePort === '') {
                    $warnings[] = "页面缓存未配置 port，默认沿用缓存配置。";
                    $pagePort = $cachePort ?: '6379';
                }
                if ($pageDb === '') {
                    $errors[] = "页面缓存未配置 database。";
                }
                if ($pagePassword === '') {
                    $pagePassword = $cachePassword;
                }

                $session = $config['session'] ?? [];
                if (($session['save'] ?? '') !== 'redis') {
                    $errors[] = "会话存储未设置为 Redis。";
                }
                $sessionOptions = $session['redis'] ?? [];
                $sessionHost = isset($sessionOptions['host']) ? (string)$sessionOptions['host'] : '';
                $sessionPort = isset($sessionOptions['port']) ? (string)$sessionOptions['port'] : '';
                $sessionDb = isset($sessionOptions['database']) ? (string)$sessionOptions['database'] : '';
                $sessionPrefix = isset($sessionOptions['id_prefix']) && $sessionOptions['id_prefix'] !== false ? (string)$sessionOptions['id_prefix'] : '';
                $sessionPassword = isset($sessionOptions['password']) && $sessionOptions['password'] !== false ? (string)$sessionOptions['password'] : '';

                if ($sessionHost === '') {
                    $warnings[] = "会话未配置 host，默认将使用 127.0.0.1。";
                    $sessionHost = $cacheHost ?: '127.0.0.1';
                }
                if ($sessionPort === '') {
                    $warnings[] = "会话未配置 port，默认将使用 6379。";
                    $sessionPort = $cachePort ?: '6379';
                }
                if ($sessionDb === '') {
                    $errors[] = "会话存储未配置 database。";
                }
                if ($sessionPrefix === '') {
                    $warnings[] = "会话未设置 id_prefix。";
                }
                if ($sessionPassword === '') {
                    $sessionPassword = $cachePassword;
                }

                $passwords = array_filter(
                    [$cachePassword, $pagePassword, $sessionPassword],
                    function ($value) {
                        return $value !== null && $value !== '';
                    }
                );
                if (!$passwords) {
                    $warnings[] = "未检测到 Valkey 密码，确认是否已启用 requirepass。";
                } elseif (count(array_unique($passwords)) > 1) {
                    $warnings[] = "检测到 Valkey 密码不一致 (默认缓存/页面缓存/会话)。";
                }

                $info[] = "缓存主机: {$cacheHost}";
                $info[] = "缓存端口: {$cachePort}";
                $info[] = "缓存数据库: {$cacheDb}";
                $info[] = "页面缓存主机: {$pageHost}";
                $info[] = "页面缓存端口: {$pagePort}";
                $info[] = "页面缓存数据库: {$pageDb}";
                $info[] = "会话主机: {$sessionHost}";
                $info[] = "会话端口: {$sessionPort}";
                $info[] = "会话数据库: {$sessionDb}";
                if ($cachePrefix !== '') {
                    $info[] = "缓存前缀: {$cachePrefix}";
                }
                if ($sessionPrefix !== '') {
                    $info[] = "会话前缀: {$sessionPrefix}";
                }

                $stat = @stat($envFile);
                if ($stat) {
                    $owner = $stat['uid'];
                    $group = $stat['gid'];
                    $ownerName = function_exists('posix_getpwuid') ? (posix_getpwuid($owner)['name'] ?? (string)$owner) : (string)$owner;
                    $groupName = function_exists('posix_getgrgid') ? (posix_getgrgid($group)['name'] ?? (string)$group) : (string)$group;
                    $perms = substr(sprintf('%o', $stat['mode']), -3);
                    $info[] = "env.php 所有者: {$ownerName}:{$groupName}";
                    $info[] = "env.php 权限: {$perms}";

                    if ($expectedOwner !== '' && $ownerName !== $expectedOwner) {
                        $errors[] = "env.php 所有者为 {$ownerName}，期望 {$expectedOwner}。";
                    }
                    if ($expectedGroup !== '' && $groupName !== $expectedGroup) {
                        $errors[] = "env.php 所属组为 {$groupName}，期望 {$expectedGroup}。";
                    }
                    if ($expectedPerms !== '' && $perms !== $expectedPerms) {
                        $warnings[] = "env.php 权限为 {$perms}，期望 {$expectedPerms}。";
                    }
                }

                if ($redisCli !== '') {
                    $checks = [
                        ['label' => '默认缓存', 'db' => $cacheDb, 'host' => $cacheHost, 'port' => $cachePort, 'password' => $cachePassword],
                        ['label' => '页面缓存', 'db' => $pageDb, 'host' => $pageHost, 'port' => $pagePort, 'password' => $pagePassword],
                        ['label' => '会话缓存', 'db' => $sessionDb, 'host' => $sessionHost, 'port' => $sessionPort, 'password' => $sessionPassword],
                    ];

                    foreach ($checks as $item) {
                        $db = $item['db'];
                        if ($db === '' || !ctype_digit((string)$db)) {
                            continue;
                        }
                        $host = $item['host'] !== '' ? $item['host'] : '127.0.0.1';
                        $port = $item['port'] !== '' ? $item['port'] : '6379';
                        $password = $item['password'] ?? '';

                        $command = $redisCli . ' --no-auth-warning';
                        if ($password !== '') {
                            $command .= ' -a ' . escapeshellarg($password);
                        }
                        $command .= ' -h ' . escapeshellarg($host);
                        $command .= ' -p ' . escapeshellarg($port);
                        $command .= ' -n ' . (int)$db . ' ping';

                        $output = [];
                        $code = 0;
                        exec($command . ' 2>&1', $output, $code);
                        $result = trim(implode(' ', $output));
                        if ($code !== 0 || strtoupper($result) !== 'PONG') {
                            $errors[] = "{$item['label']} (DB {$db}) PING 失败: {$result}";
                        } else {
                            $info[] = "{$item['label']} (DB {$db}) 连接正常";
                        }
                    }
                }

                if ($valkeyConf !== '' && file_exists($valkeyConf)) {
                    $line = trim(shell_exec("grep -E '^\\s*requirepass' " . escapeshellarg($valkeyConf) . " | awk '{print $2}' | tail -n1 2>/dev/null") ?? '');
                    if ($line === '') {
                        $warnings[] = "Valkey 配置未检测到 requirepass。";
                    } elseif ($cachePassword !== '' && $cachePassword !== $line) {
                        $warnings[] = "env.php 中的 Valkey 密码与 " . $valkeyConf . " 不一致。";
                    }
                }
            }
        }

        if ($errors) {
            echo "[ERROR] Magento Valkey 配置检测失败" . PHP_EOL;
            foreach ($errors as $message) {
                echo "  - {$message}" . PHP_EOL;
            }
            if ($warnings) {
                echo "[WARN] 额外提示:" . PHP_EOL;
                foreach ($warnings as $message) {
                    echo "  - {$message}" . PHP_EOL;
                }
            }
            exit(1);
        }

        echo "[SUCCESS] Magento Valkey 配置检测通过" . PHP_EOL;
        foreach ($info as $message) {
            echo "  {$message}" . PHP_EOL;
        }
        if ($warnings) {
            echo "[WARN] 额外提示:" . PHP_EOL;
            foreach ($warnings as $message) {
                echo "  - {$message}" . PHP_EOL;
            }
        }
        exit(0);
        ?>
        PHP
    - cwd: {{ site_path }}
    - env:
        SITE_NAME: {{ site_name }}
        EXPECTED_OWNER: {{ expected_owner }}
        EXPECTED_GROUP: {{ expected_group }}
        EXPECTED_PERMS: {{ expected_perms }}
        VALKEY_CONF: {{ valkey_conf }}

{% endif %}
{% endif %}
