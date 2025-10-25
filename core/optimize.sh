#!/bin/bash
# 优化管理模块
# core/optimize.sh

# Magento 优化配置文件路径
MAGENTO_OPTIMIZE_PILLAR="${SCRIPT_DIR}/salt/pillar/magento-optimize.sls"
MAGENTO_OPTIMIZE_REPORT="/var/lib/saltgoat/reports/magento-optimize-summary.txt"
MAGENTO_SEARCH_ROOTS=("/var/www" "/srv" "/opt/magento")
MAGENTO_SITE_STATUS="unknown"
MAGENTO_SITE_HINT=""
MAGENTO_SITE_ROOT=""
MAGENTO_ENV_PATH=""
MAGENTO_SITE_LABEL=""

escape_yaml_value() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '%s' "$value"
}

magento_env_from_hint() {
    local hint="$1"

    [[ -z "$hint" ]] && return 1

    if [[ -f "$hint" ]]; then
        echo "$hint"
        return 0
    fi

    if [[ -d "$hint" && -f "$hint/app/etc/env.php" ]]; then
        echo "$hint/app/etc/env.php"
        return 0
    fi

    if [[ "$hint" == /* ]]; then
        local candidate="$hint"
        if [[ "${candidate##*/}" != "env.php" ]]; then
            candidate="${hint%/}/app/etc/env.php"
        fi
        if [[ -f "$candidate" ]]; then
            echo "$candidate"
            return 0
        fi
    fi

    local base
    for base in "${MAGENTO_SEARCH_ROOTS[@]}"; do
        if [[ -d "${base}/${hint}" && -f "${base}/${hint}/app/etc/env.php" ]]; then
            echo "${base}/${hint}/app/etc/env.php"
            return 0
        fi
    done

    return 1
}

detect_magento_site() {
    local hint="$1"
    MAGENTO_SITE_HINT="$hint"
    MAGENTO_SITE_STATUS="unknown"
    MAGENTO_SITE_ROOT=""
    MAGENTO_ENV_PATH=""
    MAGENTO_SITE_LABEL=""

    if [[ -n "$hint" ]]; then
        local resolved=""
        if resolved=$(magento_env_from_hint "$hint"); then
            MAGENTO_ENV_PATH="$resolved"
            MAGENTO_SITE_ROOT="$(dirname "$(dirname "$(dirname "$resolved")")")"
            MAGENTO_SITE_LABEL="$(basename "$MAGENTO_SITE_ROOT")"
            MAGENTO_SITE_STATUS="found"
            return 0
        fi

        log_error "未找到 Magento env.php 文件（参数: ${hint})"
        log_info "可以传入站点名称（如 shop01）、站点目录（/var/www/shop01）或 env.php 的绝对路径。"
        MAGENTO_SITE_STATUS="missing"
        return 1
    fi

    local -a search_dirs=()
    local dir
    for dir in "${MAGENTO_SEARCH_ROOTS[@]}"; do
        [[ -d "$dir" ]] && search_dirs+=("$dir")
    done

    if ((${#search_dirs[@]} == 0)); then
        MAGENTO_SITE_STATUS="missing"
        return 0
    fi

    local -a env_candidates=()
    local root
    for root in "${search_dirs[@]}"; do
        while IFS= read -r path; do
            env_candidates+=("$path")
        done < <(find "$root" -maxdepth 5 -path '*/app/etc/env.php' -type f 2>/dev/null | sort -u || true)
    done

    local count=${#env_candidates[@]}
    if (( count == 1 )); then
        MAGENTO_ENV_PATH="${env_candidates[0]}"
        MAGENTO_SITE_ROOT="$(dirname "$(dirname "$(dirname "$MAGENTO_ENV_PATH")")")"
        MAGENTO_SITE_LABEL="$(basename "$MAGENTO_SITE_ROOT")"
        MAGENTO_SITE_STATUS="found"
        return 0
    elif (( count == 0 )); then
        MAGENTO_SITE_STATUS="missing"
        return 0
    fi

    MAGENTO_SITE_STATUS="ambiguous"
    log_warning "检测到多个 Magento 站点:"
    local path
    for path in "${env_candidates[@]}"; do
        log_warning "  - ${path}"
    done
    log_error "请使用 '--site <站点名称|绝对路径|env.php 文件>' 指定目标站点后再运行。"
    return 1
}

update_magento_optimize_pillar() {
    local profile="${1:-auto}"
    local site="${2:-}"
    local env_path="${3:-}"
    local site_root="${4:-}"
    local detection_status="${5:-unknown}"
    local site_hint="${6:-}"

    mkdir -p "${SCRIPT_DIR}/salt/pillar"
    mkdir -p "$(dirname "$MAGENTO_OPTIMIZE_REPORT")"

    cat >"$MAGENTO_OPTIMIZE_PILLAR" <<EOF
magento_optimize:
  profile: "$(escape_yaml_value "$profile")"
  site: "$(escape_yaml_value "$site")"
  site_hint: "$(escape_yaml_value "$site_hint")"
  env_path: "$(escape_yaml_value "$env_path")"
  site_root: "$(escape_yaml_value "$site_root")"
  detection_status: "$(escape_yaml_value "$detection_status")"
  overrides: {}
EOF

    log_info "已更新 Magento 优化配置: profile=${profile:-auto} site=${site:-<none>}"
}

show_magento_optimize_report() {
    if [[ -f "$MAGENTO_OPTIMIZE_REPORT" ]]; then
        log_highlight "Magento 优化报告:"
        cat "$MAGENTO_OPTIMIZE_REPORT"
    else
        log_warning "尚未找到 Magento 优化报告 (期待位置: ${MAGENTO_OPTIMIZE_REPORT})"
    fi
}

# Magento 优化
optimize_magento() {
    local profile="auto"
    local site=""
    local dry_run=false
    local show_results=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                profile="$2"
                shift 2
                ;;
            --site)
                site="$2"
                shift 2
                ;;
            --dry-run|--plan)
                dry_run=true
                shift
                ;;
            --show-results)
                show_results=true
                shift
                ;;
            --help|-h)
                cat <<'USAGE'
用法: saltgoat optimize magento [选项]
  --profile <auto|low|standard|medium|high|enterprise>  指定优化档位 (默认: auto)
  --site <name>                                         可选，记录当前站点
  --dry-run | --plan                                    仅模拟执行，不修改系统
  --show-results                                        优化结束后打印报告
USAGE
                return 0
                ;;
            *)
                log_warning "忽略未知参数: $1"
                shift
                ;;
        esac
    done

    local original_site="$site"
    if ! detect_magento_site "$site"; then
        return 1
    fi

    local display_site="$site"
    if [[ -z "$display_site" && -n "$MAGENTO_SITE_LABEL" ]]; then
        display_site="$MAGENTO_SITE_LABEL"
    fi

    update_magento_optimize_pillar "$profile" "$display_site" "$MAGENTO_ENV_PATH" "$MAGENTO_SITE_ROOT" "$MAGENTO_SITE_STATUS" "$original_site"

    case "$MAGENTO_SITE_STATUS" in
        found)
            log_highlight "Magento 站点: ${display_site:-$MAGENTO_SITE_LABEL} (${MAGENTO_SITE_ROOT})"
            log_info "env.php 路径: ${MAGENTO_ENV_PATH}"
            ;;
        missing)
            log_warning "未检测到 Magento env.php，仍将应用系统级优化。"
            ;;
    esac

    local state_cmd=(salt-call --local state.apply optional.magento-optimization)
    if [[ "$dry_run" == true ]]; then
        log_highlight "以 dry-run 模式执行 Magento 优化 (不做更改)..."
        state_cmd+=("test=True")
    else
        log_info "开始优化 Magento 配置..."
    fi

    "${state_cmd[@]}"

    if [[ "$dry_run" == true ]]; then
        log_success "Magento 优化 dry-run 完成 (未做更改)"
    else
        log_success "Magento 优化完成"
    fi

    if [[ "$show_results" == true ]]; then
        show_magento_optimize_report
    else
        log_info "可使用 '--show-results' 查看最近的优化报告"
    fi
}
