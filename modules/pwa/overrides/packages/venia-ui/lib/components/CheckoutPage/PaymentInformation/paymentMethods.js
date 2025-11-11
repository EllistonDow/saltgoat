import React, { useEffect } from 'react';
import { shape, string, bool, func } from 'prop-types';
import { useIntl } from 'react-intl';

import { usePaymentMethods } from '@magento/peregrine/lib/talons/CheckoutPage/PaymentInformation/usePaymentMethods';

import { useStyle } from '../../../classify';
import RadioGroup from '@magento/venia-ui/lib/components/RadioGroup';
import Radio from '@magento/venia-ui/lib/components/RadioGroup/radio';
import defaultClasses from './paymentMethods.module.css';
import payments from './paymentMethodCollection';
import GenericPaymentMethod from '@saltgoat/venia-extension/src/components/Payments/Generic';

const PaymentMethods = props => {
    const {
        classes: propClasses,
        onPaymentError,
        onPaymentSuccess,
        resetShouldSubmit,
        shouldSubmit
    } = props;

    const { formatMessage } = useIntl();

    const classes = useStyle(defaultClasses, propClasses);

    const talonProps = usePaymentMethods({});

    const {
        availablePaymentMethods,
        currentSelectedPaymentMethod,
        handlePaymentMethodSelection,
        initialSelectedMethod,
        isLoading
    } = talonProps;

    if (isLoading) {
        return null;
    }

    useEffect(() => {
        if (!currentSelectedPaymentMethod && initialSelectedMethod) {
            handlePaymentMethodSelection({
                target: { value: initialSelectedMethod }
            });
        }
    }, [
        currentSelectedPaymentMethod,
        initialSelectedMethod,
        handlePaymentMethodSelection
    ]);

    const radios = availablePaymentMethods
        .map(({ code, title }) => {
            const id = `paymentMethod--${code}`;
            const isSelected = currentSelectedPaymentMethod === code;
            const PaymentComponent =
                payments[code] || GenericPaymentMethod || null;
            const renderedComponent =
                isSelected && PaymentComponent ? (
                    <PaymentComponent
                        onPaymentSuccess={onPaymentSuccess}
                        onPaymentError={onPaymentError}
                        resetShouldSubmit={resetShouldSubmit}
                        shouldSubmit={shouldSubmit}
                        title={title}
                        paymentCode={code}
                    />
                ) : null;

            return (
                <div key={code} className={classes.payment_method}>
                    <Radio
                        id={id}
                        label={title}
                        value={code}
                        classes={{
                            label: classes.radio_label
                        }}
                        checked={isSelected}
                        onChange={handlePaymentMethodSelection}
                    />
                    {renderedComponent}
                </div>
            );
        })
        .filter(paymentMethod => !!paymentMethod);

    const noPaymentMethodMessage = !radios.length ? (
        <div className={classes.payment_errors}>
            <span>
                {formatMessage({
                    id: 'checkoutPage.paymentLoadingError',
                    defaultMessage: 'There was an error loading payments.'
                })}
            </span>
            <span>
                {formatMessage({
                    id: 'checkoutPage.refreshOrTryAgainLater',
                    defaultMessage: 'Please refresh or try again later.'
                })}
            </span>
        </div>
    ) : null;

    return (
        <div className={classes.root}>
            <RadioGroup
                classes={{ root: classes.radio_group }}
                field="selectedPaymentMethod"
                initialValue={initialSelectedMethod}
            >
                {radios}
            </RadioGroup>
            {noPaymentMethodMessage}
        </div>
    );
};

export default PaymentMethods;

PaymentMethods.propTypes = {
    classes: shape({
        root: string,
        payment_method: string,
        radio_label: string
    }),
    onPaymentSuccess: func,
    onPaymentError: func,
    resetShouldSubmit: func,
    selectedPaymentMethod: string,
    shouldSubmit: bool
};
