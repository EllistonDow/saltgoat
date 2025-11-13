import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
    useApolloClient,
    useLazyQuery,
    useMutation,
    useQuery
} from '@apollo/client';
import { useHistory } from 'react-router-dom';

import { useEventingContext } from '../../context/eventing';
import { useUserContext } from '../../context/user';
import { useCartContext } from '../../context/cart';
import mergeOperations from '../../util/shallowMerge';
import DEFAULT_OPERATIONS from './checkoutPage.gql.js';
import CheckoutError from './CheckoutError';
import { useGoogleReCaptcha } from '../../hooks/useGoogleReCaptcha';

export const CHECKOUT_STEP = {
    SHIPPING_ADDRESS: 1,
    SHIPPING_METHOD: 2,
    PAYMENT: 3,
    REVIEW: 4
};

const getOrderNumber = placeOrderData =>
    placeOrderData?.placeOrder?.order?.order_number ||
    placeOrderData?.placeOrder?.order?.order_id ||
    null;

const safeSetOrderCount = value => {
    try {
        if (globalThis.localStorage) {
            globalThis.localStorage.setItem('orderCount', value);
        }
    } catch (error) {
        console.warn('Unable to persist orderCount', error);
    }
};

export const useCheckoutPage = (props = {}) => {
    const history = useHistory();
    const operations = mergeOperations(DEFAULT_OPERATIONS, props.operations);
    const {
        createCartMutation,
        getCheckoutDetailsQuery,
        getCustomerQuery,
        getOrderDetailsQuery,
        placeOrderMutation
    } = operations;

    const { generateReCaptchaData, recaptchaWidgetProps } = useGoogleReCaptcha({
        currentForm: 'PLACE_ORDER',
        formAction: 'placeOrder'
    });

    const apolloClient = useApolloClient();
    const [{ isSignedIn }] = useUserContext();
    const [{ cartId }, { createCart, removeCart }] = useCartContext();
    const [, { dispatch }] = useEventingContext();

    const shippingInformationRef = useRef(null);
    const shippingMethodRef = useRef(null);

    const [activeContent, setActiveContent] = useState('checkout');
    const [checkoutStep, setCheckoutStep] = useState(
        CHECKOUT_STEP.SHIPPING_ADDRESS
    );
    const [guestSignInUsername, setGuestSignInUsername] = useState('');
    const [isUpdating, setIsUpdating] = useState(false);
    const [placeOrderButtonClicked, setPlaceOrderButtonClicked] = useState(
        false
    );
    const [reviewOrderButtonClicked, setReviewOrderButtonClicked] = useState(
        false
    );
    const [isPlacingOrder, setIsPlacingOrder] = useState(false);
    const [orderDetailsSnapshot, setOrderDetailsSnapshot] = useState(null);

    const [fetchCartId] = useMutation(createCartMutation);
    const [
        placeOrder,
        {
            data: placeOrderData,
            error: placeOrderError,
            loading: placeOrderLoading
        }
    ] = useMutation(placeOrderMutation);
    const [
        fetchOrderDetails,
        { data: orderDetailsData, loading: orderDetailsLoading }
    ] = useLazyQuery(getOrderDetailsQuery, {
        fetchPolicy: 'no-cache'
    });

    useEffect(() => {
        if (orderDetailsData) {
            setOrderDetailsSnapshot(orderDetailsData);
        }
    }, [orderDetailsData]);
    const resolvedOrderDetailsData = orderDetailsSnapshot || orderDetailsData;

    const { data: customerData, loading: customerLoading } = useQuery(
        getCustomerQuery,
        { skip: !isSignedIn }
    );
    const {
        data: checkoutData,
        networkStatus: checkoutQueryNetworkStatus
    } = useQuery(getCheckoutDetailsQuery, {
        skip: !cartId,
        notifyOnNetworkStatusChange: true,
        variables: { cartId }
    });

    const cartItems = useMemo(() => {
        return checkoutData?.cart?.items || [];
    }, [checkoutData]);

    const isLoading = useMemo(() => {
        const checkoutQueryInFlight = checkoutQueryNetworkStatus
            ? checkoutQueryNetworkStatus < 7
            : true;
        return checkoutQueryInFlight || customerLoading;
    }, [checkoutQueryNetworkStatus, customerLoading]);

    const customer = customerData?.customer || null;

    const toggleAddressBookContent = useCallback(() => {
        setActiveContent(current =>
            current === 'checkout' ? 'addressBook' : 'checkout'
        );
    }, []);

    const toggleSignInContent = useCallback(() => {
        setActiveContent(current =>
            current === 'checkout' ? 'signIn' : 'checkout'
        );
    }, []);

    const checkoutError = useMemo(() => {
        if (placeOrderError) {
            return new CheckoutError(placeOrderError);
        }
        return null;
    }, [placeOrderError]);

    const scrollShippingInformationIntoView = useCallback(() => {
        if (shippingInformationRef.current) {
            shippingInformationRef.current.scrollIntoView({
                behavior: 'smooth'
            });
        }
    }, []);

    const scrollShippingMethodIntoView = useCallback(() => {
        if (shippingMethodRef.current) {
            shippingMethodRef.current.scrollIntoView({
                behavior: 'smooth'
            });
        }
    }, []);

    const setShippingInformationDone = useCallback(() => {
        if (checkoutStep === CHECKOUT_STEP.SHIPPING_ADDRESS) {
            setCheckoutStep(CHECKOUT_STEP.SHIPPING_METHOD);
        }
    }, [checkoutStep]);

    const setShippingMethodDone = useCallback(() => {
        if (checkoutStep === CHECKOUT_STEP.SHIPPING_METHOD) {
            setCheckoutStep(CHECKOUT_STEP.PAYMENT);
        }
    }, [checkoutStep]);

    const setPaymentInformationDone = useCallback(() => {
        if (checkoutStep === CHECKOUT_STEP.PAYMENT) {
            globalThis.scrollTo({
                top: 0,
                left: 0,
                behavior: 'smooth'
            });
            setCheckoutStep(CHECKOUT_STEP.REVIEW);
        }
    }, [checkoutStep]);

    const handleReviewOrder = useCallback(() => {
        if (checkoutStep === CHECKOUT_STEP.PAYMENT) {
            setReviewOrderButtonClicked(true);
        }
    }, [checkoutStep]);

    const handleReviewOrderEnterKeyPress = useCallback(
        event => {
            if (event.key === 'Enter') {
                handleReviewOrder();
            }
        },
        [handleReviewOrder]
    );

    const resetReviewOrderButtonClicked = useCallback(() => {
        setReviewOrderButtonClicked(false);
    }, []);

    const handlePlaceOrder = useCallback(async () => {
        if (!cartId || placeOrderLoading || orderDetailsLoading) {
            return;
        }
        await fetchOrderDetails({
            variables: { cartId }
        });
        setPlaceOrderButtonClicked(true);
        setIsPlacingOrder(true);
        safeSetOrderCount('1');
    }, [cartId, fetchOrderDetails, orderDetailsLoading, placeOrderLoading]);

    const handlePlaceOrderEnterKeyPress = useCallback(
        event => {
            if (event.key === 'Enter') {
                handlePlaceOrder();
            }
        },
        [handlePlaceOrder]
    );

    useEffect(() => {
        if (isSignedIn) {
            setActiveContent('checkout');
        }
    }, [isSignedIn]);

    useEffect(() => {
        if (!isPlacingOrder || !resolvedOrderDetailsData || !cartId) {
            return;
        }

        let isCancelled = false;
        const placeOrderAndCleanup = async () => {
            try {
                const reCaptchaData = await generateReCaptchaData();
                await placeOrder({
                    variables: { cartId },
                    ...reCaptchaData
                });
                if (isCancelled) {
                    return;
                }
                await removeCart();
                try {
                    apolloClient.cache.evict({
                        fieldName: 'cart'
                    });
                    apolloClient.cache.gc();
                } catch (cacheError) {
                    await apolloClient.resetStore();
                }
                await createCart({ fetchCartId });
            } catch (error) {
                console.error(
                    'An error occurred during when placing the order',
                    error
                );
                if (!isCancelled) {
                    setPlaceOrderButtonClicked(false);
                }
            } finally {
                if (!isCancelled) {
                    setIsPlacingOrder(false);
                }
            }
        };

        placeOrderAndCleanup();

        return () => {
            isCancelled = true;
        };
    }, [
        apolloClient,
        cartId,
        createCart,
        fetchCartId,
        generateReCaptchaData,
        placeOrder,
        removeCart,
        resolvedOrderDetailsData,
        isPlacingOrder
    ]);

    useEffect(() => {
        if (
            checkoutStep === CHECKOUT_STEP.SHIPPING_ADDRESS &&
            cartItems.length
        ) {
            dispatch({
                type: 'CHECKOUT_PAGE_VIEW',
                payload: {
                    cart_id: cartId,
                    products: cartItems
                }
            });
        } else if (reviewOrderButtonClicked) {
            dispatch({
                type: 'CHECKOUT_REVIEW_BUTTON_CLICKED',
                payload: { cart_id: cartId }
            });
        } else if (
            placeOrderButtonClicked &&
            resolvedOrderDetailsData &&
            resolvedOrderDetailsData.cart
        ) {
            const shippingMethods =
                resolvedOrderDetailsData.cart.shipping_addresses?.reduce(
                    (acc, address) => [
                        ...acc,
                        {
                            ...address.selected_shipping_method
                        }
                    ],
                    []
                ) || [];

            const payload = {
                cart_id: cartId,
                amount: resolvedOrderDetailsData.cart.prices,
                shipping: shippingMethods,
                payment: resolvedOrderDetailsData.cart.selected_payment_method,
                products: resolvedOrderDetailsData.cart.items
            };

            if (isPlacingOrder) {
                dispatch({
                    type: 'CHECKOUT_PLACE_ORDER_BUTTON_CLICKED',
                    payload
                });
            } else {
                const orderNumber = getOrderNumber(placeOrderData);
                if (
                    orderNumber &&
                    resolvedOrderDetailsData.cart?.id === cartId
                ) {
                    dispatch({
                        type: 'ORDER_CONFIRMATION_PAGE_VIEW',
                        payload: {
                            order_number: orderNumber,
                            ...payload
                        }
                    });
                }
            }
        }
    }, [
        cartId,
        cartItems,
        checkoutStep,
        dispatch,
        isPlacingOrder,
        placeOrderButtonClicked,
        placeOrderData,
        resolvedOrderDetailsData,
        reviewOrderButtonClicked
    ]);

    useEffect(() => {
        const orderNumber = getOrderNumber(placeOrderData);
        if (!orderNumber) {
            if (placeOrderData) {
                console.warn(
                    'placeOrder completed without an order number payload'
                );
            }
            return;
        }

        const confirmationItems =
            resolvedOrderDetailsData?.cart?.items || cartItems;

        setPlaceOrderButtonClicked(false);
        setReviewOrderButtonClicked(false);
        setCheckoutStep(CHECKOUT_STEP.SHIPPING_ADDRESS);
        setActiveContent('checkout');

        if (isSignedIn) {
            history.push('/order-confirmation', {
                orderNumber,
                items: confirmationItems
            });
        } else {
            history.push('/checkout');
        }
    }, [
        cartItems,
        history,
        isSignedIn,
        placeOrderData,
        resolvedOrderDetailsData
    ]);

    return {
        activeContent,
        availablePaymentMethods:
            checkoutData?.cart?.available_payment_methods || null,
        cartItems,
        checkoutStep,
        customer,
        error: checkoutError,
        guestSignInUsername,
        handlePlaceOrder,
        handlePlaceOrderEnterKeyPress,
        hasError: Boolean(checkoutError),
        isCartEmpty: !(checkoutData && checkoutData?.cart?.total_quantity),
        isGuestCheckout: !isSignedIn,
        isLoading,
        isUpdating,
        orderDetailsLoading,
        orderDetailsData: resolvedOrderDetailsData,
        orderNumber: getOrderNumber(placeOrderData),
        placeOrderLoading,
        placeOrderButtonClicked,
        recaptchaWidgetProps,
        reviewOrderButtonClicked,
        handleReviewOrder,
        handleReviewOrderEnterKeyPress,
        resetReviewOrderButtonClicked,
        scrollShippingInformationIntoView,
        scrollShippingMethodIntoView,
        setCheckoutStep,
        setGuestSignInUsername,
        setIsUpdating,
        setPaymentInformationDone,
        setShippingInformationDone,
        setShippingMethodDone,
        shippingInformationRef,
        shippingMethodRef,
        toggleAddressBookContent,
        toggleSignInContent
    };
};
