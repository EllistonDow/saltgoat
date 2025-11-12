import React, { useEffect, useMemo } from 'react';
import { shape, string, bool, func } from 'prop-types';
import { useIntl } from 'react-intl';

import { usePaymentMethods } from '@magento/peregrine/lib/talons/CheckoutPage/PaymentInformation/usePaymentMethods';

import { useStyle } from '../../../classify';
import RadioGroup from '@magento/venia-ui/lib/components/RadioGroup';
import Radio from '@magento/venia-ui/lib/components/RadioGroup/radio';
import defaultClasses from './paymentMethods.module.css';
import payments from './paymentMethodCollection';
import GenericPaymentMethod from '@saltgoat/venia-extension/src/components/Payments/Generic';

const normalizeDisabledCodes = () => {
    const raw =
        process.env.SALTGOAT_PWA_DISABLED_PAYMENTS ||
        process.env.NEXT_PUBLIC_SALTGOAT_DISABLED_PAYMENTS ||
        '';
    return raw
        .split(',')
        .map(code => code.trim())
        .filter(Boolean)
        .map(code => code.toLowerCase());
};

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

    const disabledCodes = useMemo(
        () => normalizeDisabledCodes(),
        []
    );

    const filteredPaymentMethods = useMemo(() => {
        if (!disabledCodes.length) {
            return availablePaymentMethods;
        }
        return availablePaymentMethods.filter(({ code }) => {
            if (!code) {
                return true;
            }
            return !disabledCodes.includes(code.toLowerCase());
        });
    }, [availablePaymentMethods, disabledCodes]);

    if (isLoading) {
        return null;
    }

    const resolvedInitialMethod = useMemo(() => {
        if (
            currentSelectedPaymentMethod &&
            filteredPaymentMethods.some(
                method => method.code === currentSelectedPaymentMethod
            )
        ) {
            return currentSelectedPaymentMethod;
        }
        if (
            initialSelectedMethod &&
            filteredPaymentMethods.some(
                method => method.code === initialSelectedMethod
            )
        ) {
            return initialSelectedMethod;
        }
        return filteredPaymentMethods[0]?.code || null;
    }, [
        currentSelectedPaymentMethod,
        filteredPaymentMethods,
        initialSelectedMethod
    ]);

    useEffect(() => {
        if (!currentSelectedPaymentMethod && resolvedInitialMethod) {
            handlePaymentMethodSelection({
                target: { value: resolvedInitialMethod }
            });
        }
    }, [
        currentSelectedPaymentMethod,
        resolvedInitialMethod,
        handlePaymentMethodSelection
    ]);

    const radios = filteredPaymentMethods
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
