import React, { useEffect, useMemo } from 'react';

import CMSPageShimmer from '@magento/venia-ui/lib/RootComponents/CMS/cms.shimmer';
import RichContent from '@magento/venia-ui/lib/components/RichContent';
import { useCmsPage } from '@magento/peregrine/lib/talons/Cms/useCmsPage';

import Showcase from './Showcase';
import NebulaHome from './NebulaHome';

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

const resolveFallbackMode = () => {
    const raw =
        process.env.SALTGOAT_PWA_SHOWCASE_FALLBACK &&
        process.env.SALTGOAT_PWA_SHOWCASE_FALLBACK.trim();
    if (!raw) {
        return 'off';
    }
    const normalized = raw.toLowerCase();
    if (normalized === 'auto' || normalized === 'on') {
        return 'auto';
    }
    return 'off';
};

const getNebulaIdentifier = () => {
    const raw = process.env.MAGENTO_PWA_ALT_HOME_IDENTIFIER && process.env.MAGENTO_PWA_ALT_HOME_IDENTIFIER.trim();
    return raw && raw.length ? raw : 'pwa_home_no_pb';
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
        const nebulaIdentifier = useMemo(() => getNebulaIdentifier(), []);
        const isNebulaHome = identifier === nebulaIdentifier;

        const { cmsPage, shouldShowLoadingIndicator } = useCmsPage({
            identifier
        });

        const cmsContent = useMemo(() => cmsPage?.content?.trim() || '', [cmsPage]);
        const fallbackMode = useMemo(() => resolveFallbackMode(), []);

        if (isNebulaHome) {
            return React.createElement(NebulaHome, null);
        }

        if (shouldShowLoadingIndicator) {
            return React.createElement(CMSPageShimmer, null);
        }

        if (!cmsContent) {
            if (fallbackMode === 'auto') {
                return React.createElement(Showcase, null);
            }
            return null;
        }

        return React.createElement(RichContent, { html: cmsContent });
    };

    PwaHomeContent.displayName = 'PwaHomeContent';

    return PwaHomeContent;
};

export default createHomeContent;
