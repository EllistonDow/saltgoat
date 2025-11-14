import React, { useEffect, useMemo, useRef } from 'react';

const SLIDES = [
    {
        tag: 'DROP · AURORA FLUX',
        title: 'Chromatic workstations',
        copy: 'Electroplated frames with adaptive haptics. Ships with AI-guided needle memory.',
        image:
            'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1400&q=80'
    },
    {
        tag: 'OPS · VANTA GRID',
        title: 'Telemetry autopilot',
        copy: 'Predict pigment depletion and auto-issue purchase orders per studio bay.',
        image:
            'https://images.unsplash.com/photo-1489515217757-5fd1be406fef?auto=format&fit=crop&w=1400&q=80'
    },
    {
        tag: 'EXPO · VOIDWAVE',
        title: 'Immersive pop-ups',
        copy: 'Deploy holographic booths, queue-less checkout, and AR-ready product tours.',
        image:
            'https://images.unsplash.com/photo-1470104240373-bc1812eddc9f?auto=format&fit=crop&w=1400&q=80'
    }
];

const NebulaHome = () => {
    const sliderRef = useRef(null);
    const orbitRef = useRef(null);
    const labRef = useRef(null);

    useEffect(() => initSlider(sliderRef.current), []);
    useEffect(() => initOrbitCanvas(orbitRef.current), []);
    useEffect(() => initLabCanvas(labRef.current), []);

    const metricCards = useMemo(
        () => [
            { label: 'RENDER SPEED', value: '38 ms', copy: 'Edge LCP average across tattoo capitals.' },
            { label: 'PRODUCT MODES', value: '420+', copy: 'Interactive rigs, pigment vaults, and supply stacks.' },
            { label: 'UPTIME', value: '99.97%', copy: 'Multi-region orchestration with auto healing.' }
        ],
        []
    );

    const panels = useMemo(
        () => [
            { tag: 'MODE 01', title: 'Living lookbooks', copy: 'Blend CMS scenes, shader loops, and drop timers without reloads.' },
            { tag: 'MODE 02', title: 'Synced supply brains', copy: 'RFID, B2B restock portals, and studio telemetry streaming into Venia.' },
            { tag: 'MODE 03', title: 'Story-driven checkout', copy: 'Glassmorphism checkout sections with artist histories & curated upsells.' }
        ],
        []
    );

    return (
        <section className="nebula-home">
            <div className="nebula-shell">
                <header className="nebula-hero">
                    <div className="nebula-hero-copy">
                        <span className="nebula-pill">NEBULA SUPPLY GRID</span>
                        <h1>Design gravity-defying storefronts for fearless studios.</h1>
                        <p>
                            Launch cinematic drops, sync tactile inventories, and render interactive rigs straight inside your PWA. SaltGoat orchestrates
                            automation, storytelling, and fulfillment without losing an ounce of vibe.
                        </p>
                        <div className="nebula-hero-actions">
                            <a href="/collections" className="nebula-btn primary">
                                Browse curations →
                            </a>
                            <a href="/contact" className="nebula-btn">
                                Book a hologram demo
                            </a>
                        </div>
                        <div className="nebula-metrics">
                            {metricCards.map(card => (
                                <article className="nebula-card" key={card.label}>
                                    <span>{card.label}</span>
                                    <strong>{card.value}</strong>
                                    <small>{card.copy}</small>
                                </article>
                            ))}
                        </div>
                    </div>
                    <div className="nebula-orbit">
                        <canvas ref={orbitRef} aria-hidden="true" />
                    </div>
                </header>

                <section className="nebula-grid">
                    {panels.map(panel => (
                        <article className="nebula-panel" key={panel.tag}>
                            <span>{panel.tag}</span>
                            <strong>{panel.title}</strong>
                            <p>{panel.copy}</p>
                        </article>
                    ))}
                </section>

                <section className="nebula-labs">
                    <div>
                        <span className="nebula-pill">Hologram Lab</span>
                        <h2>Spin 3D rigs directly inside your home page.</h2>
                        <p>Upload GLB, Lottie, or shader specs — the Nebula lab renders interactive previews across Venia, microsites, and embedded kiosks.</p>
                    </div>
                    <canvas ref={labRef} aria-hidden="true" />
                </section>

                <section className="nebula-slider" ref={sliderRef}>
                    <div className="nebula-slider-track">
                        {SLIDES.map(slide => (
                            <article className="nebula-slide" key={slide.title}>
                                <div>
                                    <span className="nebula-pill">{slide.tag}</span>
                                    <h3>{slide.title}</h3>
                                    <p>{slide.copy}</p>
                                </div>
                                <div className="nebula-slide-visual" style={{ backgroundImage: `url('${slide.image}')` }} />
                            </article>
                        ))}
                    </div>
                    <div className="nebula-slider-nav">
                        <button type="button" data-dir="-1" aria-label="Previous slide">
                            ‹
                        </button>
                        <button type="button" data-dir="1" aria-label="Next slide">
                            ›
                        </button>
                    </div>
                </section>

                <section className="nebula-cta">
                    <h2>Compose the next-generation tattoo commerce portal.</h2>
                    <p>Pair Venia storefronts, OnePage showcases, and hologram-ready landing pads — all orchestrated by SaltGoat.</p>
                    <div className="nebula-hero-actions" style={{ justifyContent: 'center' }}>
                        <a href="mailto:hello@saltgoat.com" className="nebula-btn primary">
                            Start a build session
                        </a>
                        <a href="/onepage" className="nebula-btn">
                            Launch a single-product universe
                        </a>
                    </div>
                </section>
            </div>
        </section>
    );
};

export default NebulaHome;

function initSlider(root) {
    if (!root) {
        return undefined;
    }
    const track = root.querySelector('.nebula-slider-track');
    const buttons = root.querySelectorAll('.nebula-slider-nav button');
    const slides = track ? track.children : [];
    if (!track || !slides.length) {
        return undefined;
    }
    let index = 0;
    let timer = null;
    const go = dir => {
        index = (index + dir + slides.length) % slides.length;
        track.style.transform = `translateX(-${index * 100}%)`;
    };
    const handleClick = event => {
        const dir = parseInt(event.currentTarget.dataset.dir, 10) || 0;
        go(dir);
        reset();
    };
    const reset = () => {
        if (timer) {
            window.clearInterval(timer);
        }
        timer = window.setInterval(() => go(1), 6500);
    };
    buttons.forEach(btn => btn.addEventListener('click', handleClick));
    reset();
    return () => {
        buttons.forEach(btn => btn.removeEventListener('click', handleClick));
        if (timer) {
            window.clearInterval(timer);
        }
    };
}

function initOrbitCanvas(canvas) {
    if (!canvas) {
        return undefined;
    }
    const ctx = canvas.getContext('2d');
    const resize = () => {
        const ratio = window.devicePixelRatio || 1;
        canvas.width = canvas.clientWidth * ratio;
        canvas.height = canvas.clientHeight * ratio;
    };
    resize();
    window.addEventListener('resize', resize);
    let t = 0;
    let raf = null;
    const render = () => {
        t += 0.01;
        const { width, height } = canvas;
        ctx.clearRect(0, 0, width, height);
        ctx.save();
        ctx.translate(width / 2, height / 2);
        const rings = 6;
        for (let i = 0; i < rings; i++) {
            const ratio = i / rings;
            const radius = 60 + i * 35;
            const hue = 200 + ratio * 80;
            ctx.strokeStyle = `hsla(${hue}, 90%, 70%, ${0.4 + (1 - ratio) * 0.4})`;
            ctx.lineWidth = 2 + (1 - ratio) * 2;
            ctx.beginPath();
            ctx.ellipse(0, 0, radius, radius * (0.6 + 0.2 * Math.sin(t + i)), t * (0.5 + ratio), 0, Math.PI * 2);
            ctx.stroke();
        }
        ctx.restore();
        raf = window.requestAnimationFrame(render);
    };
    render();
    return () => {
        window.removeEventListener('resize', resize);
        if (raf) {
            window.cancelAnimationFrame(raf);
        }
    };
}

function initLabCanvas(canvas) {
    if (!canvas) {
        return undefined;
    }
    const ctx = canvas.getContext('2d');
    const resize = () => {
        const ratio = window.devicePixelRatio || 1;
        canvas.width = canvas.clientWidth * ratio;
        canvas.height = canvas.clientHeight * ratio;
    };
    resize();
    window.addEventListener('resize', resize);
    const sparks = Array.from({ length: 80 }).map(() => ({
        angle: Math.random() * Math.PI * 2,
        radius: 20 + Math.random() * 140,
        speed: 0.004 + Math.random() * 0.01,
        size: 3 + Math.random() * 3
    }));
    let raf = null;
    const draw = () => {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        ctx.save();
        ctx.translate(canvas.width / 2, canvas.height / 2);
        sparks.forEach((spark, idx) => {
            spark.angle += spark.speed;
            const x = Math.cos(spark.angle) * spark.radius;
            const y = Math.sin(spark.angle) * spark.radius * 0.6;
            const gradient = ctx.createRadialGradient(x, y, 0, x, y, spark.size * 2);
            gradient.addColorStop(0, `rgba(120, ${180 + (idx % 70)}, 255, 0.9)`);
            gradient.addColorStop(1, 'rgba(120, 150, 255, 0)');
            ctx.fillStyle = gradient;
            ctx.beginPath();
            ctx.arc(x, y, spark.size, 0, Math.PI * 2);
            ctx.fill();
        });
        ctx.restore();
        raf = window.requestAnimationFrame(draw);
    };
    draw();
    return () => {
        window.removeEventListener('resize', resize);
        if (raf) {
            window.cancelAnimationFrame(raf);
        }
    };
}
