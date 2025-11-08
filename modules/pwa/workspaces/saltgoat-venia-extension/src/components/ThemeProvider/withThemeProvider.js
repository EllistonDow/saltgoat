import React from 'react';
import ThemeProvider from './index';

const withThemeProvider = OriginalComponent => {
    const Wrapped = props =>
        React.createElement(
            ThemeProvider,
            null,
            React.createElement(OriginalComponent, props)
        );

    Wrapped.displayName = `WithThemeProvider(${
        OriginalComponent.displayName || OriginalComponent.name || 'Component'
    })`;

    return Wrapped;
};

export default withThemeProvider;
