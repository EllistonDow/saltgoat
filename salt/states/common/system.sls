# 系统基础配置

# 更新系统包
update_system_packages:
  cmd.run:
    - name: apt update && apt upgrade -y
    - creates: /tmp/saltgoat_system_updated

# 安装基础工具
install_basic_tools:
  pkg.installed:
    - names:
      - curl
      - wget
      - git
      - unzip
      - software-properties-common
      - apt-transport-https
      - ca-certificates
      - gnupg
      - lsb-release

# 设置时区
set_timezone:
  timezone.system:
    - name: UTC

# 设置语言环境
set_locale:
  locale.system:
    - name: en_US.UTF-8

# 创建应用用户
create_app_user:
  user.present:
    - name: lemp
    - fullname: LEMP Stack User
    - shell: /bin/bash
    - home: /home/lemp
    - createhome: true
    - groups:
      - www-data
