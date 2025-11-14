import React, { useContext } from 'react';
import { shape, string } from 'prop-types';
import { useAccountMenu } from '@magento/peregrine/lib/talons/Header/useAccountMenu';

import { useStyle } from '../../classify';
import CreateAccount from '../CreateAccount';
import SignIn from '../SignIn/signIn';
import AccountMenuItems from './accountMenuItems';
import ForgotPassword from '../ForgotPassword';
import defaultClasses from './accountMenu.module.css';
import { ThemeContext } from '@saltgoat/venia-extension/src/components/ThemeProvider';

const AccountMenu = React.forwardRef((props, ref) => {
    const {
        handleTriggerClick,
        accountMenuIsOpen,
        setAccountMenuIsOpen
    } = props;
    const talonProps = useAccountMenu({
        accountMenuIsOpen,
        setAccountMenuIsOpen
    });
    const {
        view,
        username,
        handleAccountCreation,
        handleSignOut,
        handleForgotPassword,
        handleCancel,
        handleCreateAccount,
        updateUsername
    } = talonProps;

    const classes = useStyle(defaultClasses, props.classes);
    const { theme } = useContext(ThemeContext);
    const rootClass = accountMenuIsOpen
        ? classes.root_open
        : classes.root_closed;
    const contentsClass = accountMenuIsOpen
        ? classes.contents_open
        : classes.contents;

    let dropdownContents = null;

    switch (view) {
        case 'ACCOUNT': {
            dropdownContents = <AccountMenuItems onSignOut={handleSignOut} />;
            break;
        }
        case 'FORGOT_PASSWORD': {
            dropdownContents = (
                <ForgotPassword
                    initialValues={{ email: username }}
                    onCancel={handleCancel}
                />
            );
            break;
        }
        case 'CREATE_ACCOUNT': {
            dropdownContents = (
                <CreateAccount
                    classes={{ root: classes.createAccount }}
                    initialValues={{ email: username }}
                    isCancelButtonHidden={false}
                    onSubmit={handleAccountCreation}
                    onCancel={handleCancel}
                />
            );
            break;
        }
        case 'SIGNIN':
        default: {
            dropdownContents = (
                <SignIn
                    handleTriggerClick={handleTriggerClick}
                    classes={{
                        modal_active: classes.loading
                    }}
                    setDefaultUsername={updateUsername}
                    showCreateAccount={handleCreateAccount}
                    showForgotPassword={handleForgotPassword}
                />
            );
            break;
        }
    }

    const glassTone =
        theme === 'light'
            ? {
                  bg: 'rgba(255, 255, 255, 0.94)',
                  border: 'rgba(15, 23, 42, 0.12)',
                  shadow: '0 30px 80px rgba(15, 23, 42, 0.16)',
                  text: '#101828'
              }
            : {
                  bg: 'rgba(7, 11, 22, 0.92)',
                  border: 'rgba(255, 255, 255, 0.12)',
                  shadow: '0 30px 70px rgba(5, 8, 16, 0.6)',
                  text: '#f4f6fb'
              };

    const panelStyle = {
        background: glassTone.bg,
        borderRadius: '28px',
        boxShadow: glassTone.shadow,
        backdropFilter: 'blur(20px)',
        WebkitBackdropFilter: 'blur(20px)',
        border: `1px solid ${glassTone.border}`,
        color: glassTone.text
    };

    return (
        <aside className={rootClass} data-cy="AccountMenu-root">
            <div ref={ref} className={contentsClass}>
                <div
                    className={`${classes.panel} sg-glass`}
                    style={panelStyle}
                    data-cy="AccountMenu-panel"
                >
                    {accountMenuIsOpen ? dropdownContents : null}
                </div>
            </div>
        </aside>
    );
});

export default AccountMenu;

AccountMenu.propTypes = {
    classes: shape({
        root: string,
        root_closed: string,
        root_open: string,
        link: string,
        contents_open: string,
        contents: string,
        panel: string
    })
};
