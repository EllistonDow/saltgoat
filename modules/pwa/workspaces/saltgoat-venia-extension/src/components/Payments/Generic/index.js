import React, { useEffect } from 'react';
import PropTypes from 'prop-types';
import { FormattedMessage } from 'react-intl';

import styles from '../Free/freePayment.module.css';

const GenericPaymentMethod = ({
    onPaymentSuccess,
    onPaymentError,
    resetShouldSubmit,
    shouldSubmit,
    title
}) => {
    useEffect(() => {
        if (shouldSubmit) {
            if (typeof onPaymentSuccess === 'function') {
                onPaymentSuccess();
            }
            if (typeof resetShouldSubmit === 'function') {
                resetShouldSubmit();
            }
        }
    }, [onPaymentSuccess, onPaymentError, resetShouldSubmit, shouldSubmit]);

    return (
        <div className={styles.container} data-cy="GenericPayment-root">
            <strong>{title}</strong>
            <div>
                <FormattedMessage
                    id="payment.generic.description"
                    defaultMessage="Complete payment for this method on the next step."
                />
            </div>
        </div>
    );
};

GenericPaymentMethod.propTypes = {
    onPaymentError: PropTypes.func,
    onPaymentSuccess: PropTypes.func,
    resetShouldSubmit: PropTypes.func,
    shouldSubmit: PropTypes.bool,
    title: PropTypes.string
};

export default GenericPaymentMethod;
