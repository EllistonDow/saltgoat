#!/bin/bash
# 安装管理模块
# core/install.sh

# 抑制 Salt DeprecationWarning 警告
export PYTHONWARNINGS="ignore::DeprecationWarning"
export PYTHONPATH="/usr/local/lib/python3.12/dist-packages:$PYTHONPATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
		MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(get_local_pillar_value mysql_password || true)}"
		VALKEY_PASSWORD="${VALKEY_PASSWORD:-$(get_local_pillar_value valkey_password || true)}"
		RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(get_local_pillar_value rabbitmq_password || true)}"
		WEBMIN_PASSWORD="${WEBMIN_PASSWORD:-$(get_local_pillar_value webmin_password || true)}"
		PHPMYADMIN_PASSWORD="${PHPMYADMIN_PASSWORD:-$(get_local_pillar_value phpmyadmin_password || true)}"
		SSL_EMAIL="${SSL_EMAIL:-$(get_local_pillar_value ssl_email || true)}"
		TIMEZONE="${TIMEZONE:-$(get_local_pillar_value timezone || true)}"
		LANGUAGE="${LANGUAGE:-$(get_local_pillar_value language || true)}"
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
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local saltutil.refresh_pillar >/dev/null 2>&1 || true
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
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local saltutil.refresh_pillar >/dev/null 2>&1 || true

	log_success "Pillar 配置更新完成"
}

# 安装所有组件
install_all() {
	log_info "开始安装所有 SaltGoat 组件..."

	# 加载环境配置
	load_install_config "$@"

	# 安装系统依赖
	install_system_deps || return 1

	# 安装 Salt，后续命令依赖 salt-call
	install_salt || return 1

	# 配置 salt minion（确保能读取项目 pillar）
	configure_salt_minion

	# 设置SaltGoat项目目录grain
	if command_exists salt-call; then
		salt-call --local grains.set saltgoat_project_dir "${SCRIPT_DIR}"
	else
		log_warning "salt-call 不可用，无法设置 saltgoat_project_dir grain"
	fi

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

	if command -v saltgoat >/dev/null 2>&1; then
		log_highlight "自动规划 Magento Salt Schedule..."
		if schedule_output=$(sudo saltgoat magetools schedule auto 2>&1); then
			log_success "Magento Salt Schedule 已收敛"
			printf '%s\n' "$schedule_output"
		else
			log_warning "自动规划 Salt Schedule 失败，可稍后手动执行 'sudo saltgoat magetools schedule auto'"
			printf '%s\n' "$schedule_output"
		fi

        log_highlight "生成站点健康检查配置..."
        if monitor_output=$(sudo saltgoat monitor auto-sites 2>&1); then
            log_success "站点健康检查已自动配置"
            printf '%s\n' "$monitor_output"
        else
            log_warning "站点健康检查自动配置失败，可稍后手动执行 'sudo saltgoat monitor auto-sites'"
            printf '%s\n' "$monitor_output"
        fi

        local topics_script="${SCRIPT_DIR}/scripts/setup-telegram-topics.py"
        if [[ -x "$topics_script" ]]; then
            log_highlight "同步 Telegram 话题映射..."
            if topics_output=$(sudo python3 "$topics_script" 2>&1); then
                printf '%s\n' "$topics_output"
            else
                log_warning "Telegram 话题同步失败，可稍后运行 'sudo python3 scripts/setup-telegram-topics.py'"
                printf '%s\n' "$topics_output"
            fi
        fi
	else
		log_info "提示: 安装完成后可运行 'sudo saltgoat magetools schedule auto' 规划 Magento Salt Schedule"
	fi

	if command -v saltgoat >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1 \
		&& systemctl list-unit-files | grep -q '^salt-minion\\.service'; then
		log_highlight "启用 Salt Beacons/Reactors..."
		if beacon_output=$(sudo saltgoat monitor enable-beacons 2>&1); then
			log_success "Salt Beacons/Reactors 已启用"
			printf '%s\n' "$beacon_output"
		else
			log_warning "自动启用 Salt Beacons 失败，可稍后手动执行 'sudo saltgoat monitor enable-beacons'"
			printf '%s\n' "$beacon_output"
		fi
	else
		log_info "提示: 安装 salt-minion 后可执行 'sudo saltgoat monitor enable-beacons' 启用事件驱动自动化"
	fi

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
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply core.nginx
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply core.php
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply core.mysql pillar='{"mysql_password":"'"$MYSQL_PASSWORD"'"}'
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply core.composer

	log_success "核心组件安装完成"
}

# 安装可选组件
install_optional() {
	log_info "安装可选组件..."

	# 应用可选状态
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply optional.valkey
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply optional.opensearch
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply optional.rabbitmq
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply optional.varnish
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply optional.fail2ban
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply optional.webmin
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply optional.phpmyadmin
	sudo PYTHONWARNINGS="ignore::DeprecationWarning" salt-call --local state.apply optional.certbot

	log_success "可选组件安装完成"
}

# 安装系统依赖
install_system_deps() {
	log_info "安装系统依赖..."

	if sudo apt-get update; then
		log_info "APT 软件包列表已更新"
	else
		log_warning "apt-get update 失败，可稍后手动运行 'sudo apt-get update'"
	fi

	local deps=(curl wget git unzip openssl python3-venv ca-certificates)
	if sudo apt-get install -y "${deps[@]}"; then
		log_success "系统依赖安装完成"
	else
		log_error "安装系统依赖失败，请检查网络或软件源后重试"
		return 1
	fi
}

# 安装 Salt
install_salt() {
	log_info "安装 Salt..."

	# 检查 Salt 是否已安装
	if command_exists salt-call; then
		log_info "Salt 已安装，跳过安装步骤"
		return
	fi

	local bootstrap_script="https://bootstrap.saltproject.io"
	if curl -fsSL "$bootstrap_script" | sudo sh -s -- -M -N; then
		log_success "Salt 安装完成"
	else
		log_error "Salt 安装失败，请检查网络或参考 https://repo.saltproject.io/ 手动安装"
		return 1
	fi
}
