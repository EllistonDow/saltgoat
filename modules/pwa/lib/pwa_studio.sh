#!/bin/bash

ensure_node_yarn() {
    if ! is_true "${PWA_ENSURE_NODE}"; then
        log_info "已跳过 Node.js/Yarn 检查（配置 ensure=false）"
        return
    fi

    local desired="${PWA_NODE_VERSION:-$DEFAULT_NODE_VERSION}"
    local need_node=false

    if command_exists node; then
        local current
        current="$(node --version 2>/dev/null | sed 's/v//')"
        if ! version_ge "$current" "$desired"; then
            log_warning "检测到 Node.js $current，低于期望版本 $desired，将尝试升级。"
            need_node=true
        fi
    else
        need_node=true
    fi

    if [[ "$need_node" == "true" ]]; then
        log_info "安装/升级 Node.js 到 $desired.x ..."
        if ! command_exists curl; then
            log_info "安装 curl ..."
            apt-get update
            apt-get install -y curl
        fi
        curl -fsSL "https://deb.nodesource.com/setup_${desired}.x" | bash -
        apt-get install -y nodejs
    else
        log_success "Node.js 版本满足要求 ($(node --version))"
    fi

    if is_true "${PWA_INSTALL_YARN}"; then
        if command_exists yarn; then
            log_success "Yarn 已安装 ($(yarn --version))"
        else
            log_info "全局安装 Yarn..."
            npm install -g yarn
        fi
    fi
}

ensure_git() {
    if command_exists git; then
        return
    fi
    log_info "安装 git..."
    apt-get update
    apt-get install -y git
}

prepare_pwa_repo() {
    ensure_git
    local dir="$PWA_STUDIO_DIR"
    local repo="$PWA_STUDIO_REPO"
    local branch="${PWA_STUDIO_BRANCH:-develop}"

    if [[ -d "$dir/.git" ]]; then
        log_info "更新 PWA Studio 仓库 (${repo} @ ${branch}) ..."
        sudo -u www-data -H bash -lc "cd '${dir}' && git fetch origin '${branch}' && git reset --hard 'origin/${branch}'"
    else
        local parent
        parent="$(dirname "$dir")"
        mkdir -p "$parent"
        case "${parent%/}/" in
            "${PWA_ROOT%/}/"*)
                chown www-data:www-data "$parent"
                ;;
        esac
        log_info "克隆 PWA Studio 仓库 (${repo} @ ${branch}) ..."
        sudo -u www-data -H bash -lc "git clone --branch '${branch}' '${repo}' '${dir}'"
    fi
}

sync_pwa_overrides() {
    local overrides_dir="${SCRIPT_DIR}/modules/pwa/overrides"
    if [[ ! -d "$overrides_dir" ]]; then
        return
    fi
    log_info "同步 PWA overrides"
    sudo rsync -a --exclude '.git' "${overrides_dir}/" "${PWA_STUDIO_DIR%/}/"
    sudo chown -R www-data:www-data "${PWA_STUDIO_DIR%/}"
}

ensure_saltgoat_extension_workspace() {
    local workspace_src="${SCRIPT_DIR}/modules/pwa/workspaces/saltgoat-venia-extension"
    if [[ ! -d "$workspace_src" ]]; then
        return
    fi

    local workspace_dest="${PWA_STUDIO_DIR%/}/packages/saltgoat-venia-extension"
    log_info "同步 SaltGoat Venia 扩展 workspace"
    sudo -u www-data -H mkdir -p "$(dirname "$workspace_dest")"
    sudo rsync -a "$workspace_src/" "$workspace_dest/"
    sudo chown -R www-data:www-data "$workspace_dest"

    local workspace_status
    workspace_status=$(sudo -u www-data -H python3 "$PWA_HELPER" ensure-workspace \
        --root "$PWA_STUDIO_DIR" \
        --workspace "packages/saltgoat-venia-extension" \
        --dependency "@saltgoat/venia-extension") || workspace_status=""
    if [[ "$workspace_status" == "updated" ]]; then
        log_info "已更新根 package.json workspaces 与依赖映射 (@saltgoat/venia-extension)"
    fi

    ensure_workspace_dependency "${PWA_STUDIO_DIR%/}/packages/venia-ui/package.json" \
        "@saltgoat/venia-extension" "link:../saltgoat-venia-extension"
    ensure_workspace_dependency "${PWA_STUDIO_DIR%/}/packages/venia-concept/package.json" \
        "@saltgoat/venia-extension" "link:../saltgoat-venia-extension"
}

ensure_sample_payment_extensions() {
    if ! is_true "${PWA_WITH_FRONTEND:-false}"; then
        return
    fi

    if [[ -n "${PWA_STUDIO_SAMPLE_PAYMENT_REPO:-}" ]]; then
        log_info "克隆示例支付扩展 (${PWA_STUDIO_SAMPLE_PAYMENT_REPO})"
        sudo -u www-data -H bash -lc "cd '${PWA_STUDIO_DIR}' && yarn add ${PWA_STUDIO_SAMPLE_PAYMENT_REPO}"
    fi
}

ensure_workspace_dependency() {
    local package_json="$1"
    local dep="$2"
    local value="$3"
    if [[ ! -f "$package_json" ]]; then
        return
    fi
    sudo -u www-data -H python3 "$PWA_HELPER" ensure-workspace-dependency --file "$package_json" --package "$dep" --value "$value"
}

cleanup_package_lock() {
    local pkg="${1:-${PWA_STUDIO_DIR%/}/package-lock.json}"
    if [[ -f "$pkg" ]]; then
        log_info "移除遗留 package-lock.json (${pkg})"
        rm -f "$pkg"
    fi
}

ensure_package_json_field() {
    local pkg="$1"
    local field="$2"
    local value="$3"
    sudo -u www-data -H python3 "$PWA_HELPER" ensure-package-field --file "$pkg" --field "$field" --value "$value"
}

ensure_package_json_dev_dependency() {
    local pkg="$1"
    local dep="$2"
    local version="$3"
    sudo -u www-data -H python3 "$PWA_HELPER" ensure-package-dev-dependency --file "$pkg" --package "$dep" --version "$version"
}

ensure_package_json_dependency() {
    local pkg="$1"
    local dep="$2"
    local version="$3"
    sudo -u www-data -H python3 "$PWA_HELPER" ensure-package-dependency --file "$pkg" --package "$dep" --version "$version"
}

remove_package_json_field() {
    local pkg="$1"
    local field="$2"
    sudo -u www-data -H python3 "$PWA_HELPER" remove-package-field --file "$pkg" --field "$field"
}

remove_package_json_dependency() {
    local pkg="$1"
    local dep="$2"
    sudo -u www-data -H python3 "$PWA_HELPER" remove-package-dependency --file "$pkg" --package "$dep"
}

prune_unused_pwa_extensions() {
    sudo -u www-data -H python3 "$PWA_HELPER" prune-extensions --root "$PWA_STUDIO_DIR"
}

ensure_pwa_root_peer_dependencies() {
    local pkg="${PWA_STUDIO_DIR%/}/package.json"
    sudo -u www-data -H python3 "$PWA_HELPER" ensure-peer-deps --file "$pkg"
}

check_single_react_version() {
    local result
    result=$(sudo -u www-data -H python3 "$PWA_HELPER" react-version-check --root "$PWA_STUDIO_DIR" 2>/dev/null || true)
    if [[ -n "$result" ]]; then
        log_info "$result"
    fi
}

graphql_ping() {
    local endpoint="$1"
    python3 "$PWA_HELPER" graphql-ping --endpoint "$endpoint"
}

check_pwa_port() {
    local port="$1"
    local host="$2"
    python3 "$PWA_HELPER" port-check --port "$port" --host "$host"
}

apply_mos_graphql_fixes() {
    local graphql_files
    graphql_files=$(sudo -u www-data -H python3 "$PWA_HELPER" list-graphql-files --root "$PWA_STUDIO_DIR" 2>/dev/null || true)
    while IFS= read -r gql_file; do
        [[ -z "$gql_file" ]] && continue
        sudo -u www-data -H python3 "$PWA_HELPER" sanitize-graphql --file "$gql_file" >/dev/null
    done <<<"$graphql_files"

    local orders_component
    orders_component="${PWA_STUDIO_DIR%/}/packages/venia-ui/lib/components/AccountInformationPage/orders.js"
    if [[ -f "$orders_component" ]]; then
        sudo -u www-data -H python3 "$PWA_HELPER" sanitize-orders --file "$orders_component" >/dev/null
    fi

    local payment_info
    payment_info="${PWA_STUDIO_DIR%/}/packages/venia-ui/lib/components/CheckoutPage/PaymentInformation/paymentInformation.js"
    if [[ -f "$payment_info" ]]; then
        sudo -u www-data -H python3 "$PWA_HELPER" sanitize-payment --file "$payment_info" >/dev/null
    fi

    local order_history_files
    order_history_files=$(sudo -u www-data -H find "${PWA_STUDIO_DIR%/}/packages" -name 'orderHistoryPage.gql.js' -print0 2>/dev/null || true)
    if [[ -n "$order_history_files" ]]; then
        while IFS= read -r -d '' file; do
            local patch_status
            patch_status=$(sudo -u www-data -H python3 "$PWA_HELPER" fix-order-history --file "$file" 2>/dev/null || true)
            if [[ "$patch_status" == "patched" ]]; then
                local rel_path
                rel_path="${file#"${PWA_STUDIO_DIR%/}"/}"
                log_info "修复订单历史 GraphQL 查询字段 (state→status): ${rel_path}"
            fi
        done <<<"$order_history_files"
    fi

    local cart_fragment
    cart_fragment="${PWA_STUDIO_DIR%/}/packages/peregrine/lib/talons/Header/cartTriggerFragments.gql.js"
    if [[ -f "$cart_fragment" && -n "$(grep -F 'total_summary_quantity_including_config' "$cart_fragment" || true)" ]]; then
        log_info "移除 MOS 不支持的购物车统计字段"
        sudo -u www-data -H python3 "$PWA_HELPER" remove-line --file "$cart_fragment" --contains "total_summary_quantity_including_config" >/dev/null
    fi

    local cart_trigger_hook
    cart_trigger_hook="${PWA_STUDIO_DIR%/}/packages/peregrine/lib/talons/Header/useCartTrigger.js"
    if [[ -f "$cart_trigger_hook" ]]; then
        sudo -u www-data -H python3 "$PWA_HELPER" sanitize-cart-trigger --file "$cart_trigger_hook" >/dev/null
    fi

    local product_detail_talon
    product_detail_talon="${PWA_STUDIO_DIR%/}/packages/peregrine/lib/talons/ProductFullDetail/useProductFullDetail.js"
    if [[ -f "$product_detail_talon" ]]; then
        sudo -u www-data -H python3 "$PWA_HELPER" patch-product-custom-attributes --file "$product_detail_talon" >/dev/null
    fi

    local xp_intercept
    xp_intercept="${PWA_STUDIO_DIR%/}/packages/extensions/experience-platform-connector/intercept.js"
    if [[ -f "$xp_intercept" && -z "$(grep -F 'MAGENTO_EXPERIENCE_PLATFORM_ENABLED' "$xp_intercept" || true)" ]]; then
        log_info "禁用 Experience Platform 扩展（MOS 不支持）"
        sudo -u www-data -H python3 "$PWA_HELPER" add-guard --file "$xp_intercept" --env-var "MAGENTO_EXPERIENCE_PLATFORM_ENABLED" >/dev/null
    fi

    local live_search_intercept
    live_search_intercept="${PWA_STUDIO_DIR%/}/packages/extensions/venia-pwa-live-search/src/targets/intercept.js"
    if [[ -f "$live_search_intercept" && -z "$(grep -F 'MAGENTO_LIVE_SEARCH_ENABLED' "$live_search_intercept" || true)" ]]; then
        log_info "按需禁用 PWA Live Search 扩展"
        sudo -u www-data -H python3 "$PWA_HELPER" add-guard --file "$live_search_intercept" --env-var "MAGENTO_LIVE_SEARCH_ENABLED" >/dev/null
    fi

    local webpack_config
    webpack_config="${PWA_STUDIO_DIR%/}/packages/venia-concept/webpack.config.js"
    if [[ -f "$webpack_config" && -z "$(grep -F 'config.performance.hints = false' "$webpack_config" || true)" ]]; then
        log_info "调整 webpack 配置，禁用性能提示告警"
        sudo -u www-data -H python3 "$PWA_HELPER" tune-webpack --file "$webpack_config" >/dev/null
    fi
}

ensure_magento_graphql_ready() {
    if ! magento_command_exists "config:show"; then
        log_warning "Magento CLI 无法查询配置，跳过 GraphQL 配置验证。"
        return
    fi
    magento_cli "确认 GraphQL endpoint 已开启" "config:set" "graphql/graphqllinks/enable" 1 >/dev/null
}

prepare_yarn_environment() {
    local workdir="$1"
    local cache_dir="$workdir/.cache"
    local yarn_cache="$cache_dir/yarn"
    local yarn_global="$workdir/.yarn-global"
    local npm_cache="$cache_dir/npm"
    local npx_cache="$cache_dir/npx"
    sudo -u www-data -H mkdir -p "$cache_dir" "$yarn_cache" "$yarn_global" "$npm_cache" "$npx_cache"
    chown -R www-data:www-data "$workdir"
}

ensure_inotify_limits() {
    local min_watches="${PWA_INOTIFY_MIN_WATCHES:-524288}"
    local current
    current=$(sysctl -n fs.inotify.max_user_watches 2>/dev/null || echo "")
    if [[ -z "$current" ]]; then
        return
    fi
    if (( current >= min_watches )); then
        return
    fi

    if sysctl -w "fs.inotify.max_user_watches=${min_watches}" >/dev/null 2>&1; then
        log_info "提升 fs.inotify.max_user_watches=${min_watches}"
        local sysctl_dir="/etc/sysctl.d"
        local sysctl_conf="${sysctl_dir}/99-saltgoat-pwa.conf"
        if [[ -d "$sysctl_dir" && -w "$sysctl_dir" ]]; then
            if [[ ! -f "$sysctl_conf" ]] || ! grep -Fq -- 'fs.inotify.max_user_watches' "$sysctl_conf" 2>/dev/null; then
                printf "fs.inotify.max_user_watches = %s\n" "$min_watches" >>"$sysctl_conf"
                log_info "已写入 ${sysctl_conf}，重启后自动恢复该限制。"
            fi
        fi
    else
        log_warning "无法提升 fs.inotify.max_user_watches=${min_watches}，如需 yarn watch 请手动调整。"
    fi
}

run_yarn_task() {
    local command="$1"
    if [[ -z "$command" ]]; then
        return
    fi
    ensure_inotify_limits
    prepare_yarn_environment "$PWA_STUDIO_DIR"
    local yarn_cache_dir="${PWA_STUDIO_DIR}/.cache/yarn"
    local yarn_global_dir="${PWA_STUDIO_DIR}/.yarn-global"
    local npm_cache_dir="${PWA_STUDIO_DIR}/.cache/npm"
    local npx_cache_dir="${PWA_STUDIO_DIR}/.cache/npx"
    sudo -u www-data -H bash -lc "cd '$PWA_STUDIO_DIR' && export HOME='$PWA_STUDIO_DIR' && export YARN_CACHE_FOLDER='$yarn_cache_dir' && export YARN_GLOBAL_FOLDER='$yarn_global_dir' && export npm_config_cache='$npm_cache_dir' && export NPX_CACHE_DIR='$npx_cache_dir' && $command"
}

build_pwa_frontend() {
    sync_pwa_overrides
    log_highlight "构建 PWA Studio ..."
    run_yarn_task "${PWA_STUDIO_INSTALL_COMMAND:-yarn install}"
    run_yarn_task "${PWA_STUDIO_BUILD_COMMAND:-yarn build}"
    log_success "PWA build 完成，产物位于 packages/venia-concept/dist"
}

ensure_pwa_service() {
    local service_unit
    service_unit="$(pwa_service_unit)"

    local port="${PWA_STUDIO_PORT:-$DEFAULT_PWA_PORT}"
    local host="${PWA_STUDIO_BIND:-0.0.0.0}"
    local node_env="${PWA_NODE_ENV:-production}"
    local venia_pkg_dir="${PWA_STUDIO_DIR%/}"
    local serve_cmd="${PWA_STUDIO_SERVE_COMMAND:-/usr/bin/env yarn workspace @magento/venia-concept run start}"

    cat <<SERVICE >/etc/systemd/system/"${service_unit}"
[Unit]
Description=SaltGoat PWA Frontend (${PWA_SITE_NAME})
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=${venia_pkg_dir}
Environment=NODE_ENV=${node_env}
Environment=PORT=${port}
Environment=HOST=${host}
Environment=HOME=${PWA_STUDIO_DIR}
ExecStart=${serve_cmd}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

    systemctl daemon-reload
    systemctl enable --now "$service_unit"
    log_success "已启用 systemd 服务 ${service_unit}"
}
