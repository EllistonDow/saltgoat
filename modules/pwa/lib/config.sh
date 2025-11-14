#!/bin/bash

ensure_env_default() {
    local env_file="$1"
    local key="$2"
    local value="$3"
    if grep -q "^${key}=" "$env_file"; then
        return
    fi
    printf '%s=%s\n' "$key" "$value" | sudo -u www-data -H tee -a "$env_file" >/dev/null
}

sync_env_copy() {
    local src="$1"
    local dest="$2"
    if [[ ! -f "$src" ]]; then
        return
    fi
    if [[ ! -f "$dest" ]] || ! cmp -s "$src" "$dest"; then
        sudo -u www-data -H cp "$src" "$dest"
    fi
}

load_site_config() {
    local site="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        abort "缺少配置文件: ${CONFIG_FILE}，请先复制 magento-pwa.sls.sample 并填入站点参数。"
    fi

    local exports
    if ! exports=$(python3 "$PWA_HELPER" load-config --config "$CONFIG_FILE" --site "$site" 2>/dev/null); then
        log_error "解析 PWA 配置失败，请检查上方错误输出。"
        exit 1
    fi

    eval "$exports"
    if [[ ! -x "$PWA_HELPER" ]]; then
        abort "缺少 PWA helper: $PWA_HELPER"
    fi
    PWA_STUDIO_ENV_OVERRIDES_JSON="$(python3 "$PWA_HELPER" decode-b64 --data "${PWA_STUDIO_ENV_OVERRIDES_B64:-}")"
    if [[ -n "${PWA_HOME_TEMPLATE:-}" ]]; then
        if [[ "${PWA_HOME_TEMPLATE}" != /* ]]; then
            PWA_HOME_TEMPLATE_PATH="${SCRIPT_DIR%/}/${PWA_HOME_TEMPLATE}"
        else
            PWA_HOME_TEMPLATE_PATH="${PWA_HOME_TEMPLATE}"
        fi
        if [[ ! -f "$PWA_HOME_TEMPLATE_PATH" ]]; then
            PWA_HOME_TEMPLATE_WARNING="模板文件未找到: ${PWA_HOME_TEMPLATE_PATH}"
        fi
    else
        PWA_HOME_TEMPLATE_PATH=""
    fi
    if [[ -n "${PWA_ALT_HOME_TEMPLATE:-}" ]]; then
        if [[ "${PWA_ALT_HOME_TEMPLATE}" != /* ]]; then
            PWA_ALT_HOME_TEMPLATE_PATH="${SCRIPT_DIR%/}/${PWA_ALT_HOME_TEMPLATE}"
        else
            PWA_ALT_HOME_TEMPLATE_PATH="${PWA_ALT_HOME_TEMPLATE}"
        fi
        if [[ ! -f "$PWA_ALT_HOME_TEMPLATE_PATH" ]]; then
            PWA_ALT_HOME_TEMPLATE_WARNING="模板文件未找到: ${PWA_ALT_HOME_TEMPLATE_PATH}"
        fi
    else
        local default_alt="${SCRIPT_DIR%/}/modules/pwa/templates/cms/pwa_home_no_pb.html"
        if [[ -f "$default_alt" ]]; then
            PWA_ALT_HOME_TEMPLATE_PATH="$default_alt"
        else
            PWA_ALT_HOME_TEMPLATE_PATH=""
        fi
    fi
    if is_true "${PWA_STUDIO_ENABLE:-false}"; then
        PWA_WITH_FRONTEND="true"
    else
        PWA_WITH_FRONTEND="false"
    fi
}

prepare_pwa_env() {
    local env_file="$PWA_STUDIO_ENV_FILE"
    local template="$PWA_STUDIO_ENV_TEMPLATE"
    local overrides_json="$PWA_STUDIO_ENV_OVERRIDES_JSON"

    sudo -u www-data -H mkdir -p "$(dirname "$env_file")"

    if [[ -n "$template" && -f "$PWA_STUDIO_DIR/$template" ]]; then
        log_info "使用模板生成 PWA 环境变量文件"
        sudo -u www-data -H cp "$PWA_STUDIO_DIR/$template" "$env_file"
    elif [[ ! -f "$env_file" ]]; then
        log_info "创建新的 PWA 环境变量文件"
        sudo -u www-data -H touch "$env_file"
    fi

    if [[ -n "$overrides_json" && "$overrides_json" != "{}" ]]; then
        log_info "写入 PWA 环境变量覆盖项"
        python3 "$PWA_HELPER" apply-env --file "$env_file" --overrides "$overrides_json"
    fi

    if [[ -n "${PWA_HOME_IDENTIFIER:-}" ]]; then
        ensure_env_default "$env_file" "MAGENTO_PWA_HOME_IDENTIFIER" "${PWA_HOME_IDENTIFIER}"
    fi
    ensure_env_default "$env_file" "MAGENTO_BACKEND_EDITION" "MOS"
    ensure_env_default "$env_file" "MAGENTO_EXPERIENCE_PLATFORM_ENABLED" "false"
    ensure_env_default "$env_file" "MAGENTO_LIVE_SEARCH_ENABLED" "false"
    ensure_env_default "$env_file" "MAGENTO_PWA_HOME_IDENTIFIER" "home"
    ensure_env_default "$env_file" "SALTGOAT_PWA_SHOWCASE_FALLBACK" "auto"
    ensure_env_default "$env_file" "MAGENTO_PWA_ALT_HOME_IDENTIFIER" "pwa_home_no_pb"
    ensure_env_default "$env_file" "MAGENTO_PWA_ALT_HOME_TITLE" "PWA Home (No Page Builder)"

    local root_env="${PWA_STUDIO_DIR%/}/.env"
    local venia_env="${PWA_STUDIO_DIR%/}/packages/venia-concept/.env"
    sync_env_copy "$env_file" "$root_env"
    sync_env_copy "$env_file" "$venia_env"
}

ensure_pwa_env_vars() {
    local env_file="$PWA_STUDIO_ENV_FILE"
    if [[ ! -f "$env_file" ]]; then
        log_error "未找到 PWA 环境变量文件: ${env_file}"
        return 1
    fi
    local missing=()
    local key
    for key in "${PWA_REQUIRED_ENV_VARS[@]}"; do
        if ! grep -E -q "^${key}=" "$env_file"; then
            missing+=("$key")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "PWA 环境变量缺少必填项: ${missing[*]}"
        log_info "请在 salt/pillar/magento-pwa.sls 的 pwa_studio.env_overrides 中补充上述键值，或在运行时传入 --no-pwa 跳过前端构建。"
        return 1
    fi
    return 0
}

read_pwa_env_value() {
    local key="$1"
    local env_file="$PWA_STUDIO_ENV_FILE"
    python3 "$PWA_HELPER" get-env --file "$env_file" --key "$key"
}

log_pwa_home_identifier_hint() {
    local identifier
    identifier="$(read_pwa_env_value "MAGENTO_PWA_HOME_IDENTIFIER" 2>/dev/null || echo "")"
    if [[ -z "$identifier" ]]; then
        identifier="home"
    fi
    log_note "当前 PWA 首页 identifier = ${identifier}" "如需调整，请在 Pillar pwa_studio.env_overrides 中设置 MAGENTO_PWA_HOME_IDENTIFIER。"
    local alt_identifier
    alt_identifier="$(read_pwa_env_value "MAGENTO_PWA_ALT_HOME_IDENTIFIER" 2>/dev/null || echo "")"
    if [[ -z "$alt_identifier" ]]; then
        alt_identifier="pwa_home_no_pb"
    fi
    log_note "可选 No Page Builder 页面 identifier = ${alt_identifier}" "如需启用自由布局，可以让 MAGENTO_PWA_HOME_IDENTIFIER 指向该页面。"
}

resolve_home_template_file() {
    if [[ -n "$PWA_HOME_TEMPLATE_PATH" && -f "$PWA_HOME_TEMPLATE_PATH" ]]; then
        echo "$PWA_HOME_TEMPLATE_PATH"
    else
        echo ""
    fi
}

resolve_alt_home_template_file() {
    if [[ -n "$PWA_ALT_HOME_TEMPLATE_PATH" && -f "$PWA_ALT_HOME_TEMPLATE_PATH" ]]; then
        echo "$PWA_ALT_HOME_TEMPLATE_PATH"
    else
        echo ""
    fi
}

# 这些变量由主 CLI 与其他 lib 读取，使用“空操作”保持 ShellCheck 安静
: "${PWA_WITH_FRONTEND:-}"
: "${PWA_HOME_TEMPLATE_WARNING:-}"
: "${PWA_ALT_HOME_TEMPLATE_WARNING:-}"
: "${PWA_ALT_HOME_TEMPLATE_PATH:-}"
: "${PWA_HOME_FORCE_TEMPLATE:-}"
: "${PWA_HOME_STORE_IDS:-}"
: "${PWA_NODE_PROVIDER:-}"
