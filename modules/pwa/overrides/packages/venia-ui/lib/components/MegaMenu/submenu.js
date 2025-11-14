import React, { useContext } from 'react';
import PropTypes from 'prop-types';

import { useSubMenu } from '@magento/peregrine/lib/talons/MegaMenu/useSubMenu';

import { useStyle } from '../../classify';
import defaultClasses from './submenu.module.css';
import { ThemeContext } from '@saltgoat/venia-extension/src/components/ThemeProvider';
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
    const { theme } = useContext(ThemeContext);

    const glassTone =
        theme === 'light'
            ? {
                  panelBg: 'rgba(255, 255, 255, 0.95)',
                  panelBorder: 'rgba(15, 23, 42, 0.12)',
                  panelShadow: '0 40px 90px rgba(15, 23, 42, 0.16)',
                  itemsBg: 'rgba(247, 249, 255, 0.96)',
                  itemsBorder: 'rgba(15, 23, 42, 0.08)',
                  text: '#101828'
              }
            : {
                  panelBg: 'rgba(5, 8, 18, 0.9)',
                  panelBorder: 'rgba(255, 255, 255, 0.12)',
                  panelShadow: '0 40px 90px rgba(5, 8, 18, 0.65)',
                  itemsBg: 'rgba(7, 11, 22, 0.92)',
                  itemsBorder: 'rgba(255, 255, 255, 0.08)',
                  text: '#f4f6fb'
              };

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
        background: glassTone.panelBg,
        borderRadius: '32px',
        boxShadow: glassTone.panelShadow,
        padding: 'clamp(28px, 3vw, 48px)',
        backdropFilter: 'blur(24px)',
        WebkitBackdropFilter: 'blur(24px)',
        border: `1px solid ${glassTone.panelBorder}`,
        color: glassTone.text
    };

    const itemsStyle = {
        minWidth: mainNavWidth + PADDING_OFFSET,
        background: glassTone.itemsBg,
        borderRadius: '24px',
        padding: 'clamp(12px, 2vw, 20px)',
        boxShadow: `inset 0 0 0 1px ${glassTone.itemsBorder}`,
        color: glassTone.text
    };

    return (
        <div className={subMenuClassname} data-cy="MegaMenu-submenu">
            <div
                className={`${classes.panel} sg-glass`}
                style={panelStyle}
                data-cy="MegaMenu-panel"
            >
                <div
                    className={`${classes.submenuItems} sg-glass`}
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
