import React from 'react';
import { useStyle } from '@magento/venia-ui/lib/classify';

import defaultClasses from './showcase.module.css';

const heroStats = [
    { label: '实时下单响应', value: '180ms', detail: 'GraphQL 边缘缓存' },
    { label: '部署时间', value: '15min', detail: 'SaltGoat blueprint' },
    { label: '自愈覆盖', value: '24/7', detail: 'Beacon + Reactor' }
];

const trendTags = ['渐变玻璃拟物', 'Live Commerce', 'Page Builder', 'Headless PWA'];

const spotlightCollections = [
    {
        title: '立体新品矩阵',
        subtitle: 'Holographic Drop',
        href: '/collections/holographic',
        image:
            'https://images.unsplash.com/photo-1512436991641-6745cdb1723f?auto=format&fit=crop&w=900&q=70'
    },
    {
        title: '运动性能实验室',
        subtitle: 'Motion Lab',
        href: '/collections/motion',
        image:
            'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=900&q=70'
    },
    {
        title: '家居生活流',
        subtitle: 'Living Flow',
        href: '/collections/living',
        image:
            'https://images.unsplash.com/photo-1493666438817-866a91353ca9?auto=format&fit=crop&w=900&q=70'
    }
];

const serviceHighlights = [
    {
        title: 'Page Builder 即时同步',
        description: '内容团队发布后 60 秒内同步至前端，自动生成回滚点。',
        accent: '内容'
    },
    {
        title: '智能资源巡检',
        description: 'Valkey / RabbitMQ / OpenSearch 指标异常触发自愈与告警节流。',
        accent: '监控'
    },
    {
        title: '一键算力提速',
        description: '自动完成 PHP-FPM thread tuning、Nginx cache 与 Percona 优化。',
        accent: '性能'
    }
];

const realtimeSignals = [
    { type: '订单', message: '#1045 付款完成', time: '2 分钟前', delta: '+¥1,280' },
    { type: '库存', message: '跑鞋 SKY-FLUX 补货 120 件', time: '8 分钟前', delta: '+120' },
    { type: '运营', message: 'Venia-Live Story 推送成功', time: '12 分钟前', delta: '3 个渠道' },
    { type: '安全', message: 'WAF 规则更新已激活', time: '25 分钟前', delta: '全站' }
];

const Showcase = () => {
    const classes = useStyle(defaultClasses);
    const heroSignals = realtimeSignals.slice(0, 2);

    return (
        <section className={classes.root}>
            <div className={classes.heroLayer}>
                <div className={classes.glowOne} />
                <div className={classes.glowTwo} />
            </div>
            <div className={classes.hero}>
                <div className={classes.heroCard}>
                    <div className={classes.heroTopRow}>
                        <span className={classes.badge}>Venia Hyper Surface</span>
                    </div>
                    <h1>
                        立体化 PWA 首屏，
                        <br />
                        让用户一眼爱上
                    </h1>
                    <p>
                        通过 SaltGoat PWA 模块，把 Page Builder、实时订单和自动化运营整合成一个具备深度纵深感的首屏体验。渐变玻璃、柔光浮层、流动图块，让性能与美感并存。
                    </p>
                    <div className={classes.heroActions}>
                        <a className={classes.primaryCta} href="/collections/new">
                            立即选购
                        </a>
                        <a className={classes.secondaryCta} href="/page-builder">
                            布局指南
                        </a>
                    </div>
                    <div className={classes.trendTags}>
                        {trendTags.map(tag => (
                            <span key={tag}>{tag}</span>
                        ))}
                    </div>
                    <div className={classes.heroStats}>
                        {heroStats.map(item => (
                            <article key={item.label}>
                                <strong>{item.value}</strong>
                                <span>{item.label}</span>
                                <p>{item.detail}</p>
                            </article>
                        ))}
                    </div>
                </div>
                <div className={classes.heroScene}>
                    <div className={classes.sceneBackdrop} />
                    <div className={classes.sceneCard}>
                        <header>
                            <span>Live Dashboard</span>
                            <strong>Saltgoat Pulse</strong>
                        </header>
                        <div className={classes.sceneMetric}>
                            <div>
                                <span>转化率</span>
                                <strong>+38%</strong>
                            </div>
                            <div>
                                <span>PV 峰值</span>
                                <strong>48k</strong>
                            </div>
                        </div>
                        <ul className={classes.sceneSignals}>
                            {heroSignals.map(item => (
                                <li key={item.message}>
                                    <div>
                                        <span>{item.type}</span>
                                        <strong>{item.message}</strong>
                                    </div>
                                    <em>{item.delta}</em>
                                </li>
                            ))}
                        </ul>
                    </div>
                    <div className={classes.sceneFloating}>
                        <span>GraphQL Edge</span>
                        <strong>180 ms</strong>
                    </div>
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
                            <a key={tile.title} className={classes.collectionCard} href={tile.href}>
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
                        <span>实时脉搏</span>
                        <h3>订单、库存、运维事件统一面板</h3>
                    </div>
                    <a href="/monitor/live">查看监控</a>
                </header>
                <div className={classes.timelineList}>
                    {realtimeSignals.map(item => (
                        <div key={item.message} className={classes.timelineItem}>
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
