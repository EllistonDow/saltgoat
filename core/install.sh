#!/bin/bash
# 安装管理模块
# core/install.sh

# 抑制 Salt DeprecationWarning 警告
export PYTHONWARNINGS="ignore::DeprecationWarning"
export PYTHONPATH="/usr/local/lib/python3.12/dist-packages:$PYTHONPATH"

# 创建临时的 Python 警告过滤器
python3 -c "
import warnings
warnings.filterwarnings('ignore', category=DeprecationWarning)
warnings.filterwarnings('ignore', message='.*datetime.datetime.utcnow.*')
warnings.filterwarnings('ignore', message='.*crypt.*')
warnings.filterwarnings('ignore', message='.*spwd.*')
" 2>/dev/null || true

# 安装时可选的优化参数
OPTIMIZE_MAGENTO_ENABLED=false
OPTIMIZE_MAGENTO_PROFILE=""
OPTIMIZE_MAGENTO_SITE=""

# 加载安装配置
load_install_config() {
	log_info "加载安装配置..."

	# 重置可选项
	OPTIMIZE_MAGENTO_ENABLED=false
	OPTIMIZE_MAGENTO_PROFILE=""
	OPTIMIZE_MAGENTO_SITE=""

	# 载入已有 pillar 作为默认值
	load_pillar_defaults

	# 处理命令行参数覆盖（优先级最高）
	parse_install_args "$@"

	# 验证必要的配置
	validate_install_config
}

# 从 pillar 读取已有配置作为默认值
load_pillar_defaults() {
	local pillar_file
	pillar_file="$(get_local_pillar_file)"

	if [[ -f "$pillar_file" ]]; then
        log_info "从 Pillar 加载默认配置: ${pillar_file#"${SCRIPT_DIR}/"}"
		MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(get_local_pillar_value mysql_password)}"
		VALKEY_PASSWORD="${VALKEY_PASSWORD:-$(get_local_pillar_value valkey_password)}"
		RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(get_local_pillar_value rabbitmq_password)}"
		WEBMIN_PASSWORD="${WEBMIN_PASSWORD:-$(get_local_pillar_value webmin_password)}"
		PHPMYADMIN_PASSWORD="${PHPMYADMIN_PASSWORD:-$(get_local_pillar_value phpmyadmin_password)}"
		SSL_EMAIL="${SSL_EMAIL:-$(get_local_pillar_value ssl_email)}"
		TIMEZONE="${TIMEZONE:-$(get_local_pillar_value timezone)}"
		LANGUAGE="${LANGUAGE:-$(get_local_pillar_value language)}"
	else
		log_warning "未找到 Pillar 配置 salt/pillar/saltgoat.sls，将使用内置默认值"
	fi
}

# 配置 Salt minion 以读取项目 pillar（需要 root）
configure_salt_minion() {
	log_info "配置 Salt minion（pillar_roots）..."
	local pillar_conf="/etc/salt/minion.d/saltgoat-pillar.conf"
	local pillar_dir="${SCRIPT_DIR}/salt/pillar"
	sudo mkdir -p /etc/salt/minion.d
	sudo mkdir -p "$pillar_dir"
	sudo tee "$pillar_conf" >/dev/null <<EOF
pillar_roots:
  base:
    - $pillar_dir
EOF
	
	# 配置警告抑制
	sudo tee "/etc/salt/minion.d/suppress-warnings.conf" >/dev/null <<EOF
# 抑制 Salt DeprecationWarning 警告
log_level: warning
log_level_logfile: warning
python_warnings: false
EOF
	
	# 刷新 pillar（不阻断）
	sudo salt-call --local saltutil.refresh_pillar >/dev/null 2>&1 || true
	log_success "Salt minion 配置完成"
}

# 解析安装参数
parse_install_args() {
	log_info "解析命令行参数: $*"
	while [[ $# -gt 0 ]]; do
		case $1 in
		--mysql-password)
			MYSQL_PASSWORD="$2"
			log_info "设置 MySQL 密码: $MYSQL_PASSWORD"
			shift 2
			;;
		--valkey-password)
			VALKEY_PASSWORD="$2"
			log_info "设置 Valkey 密码: $VALKEY_PASSWORD"
			shift 2
			;;
		--rabbitmq-password)
			RABBITMQ_PASSWORD="$2"
			log_info "设置 RabbitMQ 密码: $RABBITMQ_PASSWORD"
			shift 2
			;;
		--webmin-password)
			WEBMIN_PASSWORD="$2"
			log_info "设置 Webmin 密码: $WEBMIN_PASSWORD"
			shift 2
			;;
		--phpmyadmin-password)
			PHPMYADMIN_PASSWORD="$2"
			log_info "设置 phpMyAdmin 密码: $PHPMYADMIN_PASSWORD"
			shift 2
			;;
		--ssl-email)
			SSL_EMAIL="$2"
			log_info "设置 SSL 邮箱: $SSL_EMAIL"
			shift 2
			;;
		--timezone)
			TIMEZONE="$2"
			log_info "设置时区: $TIMEZONE"
			shift 2
			;;
		--language)
			LANGUAGE="$2"
			log_info "设置语言: $LANGUAGE"
			shift 2
			;;
		--optimize-magento)
			OPTIMIZE_MAGENTO_ENABLED=true
			OPTIMIZE_MAGENTO_PROFILE="${OPTIMIZE_MAGENTO_PROFILE:-auto}"
			shift
			;;
		--optimize-magento=*)
			OPTIMIZE_MAGENTO_ENABLED=true
			OPTIMIZE_MAGENTO_PROFILE="${1#*=}"
			shift
			;;
		--optimize-magento-profile)
			OPTIMIZE_MAGENTO_ENABLED=true
			OPTIMIZE_MAGENTO_PROFILE="$2"
			shift 2
			;;
		--optimize-magento-profile=*)
			OPTIMIZE_MAGENTO_ENABLED=true
			OPTIMIZE_MAGENTO_PROFILE="${1#*=}"
			shift
			;;
		--optimize-magento-site)
			OPTIMIZE_MAGENTO_ENABLED=true
			OPTIMIZE_MAGENTO_SITE="$2"
			shift 2
			;;
		--optimize-magento-site=*)
			OPTIMIZE_MAGENTO_ENABLED=true
			OPTIMIZE_MAGENTO_SITE="${1#*=}"
			shift
			;;
		*)
			shift
			;;
		esac
	done
}

# 验证安装配置
validate_install_config() {
	log_info "验证安装配置..."

	# 设置默认值
	MYSQL_PASSWORD="${MYSQL_PASSWORD:-SaltGoat2024!}"
	VALKEY_PASSWORD="${VALKEY_PASSWORD:-Valkey2024!}"
	RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-RabbitMQ2024!}"
	WEBMIN_PASSWORD="${WEBMIN_PASSWORD:-Webmin2024!}"
	PHPMYADMIN_PASSWORD="${PHPMYADMIN_PASSWORD:-phpMyAdmin2024!}"
	SSL_EMAIL="${SSL_EMAIL:-admin@example.com}"
	TIMEZONE="${TIMEZONE:-America/Los_Angeles}"
	LANGUAGE="${LANGUAGE:-en_US.UTF-8}"

	# 更新 Pillar 数据
	update_pillar_config

	log_success "安装配置验证完成"
}

# 更新 Pillar 配置
update_pillar_config() {
	log_info "更新 Salt Pillar 配置..."

	# 创建临时 Pillar 文件
	local pillar_dir="${SCRIPT_DIR}/salt/pillar"
	local target_file="${pillar_dir}/saltgoat.sls"

	sudo mkdir -p "$pillar_dir"
	local tmp_file
	tmp_file=$(mktemp "${pillar_dir}/.saltgoat.XXXXXX") || {
		log_error "无法创建临时 Pillar 文件"
		exit 1
	}

	cat >"$tmp_file" <<EOF
mysql_password: '$MYSQL_PASSWORD'
valkey_password: '$VALKEY_PASSWORD'
rabbitmq_password: '$RABBITMQ_PASSWORD'
webmin_password: '$WEBMIN_PASSWORD'
phpmyadmin_password: '$PHPMYADMIN_PASSWORD'
ssl_email: '$SSL_EMAIL'
timezone: '$TIMEZONE'
language: '$LANGUAGE'
EOF

	sudo mv "$tmp_file" "$target_file"
	sudo chmod 600 "$target_file"

	# 刷新 Pillar，以便后续 state 读取到更新内容
	sudo salt-call --local saltutil.refresh_pillar >/dev/null 2>&1 || true

	log_success "Pillar 配置更新完成"
}

# 安装所有组件
install_all() {
	log_info "开始安装所有 SaltGoat 组件..."

	# 加载环境配置
	load_install_config "$@"

	# 配置 salt minion（确保能读取项目 pillar）
	configure_salt_minion
	
	# 设置SaltGoat项目目录grain
	salt-call --local grains.set saltgoat_project_dir "${SCRIPT_DIR}"

	# 安装系统依赖
	install_system_deps

	# 安装 Salt
	install_salt

	# 安装核心组件
	install_core

	# 安装可选组件
	install_optional

	log_success "SaltGoat 安装完成！"
	log_highlight "SaltGoat 版本信息"
	show_versions

	log_highlight "服务运行状态"
	show_status

	log_highlight "服务账户密码"
	show_passwords

	if [[ "$OPTIMIZE_MAGENTO_ENABLED" == true ]]; then
		log_highlight "应用 Magento 优化..."
		local optimize_args=()
		if [[ -n "$OPTIMIZE_MAGENTO_PROFILE" ]]; then
			optimize_args+=(--profile "$OPTIMIZE_MAGENTO_PROFILE")
		fi
		if [[ -n "$OPTIMIZE_MAGENTO_SITE" ]]; then
			optimize_args+=(--site "$OPTIMIZE_MAGENTO_SITE")
		fi
		optimize_magento "${optimize_args[@]}"
	else
		log_info "提示: 可运行 'saltgoat optimize magento' 以应用 Magento 调优"
	fi
}

# 安装核心组件
install_core() {
	log_info "安装核心组件..."

	# 应用核心状态
	sudo salt-call --local state.apply core.nginx
	sudo salt-call --local state.apply core.php
	sudo salt-call --local state.apply core.mysql pillar='{"mysql_password":"'"$MYSQL_PASSWORD"'"}'
	sudo salt-call --local state.apply core.composer

	log_success "核心组件安装完成"
}

# 安装可选组件
install_optional() {
	log_info "安装可选组件..."

	# 应用可选状态
	sudo salt-call --local state.apply optional.valkey
	sudo salt-call --local state.apply optional.opensearch
	sudo salt-call --local state.apply optional.rabbitmq
	sudo salt-call --local state.apply optional.varnish
	sudo salt-call --local state.apply optional.fail2ban
	sudo salt-call --local state.apply optional.webmin
	sudo salt-call --local state.apply optional.phpmyadmin
	sudo salt-call --local state.apply optional.certbot

	log_success "可选组件安装完成"
}

# 安装系统依赖
install_system_deps() {
	log_info "安装系统依赖..."

	# 更新包列表
	sudo salt-call --local cmd.run "apt update"

	# 安装基础包（使用 pkgs 列表，避免位置参数被误解析为 fromrepo 等字段）
	sudo salt-call --local pkg.install pkgs='["curl", "wget", "git", "unzip"]'

	log_success "系统依赖安装完成"
}

# 安装 Salt
install_salt() {
	log_info "安装 Salt..."

	# 检查 Salt 是否已安装
	if command_exists salt-call; then
		log_info "Salt 已安装，跳过安装步骤"
		return
	fi

	# 安装 Salt
	salt-call --local cmd.run "curl -L https://bootstrap.saltproject.io | sudo sh -s -- -M -N"

	log_success "Salt 安装完成"
}
