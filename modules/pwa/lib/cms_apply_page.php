<?php
declare(strict_types=1);

use Magento\Cms\Model\PageFactory;
use Magento\Framework\App\Bootstrap;
use Magento\Framework\App\State;
use Magento\Framework\Exception\LocalizedException;

$options = getopt('', [
    'magento-root:',
    'identifier:',
    'title:',
    'template:',
    'stores:',
    'force',
]);

$magentoRoot = $options['magento-root'] ?? null;
$identifier = trim((string)($options['identifier'] ?? ''));
$title = trim((string)($options['title'] ?? ''));
$templatePath = $options['template'] ?? null;
$storesRaw = $options['stores'] ?? '0';
$forceUpdate = array_key_exists('force', $options);

if (!$magentoRoot || !$identifier || !$templatePath) {
    fwrite(STDERR, "Missing required arguments.\n");
    exit(1);
}

$magentoRoot = rtrim($magentoRoot, '/');
$templatePath = realpath($templatePath);

if (!$templatePath || !is_file($templatePath)) {
    fwrite(STDERR, "Template file not found: {$templatePath}\n");
    exit(1);
}

$content = file_get_contents($templatePath);
if ($content === false) {
    fwrite(STDERR, "Unable to read template: {$templatePath}\n");
    exit(1);
}
$content = trim($content);
$signature = substr(hash('sha256', $content), 0, 16);
$versionStamp = sprintf("\n<!-- sg-sync:%s -->", $signature);
$contentWithStamp = $content . $versionStamp;

$stores = array_values(array_filter(array_map(static function ($value) {
    $value = trim($value);
    return $value === '' ? null : (int)$value;
}, preg_split('/\s*,\s*/', (string)$storesRaw) ?: [])));
if (!$stores) {
    $stores = [0];
}

$bootstrapPath = $magentoRoot . '/app/bootstrap.php';
if (!is_file($bootstrapPath)) {
    fwrite(STDERR, "Magento bootstrap not found under {$magentoRoot}\n");
    exit(1);
}

require $bootstrapPath;

$_SERVER['SCRIPT_FILENAME'] = $magentoRoot . '/index.php';
$_SERVER['SERVER_NAME'] = $_SERVER['SERVER_NAME'] ?? 'localhost';

$bootstrap = Bootstrap::create($magentoRoot, $_SERVER);
$objectManager = $bootstrap->getObjectManager();

/** @var State $appState */
$appState = $objectManager->get(State::class);
try {
    $appState->setAreaCode('adminhtml');
} catch (LocalizedException $e) {
    // area code already set – safe to ignore.
}

/** @var PageFactory $pageFactory */
$pageFactory = $objectManager->get(PageFactory::class);
$page = $pageFactory->create();
$page->setStoreId(0)->load($identifier, 'identifier');
$wasExisting = (bool)$page->getId();

$page->setIdentifier($identifier);
$page->setTitle($title !== '' ? $title : $identifier);
$page->setContent($contentWithStamp);
$page->setIsActive(1);
$page->setPageLayout('1column');
$page->setStores($stores);

$originalContent = trim((string)$page->getOrigData('content'));
$finalContent = trim($contentWithStamp);

if ($wasExisting && !$forceUpdate && $originalContent === $finalContent) {
    echo "unchanged\n";
    exit(0);
}

$page->save();

/** @var \Magento\Framework\App\ResourceConnection $resource */
$resource = $objectManager->get(\Magento\Framework\App\ResourceConnection::class);
$connection = $resource->getConnection();
$tableName = $resource->getTableName('cms_page');
$connection->update(
    $tableName,
    ['content' => $contentWithStamp],
    ['page_id = ?' => (int)$page->getId()]
);

echo $wasExisting ? "updated\n" : "created\n";
