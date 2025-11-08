import { useCallback, useEffect } from 'react';
import { useMutation } from '@apollo/client';
import mergeOperations from '@magento/peregrine/lib/util/shallowMerge';
import { useCartContext } from '@magento/peregrine/lib/context/cart';

import DEFAULT_OPERATIONS from './bankTransfer.gql';

export const useBankTransfer = props => {
    const operations = mergeOperations(DEFAULT_OPERATIONS, props.operations);
    const { setPaymentMethodOnCartMutation } = operations;

    const [{ cartId }] = useCartContext();
    const [
        setPaymentMethod,
        { called, error, loading }
    ] = useMutation(setPaymentMethodOnCartMutation);

    const onBillingAddressChangedSuccess = useCallback(() => {
        setPaymentMethod({
            variables: { cartId }
        });
    }, [cartId, setPaymentMethod]);

    const onBillingAddressChangedError = useCallback(() => {
        props.resetShouldSubmit();
    }, [props]);

    useEffect(() => {
        if (!called) {
            return;
        }

        if (!loading && !error) {
            props.onPaymentSuccess?.();
        }

        if (!loading && error) {
            props.onPaymentError?.();
        }
    }, [called, error, loading, props]);

    return {
        onBillingAddressChangedError,
        onBillingAddressChangedSuccess
    };
};

export default useBankTransfer;
