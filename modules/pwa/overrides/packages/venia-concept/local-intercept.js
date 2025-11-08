const { Targetables } = require('@magento/pwa-buildpack');

const BANK_TRANSFER_COMPONENTS = {
    checkout:
        '@magento/venia-sample-payments-checkmo/src/components/checkmo.js',
    editable:
        '@magento/venia-sample-payments-checkmo/src/components/edit.js',
    summary:
        '@magento/venia-sample-payments-checkmo/src/components/summary.js'
};

const registerBankTransfer = targets => {
    const veniaTargets = targets.of('@magento/venia-ui');

    veniaTargets.checkoutPagePaymentTypes.tap(payments =>
        payments.add({
            paymentCode: 'banktransfer',
            importPath: BANK_TRANSFER_COMPONENTS.checkout
        })
    );

    veniaTargets.editablePaymentTypes.tap(types =>
        types.add({
            paymentCode: 'banktransfer',
            importPath: BANK_TRANSFER_COMPONENTS.editable
        })
    );

    veniaTargets.summaryPagePaymentTypes.tap(types =>
        types.add({
            paymentCode: 'banktransfer',
            importPath: BANK_TRANSFER_COMPONENTS.summary
        })
    );
};

module.exports = targets => {
    const { specialFeatures } = targets.of('@magento/pwa-buildpack');
    specialFeatures.tap(flags => {
        flags['@saltgoat/venia-extension'] = {
            esModules: true,
            cssModules: true,
            graphqlQueries: true
        };
    });

    registerBankTransfer(targets);

    const targetables = Targetables.using(targets);

    const appComponent = targetables.reactComponent(
        '@magento/venia-ui/lib/components/App/app.js'
    );
    appComponent.wrapWithFile(
        '@saltgoat/venia-extension/src/components/ThemeProvider/withThemeProvider'
    );

    const mainComponent = targetables.reactComponent(
        '@magento/venia-ui/lib/components/Main/main.js'
    );
    mainComponent.wrapWithFile(
        '@saltgoat/venia-extension/src/components/ThemeProvider/withThemeMain'
    );

    const homePage = targetables.reactComponent(
        '@magento/venia-ui/lib/components/HomePage/homePage.ce.js'
    );

    homePage.wrapWithFile(
        '@saltgoat/venia-extension/src/components/HomeContent'
    );

    const routes = targetables.reactComponent(
        '@magento/venia-ui/lib/components/Routes/routes.js'
    );
    routes.addImport(
        "import NotFound from '@saltgoat/venia-extension/src/components/NotFound';"
    );
    routes.insertBeforeSource(
        '            </Switch>',
        '                <Route component={NotFound} />\n'
    );

    const header = targetables.reactComponent(
        '@magento/venia-ui/lib/components/Header/header.js'
    );
    header.addImport(
        "import ThemeToggle from '@saltgoat/venia-extension/src/components/ThemeToggle';"
    );
    header.insertBeforeSource(
        '                        <SearchTrigger',
        '                        <ThemeToggle />\n'
    );
    header.insertAfterSource(
        'const title = formatMessage({ id: \'logo.title\', defaultMessage: \'Venia\' });',
        "\n    const saltgoatHeaderStyle = {\n        background: '#05070f',\n        color: '#f4f6fb',\n        borderBottom: '1px solid rgba(255, 255, 255, 0.08)'\n    };\n"
    );
    header.replaceJSX(
        '<header className={rootClass} data-cy="Header-root">',
        '<header className={rootClass} data-cy="Header-root" style={saltgoatHeaderStyle}>'
    );
};
