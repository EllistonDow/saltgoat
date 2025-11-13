#!/bin/bash
# PWA OnePage 生成脚本

set -euo pipefail

: "${SCRIPT_DIR:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/logger.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/utils.sh"

PWA_ONEPAGE_BASE="/var/www/pwa-onepage"
PWA_ONEPAGE_DEFAULT_EMAIL="ops@tattoogoat.com"
PWA_ONEPAGE_DEFAULT_TAGLINE="Engineered precision for tattoo artists."

pwa_onepage_usage() {
    cat <<'EOF'
用法:
  saltgoat pwa create onepage --product "<product name>" --domain example.com [选项]

必需参数:
  --product <name>    产品名称（用于页面文案、目录 slug）
  --domain <domain>   访问域名，例如 pwa-product1.magento.tattoogoat.com

可选参数:
  --tagline <text>    英文副标题，默认："Engineered precision for tattoo artists."
  --email <addr>      申请/生成 SSL 时使用的邮箱，默认 ops@tattoogoat.com
  --output-dir <dir>  页面根目录基路径（默认 /var/www/pwa-onepage）
  --force             若目录或 Nginx 站点已存在则覆盖
  --help              显示当前帮助

示例:
  sudo saltgoat pwa create onepage \
      --product "Nebula Flux Rotary System" \
      --domain pwa-product1.magento.tattoogoat.com \
      --tagline "Modern rotary kit for bold studios"
EOF
}

pwa_onepage_handler() {
    local subcommand="${1:-}"
    case "$subcommand" in
        ""|"--help"|"-h")
            pwa_onepage_usage
            ;;
        "onepage")
            shift
            pwa_create_onepage "$@"
            ;;
        *)
            log_error "未知的 onepage 子命令: ${subcommand}"
            pwa_onepage_usage
            exit 1
            ;;
    esac
}

sanitize_slug() {
    local name="$1"
    local slug
    slug="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g')"
    if [[ -z "$slug" ]]; then
        slug="onepage-product"
    fi
    echo "$slug"
}

ensure_cmd() {
    local cmd="$1"
    if ! command_exists "$cmd"; then
        log_error "缺少命令: ${cmd}"
        exit 1
    fi
}

create_onepage_files() {
    local dir="$1"
    local product="$2"
    local tagline="$3"
    local domain="$4"

    mkdir -p "${dir}/assets"

    cat > "${dir}/assets/product-diagram.svg" <<'SVG'
<svg width="360" height="220" viewBox="0 0 360 220" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="penGradient" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop stop-color="#7c3aed" offset="0%"/>
      <stop stop-color="#38bdf8" offset="100%"/>
    </linearGradient>
  </defs>
  <rect x="20" y="60" width="320" height="60" rx="30" fill="url(#penGradient)" opacity="0.85"/>
  <rect x="40" y="90" width="280" height="18" rx="9" fill="#0f172a" opacity="0.65"/>
  <circle cx="50" cy="100" r="6" fill="#38bdf8"/>
  <circle cx="80" cy="100" r="6" fill="#7c3aed"/>
  <circle cx="110" cy="100" r="6" fill="#f97316"/>
  <rect x="150" y="40" width="140" height="20" rx="10" fill="#1f2937" opacity="0.4"/>
  <path d="M40,150 C120,190 240,190 320,150" stroke="#38bdf8" stroke-width="3" fill="none" opacity="0.5"/>
  <text x="30" y="200" fill="#94a3b8" font-size="12" font-family="Inter, Helvetica Neue, Arial, sans-serif">TattooGoat OnePage Diagram</text>
</svg>
SVG

    cat > "${dir}/index.html" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${product} · TattooGoat</title>
  <meta name="description" content="${product} — ${tagline}" />
  <link rel="preconnect" href="https://images.unsplash.com" />
  <style>
    :root {
      --bg: #f1f5f9;
      --text: #0f172a;
      --muted: #475569;
      --card: rgba(255,255,255,0.92);
      --border: rgba(15,23,42,0.1);
      --accent: #7c3aed;
      --accent-strong: #38bdf8;
      --cta-text: #fff;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #020617;
        --text: #e2e8f0;
        --muted: #94a3b8;
        --card: rgba(2,6,23,0.85);
        --border: rgba(148,163,184,0.15);
        --cta-text: #020617;
      }
    }
    [data-theme="dark"] {
      --bg: #020617;
      --text: #e2e8f0;
      --muted: #94a3b8;
      --card: rgba(2,6,23,0.88);
      --border: rgba(148,163,184,0.2);
      --cta-text: #020617;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: 'Inter','Helvetica Neue',Arial,sans-serif;
      background: var(--bg);
      color: var(--text);
      transition: background 0.4s ease, color 0.4s ease;
    }
    .page-shell {
      max-width: 1200px;
      padding: clamp(32px,4vw,60px) clamp(20px,4vw,48px);
      margin: 0 auto;
      display: flex;
      flex-direction: column;
      gap: clamp(32px,4vw,48px);
    }
    .card {
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 28px;
      padding: clamp(24px,3vw,48px);
      box-shadow: 0 30px 80px rgba(15,23,42,0.25);
    }
    .hero {
      display: grid;
      grid-template-columns: repeat(auto-fit,minmax(280px,1fr));
      gap: clamp(24px,4vw,40px);
      align-items: center;
    }
    h1 { font-size: clamp(2.2rem,5vw,3.4rem); margin: 0 0 16px; }
    p { line-height: 1.6; color: var(--muted); margin: 0 0 16px; }
    .actions { display: flex; flex-wrap: wrap; gap: 12px; }
    .btn {
      border-radius: 999px;
      padding: 14px 28px;
      font-weight: 600;
      border: none;
      cursor: pointer;
      transition: transform 0.2s ease, box-shadow 0.2s ease;
      text-decoration: none;
    }
    .btn-primary {
      background-image: linear-gradient(120deg,var(--accent),var(--accent-strong));
      color: var(--cta-text);
      box-shadow: 0 18px 36px rgba(56,189,248,0.35);
    }
    .btn-secondary {
      border: 1px solid var(--border);
      color: var(--text);
      background: transparent;
    }
    .btn:hover { transform: translateY(-2px); }
    .theme-toggle {
      margin-left: auto;
      border: 1px solid var(--border);
      border-radius: 999px;
      padding: 6px 16px;
      font-size: 0.85rem;
      background: transparent;
      color: var(--text);
      cursor: pointer;
    }
    .metrics {
      margin-top: 18px;
      display: grid;
      grid-template-columns: repeat(auto-fit,minmax(140px,1fr));
      gap: 14px;
    }
    .metric {
      background: rgba(56,189,248,0.08);
      border-radius: 20px;
      padding: 18px;
      border: 1px solid rgba(56,189,248,0.2);
    }
    .metric strong { display:block; font-size:1.8rem; }
    .media {
      position: relative;
      border-radius: 32px;
      overflow: hidden;
      min-height: 320px;
    }
    .media img {
      width: 100%;
      height: 100%;
      object-fit: cover;
      display: block;
    }
    .media::after {
      content:"";
      position:absolute;
      inset:0;
      background: linear-gradient(180deg,rgba(0,0,0,0) 40%,rgba(0,0,0,0.75));
    }
    .media-caption {
      position:absolute;
      bottom:22px;
      left:24px;
      right:24px;
      z-index:1;
      color:#fff;
    }
    .section-heading {
      text-transform: uppercase;
      letter-spacing: 0.38em;
      font-size: 0.82rem;
      color: var(--muted);
      margin-bottom: 10px;
    }
    .section-title {
      font-size: clamp(1.6rem,3vw,2.4rem);
      margin: 0 0 24px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit,minmax(240px,1fr));
      gap: 18px;
    }
    .feature {
      padding: 20px;
      border-radius: 20px;
      border: 1px solid var(--border);
      background: rgba(124,58,237,0.05);
    }
    .specs {
      display: grid;
      grid-template-columns: repeat(auto-fit,minmax(200px,1fr));
      gap: 16px;
    }
    .specs dl {
      margin: 0;
      border-radius: 20px;
      border: 1px dashed var(--border);
      padding: 16px;
    }
    .specs dt { font-size: 0.8rem; text-transform: uppercase; letter-spacing: 0.3em; color: var(--muted); }
    .specs dd { margin: 8px 0 0; font-size: 1.1rem; }
    .gallery {
      display: grid;
      grid-template-columns: repeat(auto-fit,minmax(200px,1fr));
      gap: 14px;
    }
    .gallery img, .gallery .diagram {
      border-radius: 18px;
      border: 1px solid var(--border);
      width: 100%;
      height: 220px;
      object-fit: cover;
    }
    .diagram img { width: 100%; height: 100%; object-fit: cover; }
    .cta {
      text-align: center;
    }
    .cta h2 { margin: 0 0 12px; }
    footer {
      text-align: center;
      font-size: 0.85rem;
      color: var(--muted);
    }
  </style>
</head>
<body>
  <div class="page-shell">
    <div style="display:flex;gap:12px;align-items:center;">
      <div>
        <strong>TattooGoat Labs</strong><br/>
        <span style="font-size:0.9rem;color:var(--muted);">${domain}</span>
      </div>
      <button class="theme-toggle" data-theme-toggle>Toggle Theme</button>
    </div>

    <section class="card hero">
      <div>
        <span class="section-heading">Hero Product</span>
        <h1>${product}</h1>
        <p>${tagline}</p>
        <div class="actions">
          <a class="btn btn-primary" href="https://${domain}/#buy">Buy ${product}</a>
          <a class="btn btn-secondary" href="https://${domain}/specs">Technical Specs</a>
        </div>
        <div class="metrics">
          <div class="metric">
            <strong>4.2 g</strong>
            <span>Low vibration</span>
          </div>
          <div class="metric">
            <strong>12 hrs</strong>
            <span>Battery runtime</span>
          </div>
          <div class="metric">
            <strong>IP54</strong>
            <span>Studio ready</span>
          </div>
        </div>
      </div>
      <div class="media">
        <img src="https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=1600&q=80" alt="${product} showcase" />
        <div class="media-caption">
          <span>Behind the scenes</span>
          <strong>Prototype lab · TattooGoat Supply Chain</strong>
        </div>
      </div>
    </section>

    <section class="card">
      <span class="section-heading">Why Artists Switch</span>
      <h2 class="section-title">Crafted for modern studios</h2>
      <div class="grid">
        <article class="feature">
          <h3>Balanced rotary drive</h3>
          <p>Custom-tuned coreless motor with smart torque sensing keeps every stroke consistent, even on large saturation work.</p>
        </article>
        <article class="feature">
          <h3>Smart cartridge routing</h3>
          <p>Rapid-swap bay seals pigments and routes ink waste to disposable chambers for faster sanitation.</p>
        </article>
        <article class="feature">
          <h3>Studio telemetry</h3>
          <p>BLE + NFC allow instant pairing with TattooGoat dashboards to log duty cycles, voltage, and needle pairings.</p>
        </article>
      </div>
    </section>

    <section class="card">
      <span class="section-heading">Specifications</span>
      <h2 class="section-title">Built for premium results</h2>
      <div class="specs">
        <dl>
          <dt>Drive System</dt>
          <dd>Precision rotary · 3.5 mm stroke</dd>
        </dl>
        <dl>
          <dt>Shell</dt>
          <dd>Aircraft-grade aluminum w/ ceramic coat</dd>
        </dl>
        <dl>
          <dt>Power</dt>
          <dd>USB-C 30W fast charge · Wireless pedal</dd>
        </dl>
        <dl>
          <dt>Care</dt>
          <dd>Sterile wipes safe · Modular seals</dd>
        </dl>
      </div>
    </section>

    <section class="card">
      <span class="section-heading">Gallery</span>
      <h2 class="section-title">Designed to impress clients & artists</h2>
      <div class="gallery">
        <img src="https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=800&q=80" alt="${product} gallery 1" />
        <img src="https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?auto=format&fit=crop&w=800&q=80" alt="${product} gallery 2" />
        <div class="diagram">
          <img src="assets/product-diagram.svg" alt="${product} diagram" />
        </div>
        <img src="https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=800&q=80" alt="${product} gallery 3" />
      </div>
    </section>

    <section class="card cta" id="buy">
      <span class="section-heading">Ready to deploy</span>
      <h2>Ship ${product} directly to your studio</h2>
      <p>Available exclusively via ${domain}. Bulk pricing, studio onboarding, and global logistics supported.</p>
      <div class="actions" style="justify-content:center;">
        <a class="btn btn-primary" href="https://${domain}/checkout">Preorder now</a>
        <a class="btn btn-secondary" href="mailto:sales@tattoogoat.com?subject=${product}%20Inquiry">Talk to supply concierge</a>
      </div>
    </section>

    <footer>
      &copy; $(date +%Y) TattooGoat PWA Microsites · ${domain}
    </footer>
  </div>

  <script>
    (function() {
      const toggle = document.querySelector('[data-theme-toggle]');
      const root = document.documentElement;
      const saved = localStorage.getItem('onepage-theme');
      if (saved) {
        root.setAttribute('data-theme', saved);
      }
      toggle?.addEventListener('click', () => {
        const current = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        root.setAttribute('data-theme', current);
        localStorage.setItem('onepage-theme', current);
      });
    })();
  </script>
</body>
</html>
EOF
}

create_self_signed_cert() {
    local domain="$1"
    local email="$2"
    local cert_dir="/etc/nginx/ssl"
    local cert_path="${cert_dir}/${domain}.crt"
    local key_path="${cert_dir}/${domain}.key"

    mkdir -p "$cert_dir"

    if [[ -f "$cert_path" && -f "$key_path" ]]; then
        return 0
    fi

    log_info "生成自签名证书: ${domain}"
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout "$key_path" \
        -out "$cert_path" \
        -subj "/C=US/ST=TattooGoat/L=Studio/O=TattooGoat/CN=${domain}/emailAddress=${email}" >/dev/null 2>&1

    chmod 600 "$key_path"
    chmod 644 "$cert_path"
}

setup_nginx_site() {
    local domain="$1"
    local site_dir="$2"
    local force="$3"

    ensure_cmd nginx

    local available="/etc/nginx/sites-available/${domain}.conf"
    local enabled="/etc/nginx/sites-enabled/${domain}.conf"

    if [[ -f "$available" && "$force" != "true" ]]; then
        log_error "Nginx 站点 ${domain} 已存在，使用 --force 覆盖。"
        exit 1
    fi

    cat > "$available" <<EOF
server {
    listen 80;
    server_name ${domain};
    root ${site_dir};
    index index.html;

    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }
}

server {
    listen 443 ssl;
    server_name ${domain};
    root ${site_dir};
    index index.html;

    ssl_certificate     /etc/nginx/ssl/${domain}.crt;
    ssl_certificate_key /etc/nginx/ssl/${domain}.key;

    location / {
        try_files \$uri \$uri/ /index.html =404;
    }
}
EOF

    ln -sf "$available" "$enabled"

    nginx -t >/dev/null
    systemctl reload nginx
}

pwa_create_onepage() {
    local product=""
    local domain=""
    local tagline="$PWA_ONEPAGE_DEFAULT_TAGLINE"
    local email="$PWA_ONEPAGE_DEFAULT_EMAIL"
    local base_dir="$PWA_ONEPAGE_BASE"
    local force="false"
    local dry_run="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --product)
                product="${2:-}"
                shift 2
                ;;
            --domain)
                domain="${2:-}"
                shift 2
                ;;
            --tagline)
                tagline="${2:-}"
                shift 2
                ;;
            --email)
                email="${2:-}"
                shift 2
                ;;
            --output-dir)
                base_dir="${2:-}"
                shift 2
                ;;
            --force)
                force="true"
                shift
                ;;
            --dry-run|--dryrun|--dry_on|--dry-on)
                dry_run="true"
                shift
                ;;
            --help|-h)
                pwa_onepage_usage
                return 0
                ;;
            *)
                log_error "未知参数: ${1}"
                pwa_onepage_usage
                exit 1
                ;;
        esac
    done

    if [[ -z "$product" || -z "$domain" ]]; then
        log_error "必须提供 --product 与 --domain 参数。"
        pwa_onepage_usage
        exit 1
    fi

    check_permissions "pwa" "create"

    local slug
    slug="$(sanitize_slug "$product")"
    local site_dir="${base_dir%/}/${slug}"

    if [[ -d "$site_dir" && "$force" != "true" ]]; then
        log_error "目录已存在: ${site_dir}，使用 --force 覆盖。"
        exit 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_highlight "(dry-run) 预览 OnePage 流程"
        cat <<EOF
将执行的操作:
1. 创建目录: ${site_dir}
2. 写入 HTML/SVG 模板内容
3. 生成自签名证书: ${domain}
4. 写入 Nginx 站点并 reload: ${domain}
EOF
        return 0
    fi

    mkdir -p "$site_dir"
    create_onepage_files "$site_dir" "$product" "$tagline" "$domain"
    create_self_signed_cert "$domain" "$email"
    setup_nginx_site "$domain" "$site_dir" "$force"

    log_highlight "OnePage 站点已生成"
    cat <<EOF
- 目录: ${site_dir}
- 域名: ${domain}
- 自签名证书: /etc/nginx/ssl/${domain}.crt
- Nginx: /etc/nginx/sites-available/${domain}.conf

可选后续操作:
1. 如需正式证书，可运行 certbot 并更新 Nginx 配置。
2. 将 CDN 或 DNS 指向当前服务器，再执行:
      sudo systemctl reload nginx
3. 页面资源可在 ${site_dir} 内继续扩展（CSS/JS/图片）。
EOF
}
