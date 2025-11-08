import React from 'react';
import { useStyle } from '@magento/venia-ui/lib/classify';

import defaultClasses from './showcase.module.css';

const heroHighlights = [
    { value: '2x', label: '页面加载速度' },
    { value: '24/7', label: '实时监控/自愈' },
    { value: '15min', label: '一键部署' }
];

const featureCards = [
    {
        title: 'Page Builder 驱动',
        description:
            '可视化拖拽 Banner、内容块和商品小部件，保存后通过 SaltGoat 同步到 PWA。'
    },
    {
        title: '自动化运营',
        description:
            'saltgoat monitor / magetools schedule auto 自动把站点纳入健康检查与 Cron 调度。'
    },
    {
        title: '多渠道通知',
        description:
            '新订单、新用户、备份、资源告警都会推送到 Telegram / Mattermost 主题。'
    }
];

const collectionTiles = [
    {
        title: '日常服饰',
        subtitle: 'Everyday Essentials',
        href: '/collections/apparel',
        image:
            'https://images.unsplash.com/photo-1542291026-7eec264c27ff?auto=format&fit=crop&w=800&q=70'
    },
    {
        title: '运动装备',
        subtitle: 'Performance Gear',
        href: '/collections/active',
        image:
            'https://images.unsplash.com/photo-1521572267360-ee0c2909d518?auto=format&fit=crop&w=800&q=70'
    },
    {
        title: '家居生活',
        subtitle: 'Lifestyle & Home',
        href: '/collections/lifestyle',
        image:
            'https://images.unsplash.com/photo-1503602642458-232111445657?auto=format&fit=crop&w=800&q=70'
    }
];

const Showcase = () => {
    const classes = useStyle(defaultClasses);

    return (
        <section className={classes.root}>
            <div className={classes.hero}>
                <div className={classes.heroCopy}>
                    <span className={classes.eyebrow}>Venia Experience</span>
                    <h1>Headless PWA，开箱即用</h1>
                    <p>
                        结合 Magento Page Builder 与 Venia UI 组件，快速搭建具备电商、内容与自动化运营的体验。
                    </p>
                    <div className={classes.heroActions}>
                        <a className={classes.primaryCta} href="/collections/new">
                            立即选购
                        </a>
                        <a className={classes.secondaryCta} href="/page-builder">
                            了解 Page Builder
                        </a>
                    </div>
                    <div className={classes.metrics}>
                        {heroHighlights.map(item => (
                            <div key={item.label}>
                                <strong>{item.value}</strong>
                                <span>{item.label}</span>
                            </div>
                        ))}
                    </div>
                </div>
                <figure className={classes.heroVisual}>
                    <img
                        src="https://images.unsplash.com/photo-1475180098004-ca77a66827be?auto=format&fit=crop&w=1200&q=70"
                        alt="Venia storefront highlight"
                        loading="lazy"
                    />
                </figure>
            </div>

            <div className={classes.collections}>
                {collectionTiles.map(tile => (
                    <a key={tile.title} className={classes.collectionCard} href={tile.href}>
                        <img src={tile.image} alt={tile.subtitle} loading="lazy" />
                        <div>
                            <span>{tile.subtitle}</span>
                            <strong>{tile.title}</strong>
                        </div>
                    </a>
                ))}
            </div>

            <div className={classes.features}>
                {featureCards.map(card => (
                    <article key={card.title}>
                        <h3>{card.title}</h3>
                        <p>{card.description}</p>
                    </article>
                ))}
            </div>
        </section>
    );
};

export default Showcase;
