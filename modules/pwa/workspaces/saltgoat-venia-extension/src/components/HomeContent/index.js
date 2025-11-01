import React from 'react';

import CMSPageShimmer from '@magento/venia-ui/lib/RootComponents/CMS/cms.shimmer';
import RichContent from '@magento/venia-ui/lib/components/RichContent';
import { useCmsPage } from '@magento/peregrine/lib/talons/Cms/useCmsPage';

const HomeContent = () => {
    if (typeof window !== 'undefined') {
        window.__PWA_REACT_FROM_HOME__ = React;
        window.__PWA_REACT_VERSION__ = React.version;
    }

    const identifier =
        process.env.MAGENTO_PWA_HOME_IDENTIFIER &&
        process.env.MAGENTO_PWA_HOME_IDENTIFIER.trim()
            ? process.env.MAGENTO_PWA_HOME_IDENTIFIER.trim()
            : 'home';

    const { cmsPage, shouldShowLoadingIndicator } = useCmsPage({
        identifier
    });

    if (shouldShowLoadingIndicator) {
        return <CMSPageShimmer />;
    }

    if (!cmsPage || !cmsPage.content) {
        return null;
    }

    return <RichContent html={cmsPage.content} />;
};

export default HomeContent;

