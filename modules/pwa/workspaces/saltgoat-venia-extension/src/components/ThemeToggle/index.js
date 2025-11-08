import React, { useContext } from 'react';
import classes from './themeToggle.module.css';
import '../../styles/theme.global.module.css';
import { ThemeContext } from '../ThemeProvider';

const ThemeToggle = () => {
    const { theme, toggleTheme } = useContext(ThemeContext);
    const isDark = theme === 'dark';
    const label = isDark ? '切换为亮色模式' : '切换为暗色模式';

    return (
        <button
            type="button"
            className={classes.toggle}
            onClick={toggleTheme}
            aria-label={label}
            title={label}
            data-theme-mode={theme}
        >
            <span aria-hidden="true" className={classes.icon}>
                {isDark ? '☾' : '☀'}
            </span>
            <span className={classes.label}>
                {isDark ? 'Dark' : 'Light'}
            </span>
        </button>
    );
};

export default ThemeToggle;
