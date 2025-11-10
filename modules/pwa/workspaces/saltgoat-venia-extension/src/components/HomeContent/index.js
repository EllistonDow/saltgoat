import React, { useEffect, useMemo } from 'react';

import CMSPageShimmer from '@magento/venia-ui/lib/RootComponents/CMS/cms.shimmer';
import RichContent from '@magento/venia-ui/lib/components/RichContent';
import { useCmsPage } from '@magento/peregrine/lib/talons/Cms/useCmsPage';

import Showcase from './Showcase';

const recordReactDebugInfo = () => {
    if (typeof window === 'undefined') {
        return;
    }
    const payload = {
        version: React.version || null,
        sameAsGlobal: window.React === React,
        timestamp: Date.now()
    };
    window.__PWA_REACT_VERSION__ = payload.version;
    window.__PWA_REACT_DEBUG__ = payload;
};

const createHomeContent = OriginalComponent => {
    const PwaHomeContent = props => {
        useEffect(() => {
            recordReactDebugInfo();
        }, []);

        const identifier =
            process.env.MAGENTO_PWA_HOME_IDENTIFIER && process.env.MAGENTO_PWA_HOME_IDENTIFIER.trim()
                ? process.env.MAGENTO_PWA_HOME_IDENTIFIER.trim()
                : 'home';

        const { cmsPage, shouldShowLoadingIndicator } = useCmsPage({
            identifier
        });

        const cmsContent = useMemo(() => cmsPage?.content?.trim() || '', [cmsPage]);

        if (shouldShowLoadingIndicator) {
            return React.createElement(CMSPageShimmer, null);
        }

        if (!cmsContent) {
            return null;
        }

        return React.createElement(RichContent, { html: cmsContent });
    };

    PwaHomeContent.displayName = 'PwaHomeContent';

    return PwaHomeContent;
};

export default createHomeContent;
