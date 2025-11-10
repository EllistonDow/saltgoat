import React, { useMemo } from 'react';
import { useQuery } from '@apollo/client';
import { useStyle } from '@magento/venia-ui/lib/classify';

import defaultClasses from './showcase.module.css';
import { resolveShowcaseConfig } from './showcaseConfig';
import SHOWCASE_QUERY from './showcase.gql';

const DEFAULT_CATEGORY_IDS = '3,4,5';
const backendOrigin = (process.env.MAGENTO_BACKEND_URL || '').replace(/\/$/, '');

const parseCategoryIds = raw => {
    const source = raw && raw.trim().length ? raw : DEFAULT_CATEGORY_IDS;
    return source
        .split(',')
        .map(value => value.trim())
        .filter(Boolean);
};

const normalizeSuffix = suffix => {
    if (!suffix) {
        return '';
    }
    return suffix.startsWith('.') ? suffix : `.${suffix}`;
};

const buildMediaUrl = path => {
    if (!path) {
        return null;
    }
    if (/^https?:\/\//i.test(path)) {
        return path;
    }
    const normalized = path.startsWith('/') ? path : `/${path}`;
    if (normalized.startsWith('/media/')) {
        return backendOrigin ? `${backendOrigin}${normalized}` : normalized;
    }
    if (!backendOrigin) {
        return normalized;
    }
    return `${backendOrigin}/media/catalog/category${normalized}`;
};

const replaceTokens = (value, tokens) => {
    if (typeof value !== 'string') {
        return value;
    }
    return value.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (match, key) => {
        const tokenValue = tokens[key];
        if (tokenValue === undefined || tokenValue === null || tokenValue === '') {
            return match;
        }
        return tokenValue;
    });
};

const interpolateConfig = (input, tokens) => {
    if (Array.isArray(input)) {
        return input.map(item => interpolateConfig(item, tokens));
    }
    if (input && typeof input === 'object') {
        return Object.entries(input).reduce((acc, [key, value]) => {
            acc[key] = interpolateConfig(value, tokens);
            return acc;
        }, {});
    }
    return replaceTokens(input, tokens);
};

const renderHeading = title => {
    if (!title) {
        return null;
    }
    const lines = String(title).split(/\n/);
    return lines.map((line, index) => (
        <React.Fragment key={`${line}-${index}`}>
            {line}
            {index < lines.length - 1 ? <br /> : null}
        </React.Fragment>
    ));
};

const Showcase = () => {
    const classes = useStyle(defaultClasses);
    const categoryIds = useMemo(
        () => parseCategoryIds(process.env.MAGENTO_PWA_SHOWCASE_CATEGORY_IDS || ''),
        []
    );
    const { data } = useQuery(SHOWCASE_QUERY, {
        variables: { categoryIds },
        skip: !categoryIds.length
    });
    const storeName = data?.storeConfig?.store_name || '';
    const categorySuffix = normalizeSuffix(data?.storeConfig?.category_url_suffix || '');
    const graphqlCollections = useMemo(() => {
        const items = data?.categoryList?.items || [];
        return items
            .filter(item => item && item.name && (item.url_path || item.id))
            .map(item => {
                const urlPath = item.url_path ? `/${item.url_path}` : null;
                const href = urlPath ? `${urlPath}${categorySuffix}` : `/categories/${item.id}`;
                return {
                    title: item.name,
                    subtitle: item.meta_title || item.name,
                    href,
                    image: buildMediaUrl(item.image || item.image_path)
                };
            });
    }, [data, categorySuffix]);

    const baseConfig = useMemo(() => resolveShowcaseConfig(), []);
    const interpolatedConfig = useMemo(
        () => interpolateConfig(baseConfig, { store_name: storeName }),
        [baseConfig, storeName]
    );
    const fallbackCollections = interpolatedConfig.spotlightCollections || [];
    const spotlightCollections = graphqlCollections.length ? graphqlCollections : fallbackCollections;

    const hero = interpolatedConfig.hero || {};
    const heroScene = interpolatedConfig.heroScene || {};
    const timeline = interpolatedConfig.timeline || {};
    const heroSignals = (interpolatedConfig.realtimeSignals || []).slice(0, 2);
    const trendTags = hero.trendTags || [];
    const heroStats = hero.stats || [];
    const ctas = hero.ctas || [];
    const sceneMetrics = heroScene.metrics || [];
    const serviceHighlights = interpolatedConfig.serviceHighlights || [];
    const realtimeSignals = interpolatedConfig.realtimeSignals || [];
    const floatingMetric = hero.floatingMetric || {};

    return (
        <section className={classes.root}>
            <div className={classes.heroLayer}>
                <div className={classes.glowOne} />
                <div className={classes.glowTwo} />
            </div>
            <div className={classes.hero}>
                <div className={classes.heroCard}>
                    {hero.badge ? (
                        <div className={classes.heroTopRow}>
                            <span className={classes.badge}>{hero.badge}</span>
                        </div>
                    ) : null}
                    <h1>{renderHeading(hero.title)}</h1>
                    {hero.description ? <p>{hero.description}</p> : null}
                    {ctas.length ? (
                        <div className={classes.heroActions}>
                            {ctas.map(cta => {
                                const variant =
                                    cta.variant === 'secondary' ? 'secondaryCta' : 'primaryCta';
                                const className = classes[variant] || classes.primaryCta;
                                const target = cta.target || undefined;
                                const rel = target === '_blank' ? 'noreferrer' : undefined;
                                return (
                                    <a
                                        key={`${cta.href}-${cta.label}`}
                                        className={className}
                                        href={cta.href}
                                        target={target}
                                        rel={rel}
                                    >
                                        {cta.label}
                                    </a>
                                );
                            })}
                        </div>
                    ) : null}
                    {trendTags.length ? (
                        <div className={classes.trendTags}>
                            {trendTags.map(tag => (
                                <span key={tag}>{tag}</span>
                            ))}
                        </div>
                    ) : null}
                    {heroStats.length ? (
                        <div className={classes.heroStats}>
                            {heroStats.map(item => (
                                <article key={`${item.label}-${item.value}`}>
                                    {item.value ? <strong>{item.value}</strong> : null}
                                    {item.label ? <span>{item.label}</span> : null}
                                    {item.detail ? <p>{item.detail}</p> : null}
                                </article>
                            ))}
                        </div>
                    ) : null}
                </div>
                <div className={classes.heroScene}>
                    <div className={classes.sceneBackdrop} />
                    <div className={classes.sceneCard}>
                        <header>
                            <span>{heroScene.label || 'Live Dashboard'}</span>
                            <strong>{heroScene.title || 'Saltgoat Pulse'}</strong>
                        </header>
                        {sceneMetrics.length ? (
                            <div className={classes.sceneMetric}>
                                {sceneMetrics.map(metric => (
                                    <div key={`${metric.label}-${metric.value}`}>
                                        <span>{metric.label}</span>
                                        <strong>{metric.value}</strong>
                                    </div>
                                ))}
                            </div>
                        ) : null}
                        <ul className={classes.sceneSignals}>
                            {heroSignals.map((item, index) => (
                                <li key={`${item.type || 'signal'}-${item.message || index}`}>
                                    <div>
                                        <span>{item.type}</span>
                                        <strong>{item.message}</strong>
                                    </div>
                                    <em>{item.delta}</em>
                                </li>
                            ))}
                        </ul>
                    </div>
                    {floatingMetric.label || floatingMetric.value ? (
                        <div className={classes.sceneFloating}>
                            {floatingMetric.label ? <span>{floatingMetric.label}</span> : null}
                            {floatingMetric.value ? <strong>{floatingMetric.value}</strong> : null}
                        </div>
                    ) : null}
                </div>
            </div>

            <div className={classes.gridSplit}>
                <div>
                    <div className={classes.sectionHeading}>
                        <span>沉浸式系列</span>
                        <h2>用三维卡片讲述你的新品故事</h2>
                    </div>
                    <div className={classes.collectionGrid}>
                        {spotlightCollections.map(tile => (
                            <a
                                key={tile.title || tile.href}
                                className={classes.collectionCard}
                                href={tile.href}
                            >
                                <img src={tile.image} alt={tile.subtitle} loading="lazy" />
                                <div>
                                    <span>{tile.subtitle}</span>
                                    <strong>{tile.title}</strong>
                                </div>
                            </a>
                        ))}
                    </div>
                </div>

                <div className={classes.cubeStack}>
                    <div className={classes.sectionHeading}>
                        <span>自动化驱动</span>
                        <h2>服务方块，展示核心能力</h2>
                    </div>
                    <div className={classes.cubeGrid}>
                        {serviceHighlights.map(card => (
                            <article key={card.title}>
                                <span>{card.accent}</span>
                                <h3>{card.title}</h3>
                                <p>{card.description}</p>
                            </article>
                        ))}
                    </div>
                </div>
            </div>

            <div className={classes.timeline}>
                <header>
                    <div>
                        <span>{timeline.label || '实时脉搏'}</span>
                        <h3>{timeline.title || '订单、库存、运维事件统一面板'}</h3>
                    </div>
                    {timeline.cta && timeline.cta.href ? (
                        <a
                            href={timeline.cta.href}
                            target={timeline.cta.target}
                            rel={timeline.cta.target === '_blank' ? 'noreferrer' : undefined}
                        >
                            {timeline.cta.label || timeline.cta.href}
                        </a>
                    ) : null}
                </header>
                <div className={classes.timelineList}>
                    {realtimeSignals.map((item, index) => (
                        <div
                            key={`${item.message || item.type || 'timeline'}-${index}`}
                            className={classes.timelineItem}
                        >
                            <div>
                                <span>{item.type}</span>
                                <strong>{item.message}</strong>
                            </div>
                            <div>
                                <em>{item.time}</em>
                                <strong>{item.delta}</strong>
                            </div>
                        </div>
                    ))}
                </div>
            </div>
        </section>
    );
};

export default Showcase;
