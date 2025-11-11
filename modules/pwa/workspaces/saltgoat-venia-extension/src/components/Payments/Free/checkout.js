import React, { useEffect } from 'react';
import { FormattedMessage } from 'react-intl';
import PropTypes from 'prop-types';

import styles from './freePayment.module.css';

const FreeCheckoutMethod = ({
    onPaymentSuccess,
    resetShouldSubmit,
    shouldSubmit
}) => {
    // Inform checkout state that payment step is satisfied as soon as the
    // component mounts (no payment data is required).
    useEffect(() => {
        if (typeof onPaymentSuccess === 'function') {
            onPaymentSuccess();
        }
    }, [onPaymentSuccess]);

    useEffect(() => {
        if (shouldSubmit && typeof onPaymentSuccess === 'function') {
            onPaymentSuccess();
            if (typeof resetShouldSubmit === 'function') {
                resetShouldSubmit();
            }
        }
    }, [onPaymentSuccess, resetShouldSubmit, shouldSubmit]);

    return (
        <div className={styles.container} data-cy="FreePayment-root">
            <FormattedMessage
                id="payment.free.description"
                defaultMessage="This order total is ¥0.00 — no payment information is required."
            />
        </div>
    );
};

FreeCheckoutMethod.propTypes = {
    onPaymentSuccess: PropTypes.func,
    resetShouldSubmit: PropTypes.func,
    shouldSubmit: PropTypes.bool
};

export default FreeCheckoutMethod;
