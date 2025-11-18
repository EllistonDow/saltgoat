# Magento RabbitMQ 检测（Salt 原生）

{% set site_name = pillar.get('site_name') %}
{% set site_path = pillar.get('site_path', '/var/www/{0}'.format(site_name) if site_name else None) %}
{% set amqp_host = pillar.get('amqp_host', '127.0.0.1') %}
{% set amqp_port = pillar.get('amqp_port', 5672) %}
{% set amqp_user = pillar.get('amqp_user', site_name if site_name else 'magento') %}
{% set amqp_password = pillar.get('amqp_password', '') %}
{% set amqp_vhost = pillar.get('amqp_vhost', '/' ~ site_name if site_name else '/magento') %}
{% set mode = pillar.get('mode', 'smart') %}
{% set threads = pillar.get('threads', 1) %}

{% if not site_name %}
rabbitmq_check_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法检测。"
{% elif not site_path %}
rabbitmq_check_missing_path:
  test.fail_without_changes:
    - comment: "无法推导站点路径，请提供 pillar['site_path']。"
{% else %}

{% set env_file = site_path ~ '/app/etc/env.php' %}
{% set site_exists = salt['file.directory_exists'](site_path) %}
{% set env_exists = salt['file.file_exists'](env_file) %}

{% if not site_exists %}
rabbitmq_check_site_missing:
  test.fail_without_changes:
    - comment: "站点目录 {{ site_path }} 不存在。"
{% elif not env_exists %}
rabbitmq_check_env_missing:
  test.fail_without_changes:
    - comment: "未找到 {{ env_file }}，请确认 Magento 已安装。"
{% else %}

{% set consumers_all = [
  'async.operations.all',
  'product_action_attribute.update',
  'product_action_attribute.website.update',
  'catalog_website_attribute_value_sync',
  'media.storage.catalog.image.resize',
  'exportProcessor',
  'inventory.source.items.cleanup',
  'inventory.mass.update',
  'inventory.reservations.cleanup',
  'inventory.reservations.update',
  'inventory.reservations.updateSalabilityStatus',
  'inventory.indexer.sourceItem',
  'inventory.indexer.stock',
  'media.content.synchronization',
  'media.gallery.renditions.update',
  'media.gallery.synchronization',
  'codegeneratorProcessor',
  'sales.rule.update.coupon.usage',
  'sales.rule.quote.trigger.recollect',
  'product_alert',
  'saveConfigProcessor',
] %}
{% set consumers_smart = [
  'async.operations.all',
  'product_action_attribute.update',
  'media.storage.catalog.image.resize',
  'exportProcessor',
  'inventory.reservations.update',
  'inventory.indexer.stock',
  'media.content.synchronization',
  'sales.rule.update.coupon.usage',
  'product_alert',
  'saveConfigProcessor',
] %}
{% set consumers = consumers_all if mode == 'all' else consumers_smart %}

rabbitmq_magento_check:
  cmd.run:
    - name: |
        bash -eu -o pipefail <<'SH'
        SITE="{{ site_name }}"
        SITE_PATH="{{ site_path }}"
        VHOST="{{ amqp_vhost }}"
        USER="{{ amqp_user }}"
        PASS="{{ amqp_password }}"
        HOST="{{ amqp_host }}"
        PORT="{{ amqp_port }}"
        MODE="{{ mode }}"
        THREADS="{{ threads }}"

        err=0
        warn=0

        echo "[INFO] 站点: $SITE"
        echo "[INFO] 路径: $SITE_PATH"
        echo "[INFO] Broker: $HOST:$PORT vhost=$VHOST user=$USER"
        echo "[INFO] 模式: $MODE 线程: $THREADS"

        # 1) Broker 服务名检查
        if systemctl is-active --quiet rabbitmq-server 2>/dev/null || systemctl is-active --quiet rabbitmq 2>/dev/null; then
          echo "[SUCCESS] RabbitMQ 服务运行中"
        else
          echo "[ERROR] RabbitMQ 服务未运行"
          err=$((err+1))
        fi

        # 2) vhost/user/permission 检查
        # 直接捕获输出再匹配，避免 grep 提前退出导致 rabbitmqctl 因 SIGPIPE 返回非零
        vhosts="$(sudo rabbitmqctl list_vhosts 2>/dev/null)"
        if grep -Fxq -- "$VHOST" <<<"$vhosts"; then
          echo "[SUCCESS] vhost 存在: $VHOST"
        else
          echo "[ERROR] vhost 不存在: $VHOST"
          err=$((err+1))
        fi

        users="$(sudo rabbitmqctl list_users 2>/dev/null | awk 'NR>1 {print $1}')"
        if grep -Fxq -- "$USER" <<<"$users"; then
          echo "[SUCCESS] 用户存在: $USER"
        else
          echo "[ERROR] 用户不存在: $USER"
          err=$((err+1))
        fi

        perms="$(sudo rabbitmqctl list_permissions -p "$VHOST" 2>/dev/null | awk '{print $1}')"
        if grep -Fxq -- "$USER" <<<"$perms"; then
          echo "[SUCCESS] 用户权限已设置 (vhost=$VHOST)"
        else
          echo "[ERROR] 用户权限缺失 (vhost=$VHOST)"
          err=$((err+1))
        fi

        # 3) env.php AMQP 配置一致性
        php <<'PHP' > /tmp/_amqp_check.out
        <?php
        $cfg = include 'app/etc/env.php';
        if (!is_array($cfg)) { echo "ERROR: env.php 解析失败\n"; exit(1);} 
        $amqp = $cfg['queue']['amqp'] ?? [];
        $wait = (int)($cfg['queue']['consumers_wait_for_messages'] ?? 0);
        printf("host=%s\n", $amqp['host'] ?? '');
        printf("port=%s\n", $amqp['port'] ?? '');
        printf("user=%s\n", $amqp['user'] ?? '');
        printf("vhost=%s\n", $amqp['virtualhost'] ?? '');
        printf("wait=%d\n", $wait);
        PHP
        cd "$SITE_PATH"
        . /tmp/_amqp_check.out
        rm -f /tmp/_amqp_check.out
        [[ "$host" == "$HOST" ]] || { echo "[ERROR] env.php host 不一致: $host != $HOST"; err=$((err+1)); }
        [[ "$port" == "$PORT" ]] || { echo "[ERROR] env.php port 不一致: $port != $PORT"; err=$((err+1)); }
        [[ "$user" == "$USER" ]] || { echo "[ERROR] env.php user 不一致: $user != $USER"; err=$((err+1)); }
        [[ "$vhost" == "$VHOST" ]] || { echo "[ERROR] env.php vhost 不一致: $vhost != $VHOST"; err=$((err+1)); }
        [[ "$wait" == "1" ]] || { echo "[WARN] consumers_wait_for_messages 未开启"; warn=$((warn+1)); }

        # 4) systemd 单元检查
        declare -a consumers
        consumers=(
        {% for c in consumers %}
          "{{ c }}"
        {% endfor %}
        )

        for cname in "${consumers[@]}"; do
          for ((i=1;i<=THREADS;i++)); do
            unit="magento-consumer@${SITE}-${cname}-${i}.service"
            if systemctl is-enabled --quiet "$unit" 2>/dev/null; then
              echo "[SUCCESS] 单元已启用: $unit"
            else
              echo "[ERROR] 单元未启用: $unit"
              err=$((err+1))
            fi
            if systemctl is-active --quiet "$unit" 2>/dev/null; then
              echo "[SUCCESS] 单元运行中: $unit"
            else
              echo "[WARN] 单元未运行: $unit"
              warn=$((warn+1))
            fi

            # 重启次数与失败状态检测（采样 2 次判断是否仍在增加）
            restarts1=$(systemctl show "$unit" --property=NRestarts --value 2>/dev/null || echo 0)
            mainstatus=$(systemctl show "$unit" --property=ExecMainStatus --value 2>/dev/null || echo 0)
            sleep 1
            restarts2=$(systemctl show "$unit" --property=NRestarts --value 2>/dev/null || echo 0)
            if systemctl is-failed --quiet "$unit" 2>/dev/null; then
              echo "[ERROR] 单元失败: $unit (NRestarts=$restarts2, ExecMainStatus=$mainstatus)"
              err=$((err+1))
            else
              if [[ "$restarts2" =~ ^[0-9]+$ ]] && [[ "$restarts1" =~ ^[0-9]+$ ]] && [ "$restarts2" -gt "$restarts1" ]; then
                echo "[WARN] 单元正在重启: $unit (NRestarts $restarts1->$restarts2)"
                warn=$((warn+1))
              elif [[ "$restarts2" =~ ^[0-9]+$ ]] && [ "$restarts2" -gt 5 ]; then
                echo "[INFO] 单元历史重启较多: $unit (NRestarts=$restarts2)"
              fi
            fi
          done
        done

        echo ""
        if (( err > 0 )); then
          echo "[ERROR] 检测失败，错误数: $err，警告数: $warn"
          exit 1
        fi
        echo "[SUCCESS] 检测通过，警告数: $warn"
        SH
    - cwd: {{ site_path }}

{% endif %}
{% endif %}
