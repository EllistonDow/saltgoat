import React, { useMemo } from 'react';

import CMSPageShimmer from '@magento/venia-ui/lib/RootComponents/CMS/cms.shimmer';
import RichContent from '@magento/venia-ui/lib/components/RichContent';
import { useCmsPage } from '@magento/peregrine/lib/talons/Cms/useCmsPage';

import Showcase from './Showcase';

const createHomeContent = OriginalComponent => {
    const PwaHomeContent = props => {
        if (typeof window !== 'undefined') {
            const internals = React.__SECRET_INTERNALS_DO_NOT_USE_OR_YOU_WILL_BE_FIRED || {};
            const dispatcher = internals.ReactCurrentDispatcher
                ? internals.ReactCurrentDispatcher.current || null
                : null;
            const debugPayload = {
                version: React.version || null,
                hasDispatcher: Boolean(dispatcher),
                dispatcherKeys: dispatcher ? Object.keys(dispatcher) : [],
                sameAsGlobal: window.React === React
            };
            window.__PWA_REACT_FROM_HOME__ = React;
            window.__PWA_REACT_VERSION__ = debugPayload.version;
            window.__PWA_REACT_DEBUG__ = debugPayload;
        }

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
            // 默认回退为 Venia 风格展示 + 原组件（避免空白页面）
            return React.createElement(
                React.Fragment,
                null,
                React.createElement(Showcase, null),
                OriginalComponent
                    ? React.createElement(OriginalComponent, props)
                    : null
            );
        }

        return React.createElement(RichContent, { html: cmsContent });
    };

    PwaHomeContent.displayName = 'PwaHomeContent';

    return PwaHomeContent;
};

export default createHomeContent;
