import React from 'react';

import CMSPageShimmer from '@magento/venia-ui/lib/RootComponents/CMS/cms.shimmer';
import RichContent from '@magento/venia-ui/lib/components/RichContent';
import { useCmsPage } from '@magento/peregrine/lib/talons/Cms/useCmsPage';

const HomeContent = () => {
    const { cmsPage, shouldShowLoadingIndicator } = useCmsPage({
        identifier: 'home'
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
