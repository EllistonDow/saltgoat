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
    document.documentElement.dataset.theme = theme;
    document.body.dataset.theme = theme;
    if (theme === 'dark') {
        document.body.style.backgroundColor = '#0b0f1d';
        document.body.style.color = '#f4f6fb';
    } else {
        document.body.style.backgroundColor = '#f7f9ff';
        document.body.style.color = '#101828';
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
