import React, { createContext, useCallback, useEffect, useMemo, useState } from 'react';
import '../../styles/theme.global.module.css';

const STORAGE_KEY = 'saltgoat:theme';
const ThemeContext = createContext({
    theme: 'dark',
    toggleTheme: () => {}
});

const getSystemPreference = () => {
    if (typeof window === 'undefined') {
        return 'dark';
    }
    return window.matchMedia('(prefers-color-scheme: dark)').matches
        ? 'dark'
        : 'light';
};

const readInitialTheme = () => {
    if (typeof document === 'undefined') {
        return 'dark';
    }
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (stored === 'light' || stored === 'dark') {
        return stored;
    }
    if (document.documentElement.dataset.theme) {
        return document.documentElement.dataset.theme;
    }
    return getSystemPreference();
};

const THEME_VARS = {
    light: {
        '--sg-page-bg': '#f7f9ff',
        '--sg-text': '#101828',
        '--sg-subtext': '#5c6373',
        '--sg-card-bg': 'rgba(255, 255, 255, 0.9)',
        '--sg-card-border': 'rgba(15, 23, 42, 0.08)',
        '--sg-card-hover-border': 'rgba(31, 107, 255, 0.45)',
        '--sg-primary': '#1f6bff',
        '--sg-primary-strong': '#4e7dff',
        '--sg-primary-text': '#ffffff',
        '--sg-secondary-border': 'rgba(16, 24, 40, 0.25)',
        '--sg-metric-accent': '#1f6bff',
        '--sg-tile-shadow': 'rgba(15, 23, 42, 0.2)',
        '--sg-hero-gradient': 'linear-gradient(135deg, #f7f9ff, #eef3ff 45%, #ffffff)',
        '--sg-hero-shadow': 'rgba(15, 23, 42, 0.15)',
        '--sg-header-bg': 'rgba(255, 255, 255, 0.9)',
        '--sg-header-border': 'rgba(15, 23, 42, 0.1)',
        '--sg-header-text': '#101828',
        '--sg-header-icon': '#101828',
        '--sg-footer-bg': '#e9eefc',
        '--sg-footer-border': 'rgba(16, 24, 40, 0.08)',
        '--sg-footer-text': '#101828',
        '--sg-footer-link': '#1f6bff',
        '--sg-home-gradient':
            'radial-gradient(circle at 10% 20%, rgba(82, 120, 255, 0.2), transparent 42%), radial-gradient(circle at 82% -5%, rgba(255, 137, 197, 0.2), transparent 45%), linear-gradient(135deg, #f7f9ff, #eef3ff 55%, #ffffff)',
        '--sg-glow-primary': 'rgba(105, 152, 255, 0.35)',
        '--sg-glow-accent': 'rgba(255, 161, 214, 0.25)',
        '--sg-hero-card-bg': 'rgba(255, 255, 255, 0.92)',
        '--sg-hero-card-border': 'rgba(15, 23, 42, 0.08)',
        '--sg-hero-card-shadow': 'rgba(15, 23, 42, 0.18)',
        '--sg-chip-bg': 'rgba(255, 255, 255, 0.92)',
        '--sg-chip-border': 'rgba(15, 23, 42, 0.08)',
        '--sg-hero-stats-bg': 'rgba(255, 255, 255, 0.86)',
        '--sg-hero-stats-border': 'rgba(15, 23, 42, 0.08)',
        '--sg-scene-gradient':
            'linear-gradient(145deg, rgba(79, 123, 255, 0.18), rgba(255, 118, 179, 0.12))',
        '--sg-scene-card-bg': 'rgba(255, 255, 255, 0.96)',
        '--sg-scene-card-border': 'rgba(15, 23, 42, 0.08)',
        '--sg-scene-card-shadow': 'rgba(15, 23, 42, 0.22)',
        '--sg-floating-card-bg': 'rgba(255, 255, 255, 0.9)',
        '--sg-floating-card-border': 'rgba(15, 23, 42, 0.12)',
        '--sg-collection-border': 'rgba(15, 23, 42, 0.08)',
        '--sg-collection-shadow': 'rgba(15, 23, 42, 0.2)',
        '--sg-cube-bg': 'linear-gradient(160deg, rgba(255, 255, 255, 0.92), rgba(237, 244, 255, 0.7))',
        '--sg-cube-border': 'rgba(15, 23, 42, 0.08)',
        '--sg-timeline-bg': 'rgba(255, 255, 255, 0.95)',
        '--sg-timeline-border': 'rgba(15, 23, 42, 0.08)',
        '--sg-timeline-shadow': 'rgba(15, 23, 42, 0.16)'
    },
    dark: {
        '--sg-page-bg': '#0b0f1d',
        '--sg-text': '#f4f6fb',
        '--sg-subtext': '#b5c0d6',
        '--sg-card-bg': 'rgba(9, 14, 25, 0.85)',
        '--sg-card-border': 'rgba(255, 255, 255, 0.08)',
        '--sg-card-hover-border': 'rgba(141, 220, 255, 0.6)',
        '--sg-primary': '#8ddcff',
        '--sg-primary-strong': '#4bbdfc',
        '--sg-primary-text': '#0b1220',
        '--sg-secondary-border': 'rgba(255, 255, 255, 0.3)',
        '--sg-metric-accent': '#8ddcff',
        '--sg-tile-shadow': 'rgba(6, 9, 20, 0.45)',
        '--sg-hero-gradient': 'linear-gradient(135deg, #0d1a2d, #0b0f1d 45%, #1b2a54)',
        '--sg-hero-shadow': 'rgba(7, 12, 24, 0.45)',
        '--sg-header-bg': 'rgba(5, 7, 15, 0.9)',
        '--sg-header-border': 'rgba(255, 255, 255, 0.08)',
        '--sg-header-text': '#f4f6fb',
        '--sg-header-icon': '#f4f6fb',
        '--sg-footer-bg': 'rgba(5, 7, 15, 0.95)',
        '--sg-footer-border': 'rgba(255, 255, 255, 0.08)',
        '--sg-footer-text': '#d9deea',
        '--sg-footer-link': '#8ddcff',
        '--sg-home-gradient':
            'radial-gradient(circle at 10% 20%, rgba(82, 120, 255, 0.25), transparent 40%), radial-gradient(circle at 80% 0%, rgba(255, 120, 199, 0.35), transparent 42%), linear-gradient(135deg, #040619, #0c111f 55%, #0a0f1c)',
        '--sg-glow-primary': 'rgba(120, 182, 255, 0.45)',
        '--sg-glow-accent': 'rgba(255, 120, 199, 0.35)',
        '--sg-hero-card-bg': 'rgba(8, 12, 24, 0.78)',
        '--sg-hero-card-border': 'rgba(255, 255, 255, 0.08)',
        '--sg-hero-card-shadow': 'rgba(5, 8, 16, 0.65)',
        '--sg-chip-bg': 'rgba(255, 255, 255, 0.08)',
        '--sg-chip-border': 'rgba(255, 255, 255, 0.12)',
        '--sg-hero-stats-bg': 'rgba(255, 255, 255, 0.03)',
        '--sg-hero-stats-border': 'rgba(255, 255, 255, 0.08)',
        '--sg-scene-gradient':
            'linear-gradient(145deg, rgba(79, 123, 255, 0.2), rgba(255, 118, 179, 0.15))',
        '--sg-scene-card-bg': 'rgba(9, 13, 30, 0.9)',
        '--sg-scene-card-border': 'rgba(255, 255, 255, 0.08)',
        '--sg-scene-card-shadow': 'rgba(5, 8, 18, 0.7)',
        '--sg-floating-card-bg': 'rgba(255, 255, 255, 0.08)',
        '--sg-floating-card-border': 'rgba(255, 255, 255, 0.12)',
        '--sg-collection-border': 'rgba(255, 255, 255, 0.08)',
        '--sg-collection-shadow': 'rgba(5, 8, 18, 0.55)',
        '--sg-cube-bg': 'linear-gradient(160deg, rgba(255, 255, 255, 0.06), rgba(255, 255, 255, 0.02))',
        '--sg-cube-border': 'rgba(255, 255, 255, 0.06)',
        '--sg-timeline-bg': 'rgba(7, 10, 20, 0.85)',
        '--sg-timeline-border': 'rgba(255, 255, 255, 0.05)',
        '--sg-timeline-shadow': 'rgba(5, 8, 16, 0.5)'
    }
};

const applySurfaceStyles = (selector, styles) => {
    if (typeof document === 'undefined') {
        return;
    }
    const node = document.querySelector(selector);
    if (!node) {
        return;
    }
    Object.entries(styles).forEach(([prop, value]) => {
        const cssProp = prop.replace(/[A-Z]/g, match => `-${match.toLowerCase()}`);
        node.style.setProperty(cssProp, value, 'important');
    });
};

const applyTheme = theme => {
    if (typeof document === 'undefined') {
        return;
    }
    const root = document.documentElement;
    const body = document.body;
    const themeClass = `sg-theme-${theme}`;
    root.dataset.theme = theme;
    body.dataset.theme = theme;
    root.classList.add('sg-theme');
    body.classList.add('sg-theme');
    root.classList.remove('sg-theme-dark', 'sg-theme-light');
    body.classList.remove('sg-theme-dark', 'sg-theme-light');
    root.classList.add(themeClass);
    body.classList.add(themeClass);
    const palette = THEME_VARS[theme];
    if (palette) {
        Object.entries(palette).forEach(([varName, value]) => {
            root.style.setProperty(varName, value);
        });
        applySurfaceStyles("[data-cy='Footer-root']", {
            backgroundColor: palette['--sg-footer-bg'],
            color: palette['--sg-footer-text'],
            borderTopColor: palette['--sg-footer-border']
        });
    }
    if (theme === 'dark') {
        body.style.backgroundColor = '#0b0f1d';
        body.style.color = '#f4f6fb';
        root.style.colorScheme = 'dark';
        body.style.colorScheme = 'dark';
    } else {
        body.style.backgroundColor = '#f7f9ff';
        body.style.color = '#101828';
        root.style.colorScheme = 'light';
        body.style.colorScheme = 'light';
    }
};

const ThemeProvider = ({ children }) => {
    useEffect(() => {
        if (typeof window !== 'undefined') {
            window.__saltgoatThemeVersion = '20251108_01';
        }
    }, []);
    const [theme, setTheme] = useState(readInitialTheme);

    useEffect(() => {
        applyTheme(theme);
    }, [theme]);

    useEffect(() => {
        const handler = event => {
            if (event.matches) {
                setTheme('dark');
            } else if (!window.localStorage.getItem(STORAGE_KEY)) {
                setTheme('light');
            }
        };
        const media = window.matchMedia('(prefers-color-scheme: dark)');
        media.addEventListener('change', handler);
        return () => media.removeEventListener('change', handler);
    }, []);

    const toggleTheme = useCallback(() => {
        setTheme(prev => {
            const next = prev === 'dark' ? 'light' : 'dark';
            window.localStorage.setItem(STORAGE_KEY, next);
            return next;
        });
    }, []);

    const value = useMemo(() => ({ theme, toggleTheme }), [theme, toggleTheme]);

    return React.createElement(ThemeContext.Provider, { value }, children);
};

export { ThemeContext };
export default ThemeProvider;
