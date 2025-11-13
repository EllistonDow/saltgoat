import React from 'react';
import PropTypes from 'prop-types';

import { useSubMenu } from '@magento/peregrine/lib/talons/MegaMenu/useSubMenu';

import { useStyle } from '../../classify';
import defaultClasses from './submenu.module.css';
import SubmenuColumn from './submenuColumn';

const Submenu = props => {
    const {
        items,
        mainNavWidth,
        isFocused,
        subMenuState,
        handleCloseSubMenu,
        categoryUrlSuffix,
        onNavigate
    } = props;
    const PADDING_OFFSET = 20;
    const classes = useStyle(defaultClasses, props.classes);

    const talonProps = useSubMenu({
        isFocused,
        subMenuState,
        handleCloseSubMenu
    });

    const { isSubMenuActive } = talonProps;

    const subMenuClassname = isSubMenuActive
        ? classes.submenu_active
        : classes.submenu_inactive;

    const subMenus = items.map((category, index) => {
        const keyboardProps =
            index === items.length - 1 ? talonProps.keyboardProps : {};
        return (
            <SubmenuColumn
                index={index}
                keyboardProps={keyboardProps}
                key={category.uid}
                category={category}
                categoryUrlSuffix={categoryUrlSuffix}
                onNavigate={onNavigate}
                handleCloseSubMenu={handleCloseSubMenu}
            />
        );
    });

    const panelStyle = {
        width: 'min(calc(100% - clamp(24px, 4vw, 96px)), 1280px)',
        background: 'var(--sg-flyout-bg)',
        borderRadius: '32px',
        boxShadow: '0 40px 90px var(--sg-overlay-shadow)',
        padding: 'clamp(28px, 3vw, 48px)',
        backdropFilter: 'blur(24px)',
        WebkitBackdropFilter: 'blur(24px)',
        border: '1px solid var(--sg-flyout-border)'
    };

    const itemsStyle = {
        minWidth: mainNavWidth + PADDING_OFFSET,
        background: 'var(--sg-overlay-bg)',
        borderRadius: '24px',
        padding: 'clamp(12px, 2vw, 20px)',
        boxShadow: 'inset 0 0 0 1px var(--sg-flyout-border)'
    };

    return (
        <div className={subMenuClassname} data-cy="MegaMenu-submenu">
            <div
                className={classes.panel}
                style={panelStyle}
                data-cy="MegaMenu-panel"
            >
                <div
                    className={classes.submenuItems}
                    style={itemsStyle}
                    data-cy="MegaMenu-submenuItems"
                >
                    {subMenus}
                </div>
            </div>
        </div>
    );
};

export default Submenu;

Submenu.propTypes = {
    items: PropTypes.arrayOf(
        PropTypes.shape({
            children: PropTypes.array.isRequired,
            uid: PropTypes.string.isRequired,
            include_in_menu: PropTypes.number.isRequired,
            isActive: PropTypes.bool.isRequired,
            name: PropTypes.string.isRequired,
            path: PropTypes.array.isRequired,
            position: PropTypes.number.isRequired,
            url_path: PropTypes.string.isRequired
        })
    ).isRequired,
    mainNavWidth: PropTypes.number.isRequired,
    categoryUrlSuffix: PropTypes.string,
    onNavigate: PropTypes.func.isRequired,
    handleCloseSubMenu: PropTypes.func.isRequired
};
