{% set composer_version = salt['pillar.get']('saltgoat:versions:composer', salt['pillar.get']('composer_version', '2.8.0')) %}

# Composer 2.8 固定版本安装
install_composer:
  cmd.run:
    - name: |
        curl -sSL https://getcomposer.org/download/{{ composer_version }}/composer.phar -o /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
    - unless: |
        composer --version 2>/dev/null | grep -q "{{ composer_version }}"

# 验证 Composer 安装
verify_composer:
  cmd.run:
    - name: composer --version
    - require:
      - cmd: install_composer

# 配置 Composer 全局设置
configure_composer:
  cmd.run:
    - name: |
        composer config -g repo.packagist composer https://packagist.org
        composer config -g process-timeout 2000
    - require:
      - cmd: verify_composer

# 创建 Composer 全局目录
create_composer_home:
  file.directory:
    - name: /root/.composer
    - user: root
    - group: root
    - mode: 755
    - require:
      - cmd: configure_composer
