import React from 'react';
import { shape, string } from 'prop-types';
import { useAccountMenu } from '@magento/peregrine/lib/talons/Header/useAccountMenu';

import { useStyle } from '../../classify';
import CreateAccount from '../CreateAccount';
import SignIn from '../SignIn/signIn';
import AccountMenuItems from './accountMenuItems';
import ForgotPassword from '../ForgotPassword';
import defaultClasses from './accountMenu.module.css';

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

    const panelStyle = {
        background: 'var(--sg-overlay-bg, rgba(7, 11, 22, 0.92))',
        borderRadius: '28px',
        boxShadow: '0 30px 70px var(--sg-overlay-shadow, rgba(5, 8, 16, 0.6))',
        backdropFilter: 'blur(20px)',
        WebkitBackdropFilter: 'blur(20px)',
        border: '1px solid var(--sg-flyout-border, rgba(255, 255, 255, 0.12))'
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
