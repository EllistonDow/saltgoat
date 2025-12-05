#!/bin/bash
# 安装管理模块
# core/install.sh

# 抑制 Salt DeprecationWarning 警告
export PYTHONWARNINGS="ignore::DeprecationWarning"
export PYTHONPATH="/usr/local/lib/python3.12/dist-packages:$PYTHONPATH"
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 创建临时的 Python 警告过滤器
python3 -c "
import warnings
warnings.filterwarnings('ignore', category=DeprecationWarning)
warnings.filterwarnings('ignore', message='.*datetime.datetime.utcnow.*')
warnings.filterwarnings('ignore', message='.*crypt.*')
warnings.filterwarnings('ignore', message='.*spwd.*')
" 2>/dev/null || true

# Salt 本地执行上下文
SALT_FILE_ROOT="${SCRIPT_DIR}/salt/states"
SALT_PILLAR_ROOT="${SCRIPT_DIR}/salt/pillar"
SALT_CALL_COMMON=(--local "--file-root=${SALT_FILE_ROOT}" "--pillar-root=${SALT_PILLAR_ROOT}")

# 安装时可选的优化参数
OPTIMIZE_MAGENTO_ENABLED=false
OPTIMIZE_MAGENTO_PROFILE=""
OPTIMIZE_MAGENTO_SITE=""
INSTALL_CONFIG_READY=0

salt_call() {
    sudo PYTHONWARNINGS="ignore::DeprecationWarning" \
        salt-call "${SALT_CALL_COMMON[@]}" "$@"
}

salt_call_state() {
    local state="$1"
    shift || true
    salt_call state.apply "$state" "$@"
}

# 加载安装配置
load_install_config() {
	log_info "加载安装配置..."

	# 重置可选项
	OPTIMIZE_MAGENTO_ENABLED=false
	OPTIMIZE_MAGENTO_PROFILE=""
	OPTIMIZE_MAGENTO_SITE=""
	reset_install_overrides

	# 载入已有 pillar 作为默认值
	load_pillar_defaults

	# 处理命令行参数覆盖（优先级最高）
	parse_install_args "$@"

	# 验证必要的配置
	validate_install_config
	INSTALL_CONFIG_READY=1
}

reset_install_overrides() {
	MYSQL_PASSWORD=""
	VALKEY_PASSWORD=""
	RABBITMQ_PASSWORD=""
	WEBMIN_PASSWORD=""
	PHPMYADMIN_PASSWORD=""
	OPENSEARCH_ADMIN_PASSWORD=""
	SSL_EMAIL=""
	TIMEZONE=""
	LANGUAGE=""
}

# 从 pillar 读取已有配置作为默认值
load_pillar_defaults() {
	local pillar_file secret_file
	pillar_file="$(get_local_pillar_file)"
	secret_file="$(get_secret_pillar_dir)/saltgoat.sls"

	local -a sources=()
	if [[ -f "$pillar_file" ]]; then
		sources+=("${pillar_file#"${SCRIPT_DIR}/"}")
	fi
	if sudo test -f "$secret_file" 2>/dev/null; then
		sources+=("${secret_file#"${SCRIPT_DIR}/"}")
	fi

	local loaded=0 value

	value="$(get_local_pillar_value mysql_password || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$MYSQL_PASSWORD" ]] && MYSQL_PASSWORD="$value"
		loaded=1
	fi

	value="$(get_local_pillar_value valkey_password || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$VALKEY_PASSWORD" ]] && VALKEY_PASSWORD="$value"
		loaded=1
	fi

	value="$(get_local_pillar_value rabbitmq_password || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$RABBITMQ_PASSWORD" ]] && RABBITMQ_PASSWORD="$value"
		loaded=1
	fi

	value="$(get_local_pillar_value webmin_password || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$WEBMIN_PASSWORD" ]] && WEBMIN_PASSWORD="$value"
		loaded=1
	fi

	value="$(get_local_pillar_value phpmyadmin_password || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$PHPMYADMIN_PASSWORD" ]] && PHPMYADMIN_PASSWORD="$value"
		loaded=1
	fi

	value="$(get_local_pillar_value opensearch_admin_password || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$OPENSEARCH_ADMIN_PASSWORD" ]] && OPENSEARCH_ADMIN_PASSWORD="$value"
		loaded=1
	fi

	value="$(get_local_pillar_value ssl_email || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$SSL_EMAIL" ]] && SSL_EMAIL="$value"
		loaded=1
	fi

	value="$(get_local_pillar_value timezone || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$TIMEZONE" ]] && TIMEZONE="$value"
		loaded=1
	fi

	value="$(get_local_pillar_value language || true)"
	if [[ -n "$value" ]]; then
		[[ -z "$LANGUAGE" ]] && LANGUAGE="$value"
		loaded=1
	fi

	if (( loaded )); then
		if ((${#sources[@]})); then
			local IFS=', '
			local source_desc="${sources[*]}"
			log_info "从 Pillar 加载默认配置: $source_desc"
		else
			log_info "从 Pillar 加载默认配置"
		fi
	else
		log_warning "未找到 Pillar 配置 (salt/pillar/saltgoat.sls 或 secret/saltgoat.sls)，将使用内置默认值"
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
file_client: local
state_queue: True
renderer: jinja|yaml
EOF
	
	# 配置警告抑制
	sudo tee "/etc/salt/minion.d/suppress-warnings.conf" >/dev/null <<EOF
# 抑制 Salt DeprecationWarning 警告
log_level: warning
log_level_logfile: warning
python_warnings: false
EOF
	
	# 刷新 pillar（不阻断）
	if command_exists salt-call; then
		salt_call saltutil.refresh_pillar >/dev/null 2>&1 || true
	fi
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
		--opensearch-password)
			OPENSEARCH_ADMIN_PASSWORD="$2"
			log_info "设置 OpenSearch 密码: $OPENSEARCH_ADMIN_PASSWORD"
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
		--opensearch-password=*)
			OPENSEARCH_ADMIN_PASSWORD="${1#*=}"
			shift
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

# 生成随机强密码（24 位，含大小写和数字符号）
generate_random_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 | tr -d '\n' | cut -c1-24
    else
        python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + '!@#$%_-+'
print(''.join(secrets.choice(alphabet) for _ in range(24)))
PY
    fi
}

# 检查是否存在 Magento 站点（/var/www/*/app/etc/env.php）
has_magento_sites() {
    compgen -G "/var/www/*/app/etc/env.php" >/dev/null 2>&1
}

# 验证安装配置
validate_install_config() {
    log_info "验证安装配置..."

    # 自动生成随机密码
    MYSQL_PASSWORD="${MYSQL_PASSWORD:-$(generate_random_password)}"
    VALKEY_PASSWORD="${VALKEY_PASSWORD:-$(generate_random_password)}"
    RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(generate_random_password)}"
    WEBMIN_PASSWORD="${WEBMIN_PASSWORD:-$(generate_random_password)}"
	PHPMYADMIN_PASSWORD="${PHPMYADMIN_PASSWORD:-$(generate_random_password)}"
	OPENSEARCH_ADMIN_PASSWORD="${OPENSEARCH_ADMIN_PASSWORD:-$(generate_random_password)}"
	SSL_EMAIL="${SSL_EMAIL:-admin@example.com}"
	TIMEZONE="${TIMEZONE:-America/Los_Angeles}"
	LANGUAGE="${LANGUAGE:-en_US.UTF-8}"
	export OPENSEARCH_INITIAL_ADMIN_PASSWORD="$OPENSEARCH_ADMIN_PASSWORD"

	# 更新 Pillar 数据
	update_pillar_config

	log_success "安装配置验证完成"
}

ensure_install_config_loaded() {
	if [[ "${INSTALL_CONFIG_READY:-0}" != "1" || $# -gt 0 ]]; then
		load_install_config "$@"
	fi
}

ensure_salt_python_mysql_client() {
	if ! command_exists salt-call; then
		log_warning "Salt 未安装，无法为 Salt Python 环境安装 PyMySQL"
		return
	fi

	local salt_call_path salt_call_real salt_dir python_bin pip_bin
	salt_call_path="$(command -v salt-call)"
	salt_call_real="$(readlink -f "$salt_call_path")"
	salt_dir="$(dirname "$salt_call_real")"
	if [[ -x "${salt_dir}/bin/python3" ]]; then
		python_bin="${salt_dir}/bin/python3"
	else
		python_bin="$(head -n1 "$salt_call_real" | sed -n 's/^#![[:space:]]*//p')"
	fi
	if [[ -z "$python_bin" || ! -x "$python_bin" ]]; then
		python_bin="$(command -v python3 || true)"
	fi
	if [[ -z "$python_bin" || ! -x "$python_bin" ]]; then
		log_warning "无法解析 Salt Python 解释器路径，跳过 PyMySQL 安装"
		return
	fi

	pip_bin="$(dirname "$python_bin")/pip3"
	if [[ ! -x "$pip_bin" ]]; then
		log_warning "未找到 ${pip_bin}，跳过 PyMySQL 安装"
		return
	fi

	if "$python_bin" -c "import pymysql" >/dev/null 2>&1; then
		log_info "Salt Python 环境已具备 PyMySQL"
		return
	fi

	log_info "为 Salt Python 环境安装 PyMySQL..."
	local pip_log
	pip_log="$(mktemp /tmp/saltgoat-pip.XXXXXX)" || pip_log="/tmp/saltgoat-pip.log"
	if "$pip_bin" install --disable-pip-version-check PyMySQL >"$pip_log" 2>&1; then
		log_success "PyMySQL 已安装"
	else
		log_warning "PyMySQL 安装失败，可手动执行 'sudo ${pip_bin} install PyMySQL'"
		cat "$pip_log" >&2 || true
	fi
	rm -f "$pip_log" >/dev/null 2>&1 || true
}

# 更新 Pillar 配置
update_pillar_config() {
	log_info "更新 Salt Pillar 配置..."

	# 创建临时 Pillar 文件
	local pillar_dir="${SCRIPT_DIR}/salt/pillar/secret"
	local target_file="${pillar_dir}/saltgoat.sls"
	local auth_file="${pillar_dir}/auth.sls"

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
opensearch_admin_password: '$OPENSEARCH_ADMIN_PASSWORD'
ssl_email: '$SSL_EMAIL'
timezone: '$TIMEZONE'
language: '$LANGUAGE'
EOF

	sudo mv "$tmp_file" "$target_file"
	sudo chown root:root "$target_file"
	sudo chmod 600 "$target_file"

	local tmp_auth
	tmp_auth=$(mktemp "${pillar_dir}/.auth.XXXXXX") || {
		log_error "无法创建临时 Auth Pillar 文件"
		exit 1
	}

	cat >"$tmp_auth" <<EOF
auth:
  mysql:
    root_password: '$MYSQL_PASSWORD'
  valkey:
    password: '$VALKEY_PASSWORD'
  rabbitmq:
    password: '$RABBITMQ_PASSWORD'
  webmin:
    password: '$WEBMIN_PASSWORD'
  phpmyadmin:
    password: '$PHPMYADMIN_PASSWORD'
  opensearch:
    admin_password: '$OPENSEARCH_ADMIN_PASSWORD'
EOF

	sudo mv "$tmp_auth" "$auth_file"
	sudo chown root:root "$auth_file"
	sudo chmod 600 "$auth_file"

	# 刷新 Pillar，以便后续 state 读取到更新内容
	if command_exists salt-call; then
		salt_call saltutil.refresh_pillar >/dev/null 2>&1 || true
	fi

	log_success "Pillar 配置更新完成"
}

# 安装所有组件
install_all() {
	log_info "开始安装所有 SaltGoat 组件..."
	local summary_beacons_enabled=false
	local summary_beacons_message=""

	# 加载环境配置
	load_install_config "$@"

	# 安装系统依赖
	install_system_deps || return 1

	# 安装 Salt，后续命令依赖 salt-call
	install_salt || return 1
	ensure_salt_python_mysql_client

	# 配置 salt minion（确保能读取项目 pillar）
	configure_salt_minion

	# 设置SaltGoat项目目录grain
	if command_exists salt-call; then
		salt_call grains.set saltgoat_project_dir "${SCRIPT_DIR}"
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
		if has_magento_sites; then
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

			log_info "如需 Telegram 话题映射，请直接维护 Pillar 'telegram_topics'（原同步脚本已停用）。"
		else
			log_info "未检测到 Magento 站点，已跳过自动调度与健康检查配置。"
		fi
	else
		log_info "提示: 安装完成后可运行 'sudo saltgoat magetools schedule auto' 规划 Magento Salt Schedule"
	fi

	if command -v saltgoat >/dev/null 2>&1; then
		log_highlight "启用 Salt Beacons/Reactors..."
		if beacon_output=$(sudo saltgoat monitor enable-beacons 2>&1); then
			summary_beacons_enabled=true
			summary_beacons_message="$beacon_output"
			log_success "Salt Beacons/Reactors 已启用"
			printf '%s\n' "$beacon_output"
		else
			summary_beacons_message="$beacon_output"
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

	log_highlight "自动启用组件"
	if systemctl is-active --quiet salt-master 2>/dev/null; then
		log_info "- Salt master: active"
	else
		log_warning "- Salt master 未运行，可执行 'sudo systemctl restart salt-master'"
	fi
	if systemctl is-active --quiet salt-minion 2>/dev/null; then
		log_info "- Salt minion: active"
	else
		log_warning "- Salt minion 未运行，可执行 'sudo systemctl restart salt-minion'"
	fi
	if [[ -f "${SCRIPT_DIR}/salt/pillar/secret/saltgoat.sls" ]]; then
		log_info "- Pillar secrets: 已写入 salt/pillar/secret/saltgoat.sls"
	else
		log_warning "- Pillar secrets: 未检测到 salt/pillar/secret/saltgoat.sls"
	fi
	if [[ "$summary_beacons_enabled" == true ]]; then
		log_info "- Salt Beacons/Reactors: 已启用"
	else
		log_warning "- Salt Beacons/Reactors: 需手动运行 'sudo saltgoat monitor enable-beacons'"
		if [[ -n "$summary_beacons_message" ]]; then
			printf '%s\n' "$summary_beacons_message"
		fi
	fi
}

# 安装核心组件
install_core() {
	ensure_install_config_loaded "$@"
	log_info "安装核心组件..."

	ensure_salt_python_mysql_client

	salt_call_state core.salt-roots
	salt_call_state pillar.secret-init
	salt_call_state core.restic

	# 应用核心状态
	salt_call_state core.nginx
	salt_call_state core.php
	salt_call_state core.mysql pillar='{"mysql_password":"'"$MYSQL_PASSWORD"'"}'
	salt_call_state core.composer

	log_success "核心组件安装完成"
}

# 安装可选组件
install_optional() {
	ensure_install_config_loaded "$@"
	log_info "安装可选组件..."

	# 应用可选状态
	salt_call_state optional.valkey
	salt_call_state optional.opensearch
	salt_call_state optional.rabbitmq
	salt_call_state optional.varnish
	salt_call_state optional.fail2ban
	salt_call_state optional.webmin
	salt_call_state optional.phpmyadmin
	salt_call_state optional.certbot
	salt_call_state optional.dropbox
	salt_call_state optional.backup-restic
	salt_call_state optional.mysql-backup

	log_success "可选组件安装完成"
}

# 安装系统依赖
install_system_deps() {
	log_info "安装系统依赖..."

	if sudo -E apt-get update; then
		log_info "APT 软件包列表已更新"
	else
		log_warning "apt-get update 失败，可稍后手动运行 'sudo apt-get update'"
	fi

	local deps=(curl wget git unzip openssl python3-venv ca-certificates python3-pymysql python3-mysqldb)
	if sudo -E apt-get install -yq -o Dpkg::Options::='--force-confnew' "${deps[@]}"; then
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

	local bootstrap_url="https://github.com/saltstack/salt-bootstrap/releases/latest/download/bootstrap-salt.sh"
	local legacy_bootstrap_url="https://bootstrap.saltproject.io"
	local bootstrap_tmp
	bootstrap_tmp="$(mktemp)"
	trap 'rm -f "$bootstrap_tmp"' RETURN

	# 下载最新 bootstrap（官方已迁移到 GitHub Releases）
	if ! curl -fsSL -o "$bootstrap_tmp" "$bootstrap_url"; then
		log_warning "无法从官方 GitHub 获取 bootstrap 脚本，尝试旧地址"
		if ! curl -fsSL -o "$bootstrap_tmp" "$legacy_bootstrap_url"; then
			log_error "下载 Salt bootstrap 脚本失败，请检查网络或参考 https://repo.saltproject.io/ 手动安装"
			return 1
		fi
	fi

	if ! head -n1 "$bootstrap_tmp" | grep -q "^#!/"; then
		log_error "下载的 Salt bootstrap 内容异常，请参考 https://repo.saltproject.io/ 手动安装"
		return 1
	fi

	# 安装 master + minion（-M 安装 master，默认包含 minion，不使用 -N）
	if sudo sh "$bootstrap_tmp" -M; then
		log_success "Salt 安装完成"
		sudo systemctl enable --now salt-master salt-minion
	else
		log_error "Salt 安装失败，请检查网络或参考 https://repo.saltproject.io/ 手动安装"
		return 1
	fi
}
