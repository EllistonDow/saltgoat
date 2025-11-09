import React, { useContext } from 'react';
import { Sun, Moon } from 'react-feather';
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
            <span className={classes.srOnly}>{label}</span>
            <span className={classes.iconOrbit} aria-hidden="true">
                <Sun className={classes.sun} size={22} />
                <Moon className={classes.moon} size={22} />
            </span>
        </button>
    );
};

export default ThemeToggle;
