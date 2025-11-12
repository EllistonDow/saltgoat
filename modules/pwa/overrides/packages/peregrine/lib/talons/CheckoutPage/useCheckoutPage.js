import { useCallback, useEffect, useMemo, useState, useRef } from 'react';
import {
    useApolloClient,
    useLazyQuery,
    useMutation,
    useQuery
} from '@apollo/client';
import { useEventingContext } from '../../context/eventing';

import { useHistory } from 'react-router-dom';

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
    placeOrderData?.placeOrder?.order?.order_number || null;

const safeSetOrderCount = value => {
    try {
        if (globalThis.localStorage) {
            globalThis.localStorage.setItem('orderCount', value);
        }
    } catch (error) {
        console.warn('Unable to persist orderCount', error);
    }
};

/**
 *
 * @param {DocumentNode} props.operations.getCheckoutDetailsQuery query to fetch checkout details
 * @param {DocumentNode} props.operations.getCustomerQuery query to fetch customer details
 * @param {DocumentNode} props.operations.getOrderDetailsQuery query to fetch order details
 * @param {DocumentNode} props.operations.createCartMutation mutation to create a new cart
 * @param {DocumentNode} props.operations.placeOrderMutation mutation to place order
 *
 * @returns { ... } // unchanged docstring omitted for brevity
 */
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

    const [reviewOrderButtonClicked, setReviewOrderButtonClicked] = useState(
        false
    );

    const shippingInformationRef = useRef();
    const shippingMethodRef = useRef();

    const apolloClient = useApolloClient();
    const [isUpdating, setIsUpdating] = useState(false);
    const [placeOrderButtonClicked, setPlaceOrderButtonClicked] = useState(
        false
    );
    const [activeContent, setActiveContent] = useState('checkout');
    const [checkoutStep, setCheckoutStep] = useState(
        CHECKOUT_STEP.SHIPPING_ADDRESS
    );
    const [guestSignInUsername, setGuestSignInUsername] = useState('');

    const [{ isSignedIn }] = useUserContext();
    const [{ cartId }, { createCart, removeCart }] = useCartContext();

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
        getOrderDetails,
        { data: orderDetailsData, loading: orderDetailsLoading }
    ] = useLazyQuery(getOrderDetailsQuery, {
        fetchPolicy: 'no-cache'
    });

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
        variables: {
            cartId
        }
    });

    const cartItems = useMemo(() => {
        return (checkoutData && checkoutData?.cart?.items) || [];
    }, [checkoutData]);

    const isLoading = useMemo(() => {
        const checkoutQueryInFlight = checkoutQueryNetworkStatus
            ? checkoutQueryNetworkStatus < 7
            : true;

        return checkoutQueryInFlight || customerLoading;
    }, [checkoutQueryNetworkStatus, customerLoading]);

    const customer = customerData && customerData.customer;

    const toggleAddressBookContent = useCallback(() => {
        setActiveContent(currentlyActive =>
            currentlyActive === 'checkout' ? 'addressBook' : 'checkout'
        );
    }, []);
    const toggleSignInContent = useCallback(() => {
        setActiveContent(currentlyActive =>
            currentlyActive === 'checkout' ? 'signIn' : 'checkout'
        );
    }, []);

    const checkoutError = useMemo(() => {
        if (placeOrderError) {
            return new CheckoutError(placeOrderError);
        }
    }, [placeOrderError]);

    const handleReviewOrder = useCallback(() => {
        setReviewOrderButtonClicked(true);
    }, []);

    const handleReviewOrderEnterKeyPress = useCallback(() => {
        event => {
            if (event.key === 'Enter') {
                handleReviewOrder();
            }
        };
    }, [handleReviewOrder]);

    const resetReviewOrderButtonClicked = useCallback(() => {
        setReviewOrderButtonClicked(false);
    }, []);

    const scrollShippingInformationIntoView = useCallback(() => {
        if (shippingInformationRef.current) {
            shippingInformationRef.current.scrollIntoView({
                behavior: 'smooth'
            });
        }
    }, [shippingInformationRef]);

    const setShippingInformationDone = useCallback(() => {
        if (checkoutStep === CHECKOUT_STEP.SHIPPING_ADDRESS) {
            setCheckoutStep(CHECKOUT_STEP.SHIPPING_METHOD);
        }
    }, [checkoutStep]);

    const scrollShippingMethodIntoView = useCallback(() => {
        if (shippingMethodRef.current) {
            shippingMethodRef.current.scrollIntoView({
                behavior: 'smooth'
            });
        }
    }, [shippingMethodRef]);

    const setShippingMethodDone = useCallback(() => {
        if (checkoutStep === CHECKOUT_STEP.SHIPPING_METHOD) {
            setCheckoutStep(CHECKOUT_STEP.PAYMENT);
        }
    }, [checkoutStep]);

    const setPaymentInformationDone = useCallback(() => {
        if (checkoutStep === CHECKOUT_STEP.PAYMENT) {
            globalThis.scrollTo({
                left: 0,
                top: 0,
                behavior: 'smooth'
            });
            setCheckoutStep(CHECKOUT_STEP.REVIEW);
        }
    }, [checkoutStep]);

    const [isPlacingOrder, setIsPlacingOrder] = useState(false);

    const handlePlaceOrder = useCallback(async () => {
        await getOrderDetails({
            variables: {
                cartId
            }
        });
        setPlaceOrderButtonClicked(true);
        setIsPlacingOrder(true);
        safeSetOrderCount('1');
    }, [cartId, getOrderDetails]);

    const handlePlaceOrderEnterKeyPress = useCallback(() => {
        event => {
            if (event.key === 'Enter') {
                handlePlaceOrder();
            }
        };
    }, [handlePlaceOrder]);

    const [, { dispatch }] = useEventingContext();

    useEffect(() => {
        if (isSignedIn) {
            setActiveContent('checkout');
        }
    }, [isSignedIn]);

    useEffect(() => {
        async function placeOrderAndCleanup() {
            try {
                const reCaptchaData = await generateReCaptchaData();

                await placeOrder({
                    variables: {
                        cartId
                    },
                    ...reCaptchaData
                });
                await removeCart();
                await apolloClient.clearCacheData(apolloClient, 'cart');

                await createCart({
                    fetchCartId
                });
            } catch (err) {
                console.error(
                    'An error occurred during when placing the order',
                    err
                );
                setPlaceOrderButtonClicked(false);
            }
        }

        if (orderDetailsData && isPlacingOrder) {
            setIsPlacingOrder(false);
            placeOrderAndCleanup();
        }
    }, [
        apolloClient,
        cartId,
        createCart,
        fetchCartId,
        generateReCaptchaData,
        orderDetailsData,
        placeOrder,
        removeCart,
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
                payload: {
                    cart_id: cartId
                }
            });
        } else if (
            placeOrderButtonClicked &&
            orderDetailsData &&
            orderDetailsData.cart
        ) {
            const shipping =
                orderDetailsData.cart?.shipping_addresses &&
                orderDetailsData.cart.shipping_addresses.reduce(
                    (result, item) => {
                        return [
                            ...result,
                            {
                                ...item.selected_shipping_method
                            }
                        ];
                    },
                    []
                );
            const eventPayload = {
                cart_id: cartId,
                amount: orderDetailsData.cart.prices,
                shipping: shipping,
                payment: orderDetailsData.cart.selected_payment_method,
                products: orderDetailsData.cart.items
            };
            if (isPlacingOrder) {
                dispatch({
                    type: 'CHECKOUT_PLACE_ORDER_BUTTON_CLICKED',
                    payload: eventPayload
                });
            } else {
                const orderNumber = getOrderNumber(placeOrderData);
                if (
                    orderNumber &&
                    orderDetailsData?.cart?.id === cartId
                ) {
                    dispatch({
                        type: 'ORDER_CONFIRMATION_PAGE_VIEW',
                        payload: {
                            order_number: orderNumber,
                            ...eventPayload
                        }
                    });
                }
            }
        }
    }, [
        placeOrderButtonClicked,
        cartId,
        checkoutStep,
        orderDetailsData,
        cartItems,
        isLoading,
        dispatch,
        placeOrderData,
        isPlacingOrder,
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
        if (isSignedIn && placeOrderData) {
            history.push('/order-confirmation', {
                orderNumber,
                items: cartItems
            });
        } else if (!isSignedIn && placeOrderData) {
            history.push('/checkout');
        }
    }, [isSignedIn, placeOrderData, cartItems, history]);

    return {
        activeContent,
        availablePaymentMethods: checkoutData
            ? checkoutData?.cart?.available_payment_methods
            : null,
        cartItems,
        checkoutStep,
        customer,
        error: checkoutError,
        guestSignInUsername,
        handlePlaceOrder,
        handlePlaceOrderEnterKeyPress,
        hasError: !!checkoutError,
        isCartEmpty: !(checkoutData && checkoutData?.cart?.total_quantity),
        isGuestCheckout: !isSignedIn,
        isLoading,
        isUpdating,
        orderDetailsData,
        orderDetailsLoading,
        orderNumber: getOrderNumber(placeOrderData),
        placeOrderLoading,
        placeOrderButtonClicked,
        setCheckoutStep,
        setGuestSignInUsername,
        setIsUpdating,
        setShippingInformationDone,
        setShippingMethodDone,
        setPaymentInformationDone,
        scrollShippingInformationIntoView,
        shippingInformationRef,
        shippingMethodRef,
        scrollShippingMethodIntoView,
        resetReviewOrderButtonClicked,
        handleReviewOrder,
        handleReviewOrderEnterKeyPress,
        reviewOrderButtonClicked,
        recaptchaWidgetProps,
        toggleAddressBookContent,
        toggleSignInContent
    };
};
