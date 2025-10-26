# Magento RabbitMQ 列表（Salt 原生）

{% set site_name = pillar.get('site_name') %}
{% set list_all = pillar.get('list_all', False) %}

{% if not site_name and not list_all %}
magento_rabbitmq_list_missing_site:
  test.fail_without_changes:
    - comment: "pillar['site_name'] 未提供，无法列出。"
{% else %}

magento_rabbitmq_list_units:
  cmd.run:
    - name: |
        bash -euo pipefail <<'SH'
        {% if list_all %}
        printf "[INFO] 列出所有 RabbitMQ 消费者单元：\n"
        systemctl list-units --type=service --all --no-legend 2>/dev/null \
          | awk '{print $1" "$4" "$3}' \
          | grep -E "^magento-consumer(@|-)"
        printf "\n[INFO] 列出 /etc/systemd/system 中的模板/旧版 unit：\n"
        ls /etc/systemd/system/magento-consumer@.service /etc/systemd/system/magento-consumer-*.service 2>/dev/null || true
        {% else %}
        SITE="{{ site_name }}"
        printf "[INFO] 列出与 %s 相关的消费者单元：\n" "$SITE"
        systemctl list-units --type=service --all --no-legend 2>/dev/null \
          | awk '{print $1" "$4" "$3}' \
          | grep -E "^magento-consumer(@|-)${SITE}-" || true
        printf "\n[INFO] 列出 /etc/systemd/system 中的模板/旧版 unit：\n"
        ls /etc/systemd/system/magento-consumer@.service /etc/systemd/system/magento-consumer-${SITE}-*.service 2>/dev/null || true
        {% endif %}
        SH

{% endif %}
