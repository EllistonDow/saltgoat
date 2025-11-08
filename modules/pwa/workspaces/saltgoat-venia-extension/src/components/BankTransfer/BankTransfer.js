import React from 'react';
import { shape, string, bool, func } from 'prop-types';
import { useIntl } from 'react-intl';
import { useStyle } from '@magento/venia-ui/lib/classify';
import BillingAddress from '@magento/venia-ui/lib/components/CheckoutPage/BillingAddress';

import defaultClasses from './bankTransfer.module.css';
import { useBankTransfer } from './useBankTransfer';

const BankTransfer = props => {
    const {
        classes: propClasses,
        onPaymentError,
        onPaymentSuccess,
        resetShouldSubmit,
        shouldSubmit
    } = props;

    const classes = useStyle(defaultClasses, propClasses);
    const { formatMessage } = useIntl();

    const {
        onBillingAddressChangedError,
        onBillingAddressChangedSuccess
    } = useBankTransfer({
        onPaymentError,
        onPaymentSuccess,
        resetShouldSubmit
    });

    const instructions =
        props.instructions ||
        formatMessage({
            id: 'bankTransfer.instructions',
            defaultMessage:
                'Transfer the full order total to the account below. Fulfilment begins once the payment is confirmed.'
        });
    const beneficiary =
        props.beneficiary ||
        formatMessage({
            id: 'bankTransfer.beneficiary',
            defaultMessage: 'SaltGoat Operations'
        });
    const reference =
        props.reference ||
        formatMessage({
            id: 'bankTransfer.reference',
            defaultMessage: 'Use your order number as the payment reference.'
        });

    return (
        <div className={classes.root}>
            <div className={classes.block}>
                <p className={classes.heading}>
                    {formatMessage({
                        id: 'bankTransfer.title',
                        defaultMessage: 'Manual Bank Transfer'
                    })}
                </p>
                <p className={classes.text}>{instructions}</p>
                <p className={classes.label}>
                    {formatMessage({
                        id: 'bankTransfer.beneficiaryLabel',
                        defaultMessage: 'Beneficiary'
                    })}
                    :
                </p>
                <p className={classes.text}>{beneficiary}</p>
                <p className={classes.text}>{reference}</p>
            </div>
            <BillingAddress
                shouldSubmit={shouldSubmit}
                resetShouldSubmit={resetShouldSubmit}
                onBillingAddressChangedError={onBillingAddressChangedError}
                onBillingAddressChangedSuccess={onBillingAddressChangedSuccess}
            />
        </div>
    );
};

BankTransfer.propTypes = {
    beneficiary: string,
    classes: shape({
        root: string
    }),
    instructions: string,
    onPaymentError: func,
    onPaymentSuccess: func,
    reference: string,
    resetShouldSubmit: func.isRequired,
    shouldSubmit: bool.isRequired
};

export default BankTransfer;
