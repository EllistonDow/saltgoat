# Composer 2.8 安装和配置


# 下载 Composer 安装脚本
download_composer_installer:
  cmd.run:
    - name: |
        curl -sS https://getcomposer.org/installer -o composer-setup.php
        php -r "if (hash_file('sha384', 'composer-setup.php') === '$(curl -sS https://composer.github.io/installer.sig)') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
    - cwd: /tmp
    - unless: test -f /usr/local/bin/composer

# 安装 Composer
install_composer:
  cmd.run:
    - name: |
        php composer-setup.php --install-dir=/usr/local/bin --filename=composer
        rm composer-setup.php
    - cwd: /tmp
    - require:
      - cmd: download_composer_installer
    - unless: test -f /usr/local/bin/composer

# 设置 Composer 权限
set_composer_permissions:
  cmd.run:
    - name: chmod +x /usr/local/bin/composer
    - require:
      - cmd: install_composer

# 验证 Composer 安装
verify_composer:
  cmd.run:
    - name: composer --version
    - require:
      - cmd: set_composer_permissions

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
