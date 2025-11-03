#!/bin/bash
# Reset Magento storefront to official themes by removing third‑party themes/modules
# Usage: sudo scripts/reset-theme.sh <site> [locale ...]

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must be executed as root (sudo)." >&2
    exit 1
fi

SITE="${1:-}"
if [[ -z "${SITE}" ]]; then
    echo "Usage: sudo $0 <site> [locale ...]" >&2
    exit 1
fi
shift || true

SITE_ROOT="/var/www/${SITE}"
if [[ ! -d "${SITE_ROOT}" || ! -f "${SITE_ROOT}/bin/magento" ]]; then
    echo "Magento installation not found at ${SITE_ROOT}" >&2
    exit 1
fi

RUN_MAGENTO_PHP_STATUS=0

run_as_www_data() {
    local args=("$@")
    local quoted=()
    local arg
    for arg in "${args[@]}"; do
        quoted+=("$(printf "%q" "$arg")")
    done
    sudo -u www-data -H bash -lc "cd '${SITE_ROOT}' && ${quoted[*]}"
}

magento() {
    run_as_www_data php bin/magento "$@"
}

run_magento_php() {
    local script_content="$1"
    local tmpfile
    tmpfile="$(mktemp)"
    cat >"${tmpfile}" <<<"${script_content}"
    chown www-data:www-data "${tmpfile}"
    chmod 640 "${tmpfile}"
    run_as_www_data php "${tmpfile}"
    local rc=$?
    rm -f "${tmpfile}"
    RUN_MAGENTO_PHP_STATUS=${rc}
    return "${rc}"
}

echo "[INFO] Resetting themes for ${SITE_ROOT}"

# Detect locales (unless provided explicitly)
if (( $# > 0 )); then
    LOCALES=("$@")
else
    LOCALE_SCRIPT=$(cat <<'PHP'
<?php
require 'app/bootstrap.php';
use Magento\Framework\App\Bootstrap;
use Magento\Framework\App\Config\ScopeConfigInterface;
use Magento\Store\Model\ScopeInterface;
use Magento\Store\Model\StoreManagerInterface;

$bootstrap = Bootstrap::create(BP, $_SERVER);
$objectManager = $bootstrap->getObjectManager();
$scopeConfig = $objectManager->get(ScopeConfigInterface::class);
$storeManager = $objectManager->get(StoreManagerInterface::class);
$locales = [];
$defaultLocale = (string)$scopeConfig->getValue(
    'general/locale/code',
    ScopeConfigInterface::SCOPE_TYPE_DEFAULT
);
if ($defaultLocale) {
    $locales[$defaultLocale] = true;
}
foreach ($storeManager->getStores() as $store) {
    $locale = (string)$scopeConfig->getValue('general/locale/code', ScopeInterface::SCOPE_STORE, $store->getCode());
    if (!$locale) {
        $locale = $defaultLocale;
    }
    if ($locale) {
        $locales[$locale] = true;
    }
}
if (!$locales) {
    $locales['en_US'] = true;
}
echo implode(PHP_EOL, array_keys($locales));
PHP
    )
    readarray -t LOCALES < <(run_magento_php "${LOCALE_SCRIPT}")
    if (( RUN_MAGENTO_PHP_STATUS != 0 )); then
        echo "[ERROR] 读取语言配置失败，请检查 Magento 日志" >&2
        exit 1
    fi
    tmp_locales=()
    for locale in "${LOCALES[@]}"; do
        [[ -n "${locale}" ]] && tmp_locales+=("${locale}")
    done
    LOCALES=("${tmp_locales[@]}")
    if (( ${#LOCALES[@]} == 0 )); then
        echo "[WARN] 未检测到已配置语言，默认使用 en_US"
        LOCALES=("en_US")
    else
        echo "[INFO] Locales: ${LOCALES[*]}"
    fi
fi

# Collect Codazon modules from config.php
MODULE_SCRIPT=$(cat <<'PHP'
<?php
$modules = include 'app/etc/config.php';
$targets = [];
foreach ($modules['modules'] as $name => $status) {
    if (strpos($name, 'Codazon_') === 0 && (int)$status === 1) {
        $targets[] = $name;
    }
}
echo implode(PHP_EOL, $targets);
PHP
)
readarray -t CODAZON_MODULES < <(run_magento_php "${MODULE_SCRIPT}")
if (( RUN_MAGENTO_PHP_STATUS != 0 )); then
    echo "[ERROR] 无法读取 app/etc/config.php 模块配置" >&2
    exit 1
fi
tmp_modules=()
for module in "${CODAZON_MODULES[@]}"; do
    [[ -n "${module}" ]] && tmp_modules+=("${module}")
done
CODAZON_MODULES=("${tmp_modules[@]}")

declare -A MODULES_TO_DISABLE=()
if (( ${#CODAZON_MODULES[@]} > 0 )); then
    for module in "${CODAZON_MODULES[@]}"; do
        MODULES_TO_DISABLE["${module}"]=1
    done
    echo "[INFO] Codazon modules detected: ${CODAZON_MODULES[*]}"
else
    echo "[INFO] No Codazon modules detected in config.php"
fi

# Detect third-party modules that reference Codazon classes/helpers
DEPENDENT_SCAN_SCRIPT=$(cat <<'PHP'
<?php
require 'app/bootstrap.php';
use Magento\Framework\App\Bootstrap;
use Magento\Framework\Component\ComponentRegistrar;

$bootstrap = Bootstrap::create(BP, $_SERVER);
$objectManager = $bootstrap->getObjectManager();
$registrar = $objectManager->get(ComponentRegistrar::class);
$paths = $registrar->getPaths(ComponentRegistrar::MODULE);
$matches = [];
foreach ($paths as $moduleName => $path) {
    if (strpos($path, DIRECTORY_SEPARATOR . 'app' . DIRECTORY_SEPARATOR . 'code' . DIRECTORY_SEPARATOR) === false) {
        continue;
    }
    if (!is_dir($path)) {
        continue;
    }
    $iterator = new \RecursiveIteratorIterator(
        new \RecursiveDirectoryIterator($path, \FilesystemIterator::SKIP_DOTS)
    );
    foreach ($iterator as $file) {
        $extension = strtolower($file->getExtension());
        if (!in_array($extension, ['php', 'phtml', 'xml'], true)) {
            continue;
        }
        $contents = @file_get_contents($file->getPathname());
        if ($contents !== false && strpos($contents, 'Codazon\\') !== false) {
            $matches[$moduleName] = true;
            break;
        }
    }
}
echo implode(PHP_EOL, array_keys($matches));
PHP
)
readarray -t DEPENDENT_MODULES < <(run_magento_php "${DEPENDENT_SCAN_SCRIPT}")
if (( RUN_MAGENTO_PHP_STATUS != 0 )); then
    echo "[ERROR] 扫描引用 Codazon 的模块失败" >&2
    exit 1
fi

for module in "${DEPENDENT_MODULES[@]}"; do
    [[ -z "${module}" ]] && continue
    MODULES_TO_DISABLE["${module}"]=1
done

if (( ${#DEPENDENT_MODULES[@]} > 0 )); then
    echo "[INFO] Modules referencing Codazon detected: ${DEPENDENT_MODULES[*]}"
fi

DISABLE_LIST=("${!MODULES_TO_DISABLE[@]}")
if (( ${#DISABLE_LIST[@]} > 0 )); then
    # shellcheck disable=SC2046
    magento module:disable --clear-static-content --force "${DISABLE_LIST[@]}" || true
    echo "[INFO] Disabled modules: ${DISABLE_LIST[*]}"
else
    echo "[INFO] No Magento modules require disabling."
fi

declare -A VENDORS=()
for module in "${CODAZON_MODULES[@]}"; do
    vendor="${module%%_*}"
    [[ -n "${vendor}" ]] && VENDORS["${vendor}"]=1
done

# Gather custom themes and vendors
THEME_SCAN_SCRIPT=$(cat <<'PHP'
<?php
require 'app/bootstrap.php';
use Magento\Framework\App\Bootstrap;
use Magento\Theme\Model\ResourceModel\Theme\Collection as ThemeCollection;

$bootstrap = Bootstrap::create(BP, $_SERVER);
$objectManager = $bootstrap->getObjectManager();
$collection = $objectManager->create(ThemeCollection::class);
$keep = [
    'frontend/Magento/blank',
    'frontend/Magento/luma',
    'adminhtml/Magento/backend'
];
$themes = [];
foreach ($collection as $theme) {
    $full = $theme->getArea() . '/' . $theme->getThemePath();
    if (!in_array($full, $keep, true)) {
        $themes[$full] = $theme->getThemeId();
    }
}
echo implode(PHP_EOL, array_keys($themes));
PHP
)
readarray -t CUSTOM_THEMES < <(run_magento_php "${THEME_SCAN_SCRIPT}")
if (( RUN_MAGENTO_PHP_STATUS != 0 )); then
    echo "[ERROR] 无法列出 Magento 主题，请确认数据库连接正常" >&2
    exit 1
fi
tmp_themes=()
for theme in "${CUSTOM_THEMES[@]}"; do
    [[ -n "${theme}" ]] && tmp_themes+=("${theme}")
done
CUSTOM_THEMES=("${tmp_themes[@]}")

if (( ${#CUSTOM_THEMES[@]} == 0 )); then
    echo "[INFO] No custom frontend themes found; skipping theme removal."
fi

for theme in "${CUSTOM_THEMES[@]}"; do
    IFS='/' read -r _ vendor _ <<<"${theme}"
    [[ -n "${vendor:-}" ]] && VENDORS["${vendor}"]=1
done

if (( ${#VENDORS[@]} > 0 )); then
    echo "[INFO] Detected custom theme vendors: ${!VENDORS[*]}"
fi

# Update database configuration (remove theme references, reset Codazon attributes)
DB_CLEAN_SCRIPT=$(cat <<'PHP'
<?php
require 'app/bootstrap.php';
use Magento\Framework\App\Bootstrap;
use Magento\Framework\App\ResourceConnection;
use Magento\Catalog\Model\CategoryRepository;
use Magento\Store\Model\StoreManagerInterface;
use Magento\Framework\App\State;

$bootstrap = Bootstrap::create(BP, $_SERVER);
$objectManager = $bootstrap->getObjectManager();
$resource = $objectManager->get(ResourceConnection::class);
$connection = $resource->getConnection();

$configTable = $resource->getTableName('core_config_data');
$connection->delete($configTable, ['path LIKE ?' => 'design/theme/%']);
$connection->delete($configTable, ['value LIKE ?' => '%Codazon%']);
$connection->delete($configTable, ['path LIKE ?' => 'codazon/%']);

$themeTable = $resource->getTableName('theme');
$connection->delete($themeTable, ['code LIKE ?' => 'Codazon/%']);

$setupModuleTable = $resource->getTableName('setup_module');
$connection->delete($setupModuleTable, ['module LIKE ?' => 'Codazon\_%']);

$categoryAttrTable = $resource->getTableName('catalog_eav_attribute');
$connection->update(
    $categoryAttrTable,
    ['attribute_id' => null],
    ['frontend_input_renderer LIKE ?' => 'Codazon\_%']
);

foreach (['backend_model','frontend_model','source_model'] as $field) {
    $connection->update(
        $resource->getTableName('eav_attribute'),
        [$field => null],
        [$field . ' LIKE ?' => 'Codazon\\%']
    );
}

try {
    $gridTable = $resource->getTableName('design_config_grid');
    if ($connection->isTableExists($gridTable)) {
        $connection->truncateTable($gridTable);
    }
} catch (\Zend_Db_Exception $e) {
    // ignore
}
?>
PHP
)
run_magento_php "${DB_CLEAN_SCRIPT}"
if (( RUN_MAGENTO_PHP_STATUS != 0 )); then
    echo "[ERROR] 主题相关数据库清理失败，请查看 ${SITE_ROOT}/var/log/system.log" >&2
    exit 1
fi

# Remove vendor directories
for vendor in "${!VENDORS[@]}"; do
    rm -rf "${SITE_ROOT}/app/code/${vendor}" \
           "${SITE_ROOT}/app/design/frontend/${vendor}" \
           "${SITE_ROOT}/app/design/adminhtml/${vendor}"
    lower_vendor="$(printf '%s' "${vendor}" | tr '[:upper:]' '[:lower:]')"
    rm -rf "${SITE_ROOT}/vendor/${lower_vendor}"*
done

# Ensure generated directories are clean
rm -rf "${SITE_ROOT}/pub/static/"* \
       "${SITE_ROOT}/var/view_preprocessed/"* \
       "${SITE_ROOT}/generated/code/"* \
       "${SITE_ROOT}/generated/metadata/"* \
       "${SITE_ROOT}/var/cache/"* \
       "${SITE_ROOT}/var/page_cache/"*

# Run setup upgrade to refresh configuration
if ! magento setup:upgrade; then
    echo "[ERROR] Magento setup:upgrade failed; check ${SITE_ROOT}/var/log/setup.log" >&2
    exit 1
fi

# Recompile DI to regenerate proxies after module removal
if ! magento setup:di:compile; then
    echo "[ERROR] Magento setup:di:compile failed; inspect ${SITE_ROOT}/var/log" >&2
    exit 1
fi

# Deploy official static content
if ! magento setup:static-content:deploy -f \
    --theme Magento/blank \
    --theme Magento/luma \
    --theme Magento/backend \
    "${LOCALES[@]}"; then
    echo "[ERROR] Static content deployment failed; inspect ${SITE_ROOT}/var/log" >&2
    exit 1
fi

if ! magento cache:flush; then
    echo "[WARN] Magento cache flush failed; please flush manually" >&2
fi

# Reload PHP-FPM to clear opcode cache references to removed classes
php_fpm_services=(php-fpm php8.3-fpm php8.2-fpm php8.1-fpm php8.0-fpm)
php_fpm_reloaded=0
if command -v systemctl >/dev/null 2>&1; then
    for svc in "${php_fpm_services[@]}"; do
        if systemctl list-unit-files "${svc}.service" >/dev/null 2>&1; then
            if systemctl is-active --quiet "${svc}"; then
                if systemctl reload "${svc}"; then
                    echo "[INFO] Reloaded ${svc} to refresh PHP opcode cache"
                    php_fpm_reloaded=1
                    break
                fi
            fi
        fi
    done
fi
if (( php_fpm_reloaded == 0 )); then
    echo "[WARN] 未能自动重载 PHP-FPM；如遇缓存旧代码请手动 reload" >&2
fi

echo "[SUCCESS] Custom themes/modules removed. Official themes restored."
