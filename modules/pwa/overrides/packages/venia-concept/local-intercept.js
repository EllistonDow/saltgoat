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
};
