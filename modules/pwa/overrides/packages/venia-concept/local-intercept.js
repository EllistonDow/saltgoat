const { Targetables } = require('@magento/pwa-buildpack');

module.exports = targets => {
    const targetables = Targetables.using(targets);

    const homePage = targetables.reactComponent(
        '@magento/venia-ui/lib/components/HomePage/homePage.ce.js'
    );

    homePage.wrapWithFile('@saltgoat/venia-extension/src/components/HomeContent');
};
