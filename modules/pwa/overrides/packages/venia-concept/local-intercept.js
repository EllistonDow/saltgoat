const { Targetables } = require('@magento/pwa-buildpack');

const FREE_PAYMENT_COMPONENTS = {
    checkout:
        '@saltgoat/venia-extension/src/components/Payments/Free/checkout',
    editable:
        '@saltgoat/venia-extension/src/components/Payments/Free/editable',
    summary: '@saltgoat/venia-extension/src/components/Payments/Free/summary'
};

const registerFreePayment = targets => {
    const veniaTargets = targets.of('@magento/venia-ui');

    veniaTargets.checkoutPagePaymentTypes.tap(payments =>
        payments.add({
            paymentCode: 'free',
            importPath: FREE_PAYMENT_COMPONENTS.checkout
        })
    );

    veniaTargets.editablePaymentTypes.tap(types =>
        types.add({
            paymentCode: 'free',
            importPath: FREE_PAYMENT_COMPONENTS.editable
        })
    );

    veniaTargets.summaryPagePaymentTypes.tap(types =>
        types.add({
            paymentCode: 'free',
            importPath: FREE_PAYMENT_COMPONENTS.summary
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

    registerFreePayment(targets);

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
};
