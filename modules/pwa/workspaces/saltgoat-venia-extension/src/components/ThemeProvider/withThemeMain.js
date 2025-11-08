import React, { useContext } from 'react';
import { ThemeContext } from './index';

const withThemeMain = OriginalComponent => {
    const ThemedMain = props => {
        const { theme } = useContext(ThemeContext);
        return (
            <div
                data-theme-container={theme}
                style={{
                    background: 'var(--sg-page-bg)',
                    color: 'var(--sg-text)',
                    minHeight: '100vh',
                    transition: 'background 0.3s ease, color 0.3s ease'
                }}
            >
                <OriginalComponent {...props} />
            </div>
        );
    };

    ThemedMain.displayName = `WithThemeMain(${
        OriginalComponent.displayName || OriginalComponent.name || 'Component'
    })`;

    return ThemedMain;
};

export default withThemeMain;
