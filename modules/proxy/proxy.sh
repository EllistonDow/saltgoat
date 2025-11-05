#!/bin/bash
# Proxy manager helper (Docker-based Nginx Proxy Manager)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"

proxy_usage() {
    cat <<'EOF'
用法: saltgoat proxy <command>

命令:
  install                  安装 Docker + Nginx Proxy Manager (默认监听 8080/8443/9181，可通过 Pillar docker:npm 调整)
  status                   查看 docker compose ps
  add <domain>             为域名生成宿主机 Nginx 透传配置 -> NPM (HTTP)，用于在 NPM 内配置后端
  remove <domain>          删除对应透传配置
  list                     列出所有托管域名

说明:
  1. 运行 "saltgoat proxy install" 后，面板地址 https://<主机>:9181，初始账户 admin@example.com / changeme。
  2. 需要暴露服务时：
     a) 执行 "saltgoat proxy add example.com"（写入宿主 Nginx -> NPM）。
     b) 登录 NPM，在 Proxy Hosts 里配置 example.com -> 目标服务 (http://127.0.0.1:9000)。
     c) 如需 HTTPS，请另行申请证书并在 server 块中引用，或将域名直接指向 NPM 80/443。
EOF
}

pillar_get_value() {
    local key="$1"
    local default="${2:-}"
    local result
    result=$(sudo salt-call --local --out=json pillar.get "$key" 2>/dev/null | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("local",""))' 2>/dev/null || true)
    if [[ -n "$result" && "$result" != "None" ]]; then
        echo "$result"
    else
        echo "$default"
    fi
}

open_ufw_ports() {
    if ! command -v ufw >/dev/null 2>&1; then
        return
    fi
    if ! sudo ufw status | grep -qi "Status: active"; then
        return
    fi
    local http_port="$1"
    local https_port="$2"
    local admin_port="$3"
    for port in "$http_port" "$https_port" "$admin_port"; do
        if [[ -n "$port" && "$port" != "0" ]]; then
            sudo ufw status | grep -q "${port}/tcp" || sudo ufw allow "${port}/tcp" >/dev/null 2>&1
        fi
    done
}

ensure_docker_npm() {
    log_highlight "部署 Docker + Nginx Proxy Manager..."
    sudo salt-call --local state.apply optional.docker >/dev/null 2>&1 || log_warning "Docker state 执行失败，请检查日志"
    sudo salt-call --local state.apply optional.docker-npm >/dev/null 2>&1 || log_warning "NPM state 执行失败，请检查日志"
    local admin_port
    local http_port
    local https_port
    admin_port=$(pillar_get_value "docker:npm:admin_port" "9181")
    http_port=$(pillar_get_value "docker:npm:http_port" "8080")
    https_port=$(pillar_get_value "docker:npm:https_port" "8443")
    open_ufw_ports "$http_port" "$https_port" "$admin_port"
    log_success "Docker + NPM 已启动，如开放防火墙可访问 https://$(hostname -f):${admin_port}"
}

proxy_conf_dir=/etc/nginx/conf.d
legacy_proxy_dir=/etc/nginx/conf.d/proxy
npm_letsencrypt=/opt/saltgoat/docker/npm/data/letsencrypt

detect_cert_paths() {
    local domain="$1"
    local host_cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    local host_key="/etc/letsencrypt/live/${domain}/privkey.pem"
    if [[ -f "$host_cert" && -f "$host_key" ]]; then
        printf '%s %s' "$host_cert" "$host_key"
        return
    fi
    if [[ -d "$npm_letsencrypt/renewal" ]]; then
        local conf name cert key
        while IFS= read -r -d '' conf; do
            if grep -q "$domain" "$conf"; then
                name="$(basename "$conf" .conf)"
                cert="${npm_letsencrypt}/live/${name}/fullchain.pem"
                key="${npm_letsencrypt}/live/${name}/privkey.pem"
                if [[ -f "$cert" && -f "$key" ]]; then
                    printf '%s %s' "$cert" "$key"
                    return
                fi
            fi
        done < <(find "$npm_letsencrypt/renewal" -maxdepth 1 -type f -name '*.conf' -print0 2>/dev/null)
    fi
    printf ' '
}

write_proxy_config() {
    local domain="$1"
    local port
    port=$(pillar_get_value "docker:npm:http_port" "8080")
    local file="${proxy_conf_dir}/proxy-${domain}.conf"
    local legacy_file="${legacy_proxy_dir}/${domain}.conf"
    sudo mkdir -p "$proxy_conf_dir"
    if [[ -f "$legacy_file" ]]; then
        sudo rm -f "$legacy_file"
    fi
    sudo tee "$file" >/dev/null <<EOF
server {
    listen 80;
    server_name ${domain};

    location /.well-known/acme-challenge/ {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:${port};
    }

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:${port};
    }
}
EOF
    local cert key
    read -r cert key <<<"$(detect_cert_paths "$domain")"
    if [[ -n "$cert" && -n "$key" ]]; then
        sudo tee -a "$file" >/dev/null <<EOF

server {
    listen 443 ssl http2;
    server_name ${domain};
    ssl_certificate ${cert};
    ssl_certificate_key ${key};
    include /etc/nginx/snippets/ssl.conf;

    location /.well-known/acme-challenge/ {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:${port};
    }

    location / {
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_pass http://127.0.0.1:${port};
    }
}
EOF
    else
        log_warning "未发现 ${domain} 的证书，暂未生成 443 server。待证书就绪后重新运行 'saltgoat proxy add ${domain}'。"
    fi
    sudo systemctl reload nginx || log_warning "nginx reload 失败，请手动检查"
    log_success "域名 ${domain} 已透传至 NPM (127.0.0.1:${port})"
}

remove_proxy_config() {
    local domain="$1"
    local file="${proxy_conf_dir}/proxy-${domain}.conf"
    local legacy_file="${legacy_proxy_dir}/${domain}.conf"
    local removed=false
    if [[ -f "$file" ]]; then
        sudo rm -f "$file"
        removed=true
    fi
    if [[ -f "$legacy_file" ]]; then
        sudo rm -f "$legacy_file"
        removed=true
    fi
    if [[ "$removed" == true ]]; then
        sudo systemctl reload nginx || log_warning "nginx reload 失败，请手动检查"
        log_success "已移除 $domain 透传配置"
    else
        log_warning "未找到 $domain 配置文件"
    fi
}

proxy_handler() {
    local action="${1:-help}"
    shift || true
    case "$action" in
        install)
            ensure_docker_npm
            ;;
        status)
            (cd /opt/saltgoat/docker/npm && sudo docker compose ps)
            ;;
        add)
            local domain="${1:-}"
            if [[ -z "$domain" ]]; then
                log_error "用法: saltgoat proxy add <domain>"
                exit 1
            fi
            write_proxy_config "$domain"
            ;;
        remove)
            local domain="${1:-}"
            if [[ -z "$domain" ]]; then
                log_error "用法: saltgoat proxy remove <domain>"
                exit 1
            fi
            remove_proxy_config "$domain"
            ;;
        list)
            ls ${proxy_conf_dir} 2>/dev/null || echo "<none>"
            ;;
        help|*)
            proxy_usage
            ;;
    esac
}
