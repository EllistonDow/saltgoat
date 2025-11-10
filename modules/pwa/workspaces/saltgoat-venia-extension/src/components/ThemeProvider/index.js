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
