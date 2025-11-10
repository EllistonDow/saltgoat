const defaultConfig = {
    hero: {
        badge: '{{store_name}} Digital Pulse',
        title: '{{store_name}} · 全渠道体验枢纽',
        description:
            '借助 SaltGoat PWA 模块，{{store_name}} 可以把 Page Builder 内容、实时订单与自动化运营整合到同一首屏，既可快速上线，也能随品牌随时迭代。',
        ctas: [
            { label: '探索新品', href: '/collections/new', variant: 'primary' },
            { label: '查看服务', href: '/service', variant: 'secondary' }
        ],
        trendTags: ['Headless Commerce', 'Page Builder', 'Live Analytics', 'SaltGoat Ops'],
        stats: [
            { label: 'PWA 覆盖', value: '98%', detail: '多 Store View 统一体验' },
            { label: '上线窗口', value: '15min', detail: 'SaltGoat blueprint' },
            { label: '巡检自愈', value: '24/7', detail: 'Beacon + Reactor' }
        ],
        floatingMetric: { label: 'GraphQL Edge', value: '180 ms' }
    },
    heroScene: {
        label: 'Live Dashboard',
        title: 'Saltgoat Pulse',
        metrics: [
            { label: '转化率', value: '+38%' },
            { label: 'PV 峰值', value: '48k' }
        ]
    },
    spotlightCollections: [
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
    ],
    serviceHighlights: [
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
    ],
    realtimeSignals: [
        { type: '订单', message: '#1045 付款完成', time: '2 分钟前', delta: '+¥1,280' },
        { type: '库存', message: '跑鞋 SKY-FLUX 补货 120 件', time: '8 分钟前', delta: '+120' },
        { type: '运营', message: 'Venia-Live Story 推送成功', time: '12 分钟前', delta: '3 个渠道' },
        { type: '安全', message: 'WAF 规则更新已激活', time: '25 分钟前', delta: '全站' }
    ],
    timeline: {
        label: '实时脉搏',
        title: '订单、库存、运维事件统一面板',
        cta: { label: '查看监控', href: '/monitor/live' }
    }
};

const isPlainObject = value =>
    Boolean(value) && typeof value === 'object' && !Array.isArray(value);

const mergeLayer = (base, override) => {
    const output = { ...(base || {}) };
    if (!isPlainObject(override)) {
        return output;
    }
    Object.entries(override).forEach(([key, value]) => {
        if (Array.isArray(value)) {
            output[key] = value.length ? value : output[key] || [];
            return;
        }
        if (isPlainObject(value)) {
            output[key] = mergeLayer(output[key], value);
            return;
        }
        if (typeof value !== 'undefined' && value !== null) {
            output[key] = value;
        }
    });
    return output;
};

const parseJson = value => {
    try {
        return JSON.parse(value);
    } catch (error) {
        return null;
    }
};

const getEnvConfig = () => {
    if (typeof process === 'undefined') {
        return null;
    }
    if (!process.env || !process.env.SALTGOAT_PWA_SHOWCASE) {
        return null;
    }
    return parseJson(process.env.SALTGOAT_PWA_SHOWCASE);
};

const getRuntimeConfig = () => {
    if (typeof window === 'undefined') {
        return null;
    }
    const candidate = window.__SALTGOAT_PWA_SHOWCASE__;
    return isPlainObject(candidate) ? candidate : null;
};

export const resolveShowcaseConfig = () => {
    const envConfig = getEnvConfig();
    const runtimeConfig = getRuntimeConfig();
    return [defaultConfig, envConfig, runtimeConfig].reduce(
        (acc, layer) => mergeLayer(acc, layer),
        {}
    );
};

export default defaultConfig;
