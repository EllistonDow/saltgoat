const { Targetables } = require('@magento/pwa-buildpack');

const BANK_TRANSFER_COMPONENTS = {
    checkout:
        '@saltgoat/venia-extension/src/components/BankTransfer/BankTransfer.js',
    editable:
        '@saltgoat/venia-extension/src/components/BankTransfer/EditBankTransfer.js',
    summary:
        '@saltgoat/venia-extension/src/components/BankTransfer/SummaryBankTransfer.js'
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
};
