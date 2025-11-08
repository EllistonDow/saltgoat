import { onError } from '@apollo/client/link/error';
import getWithPath from 'lodash.get';
import setWithPath from 'lodash.set';
import BrowserPersistence from '@magento/peregrine/lib/util/simplePersistence';

const storage = new BrowserPersistence();
const CART_AUTH_ERRORS = [
    'The current user cannot perform operations on cart',
    "The cart isn't active",
    'The cart isn’t active'
];

const queueCartReload = () => {
    if (typeof window === 'undefined') {
        return;
    }

    storage.removeItem('cartId');

    if (window.__saltgoatReloadingCart) {
        return;
    }
    window.__saltgoatReloadingCart = true;
    setTimeout(() => {
        window.location && window.location.reload();
    }, 10);
};

const shouldResetCart = message => {
    if (!message) {
        return false;
    }
    return CART_AUTH_ERRORS.some(err =>
        message.toLowerCase().startsWith(err.toLowerCase())
    );
};

export default function createErrorLink() {
    return onError(handler => {
        const { graphQLErrors, networkError, response } = handler;

        if (graphQLErrors) {
            graphQLErrors.forEach(({ message, locations, path }) => {
                console.log(
                    `[GraphQL error]: Message: ${message}, Location: ${locations}, Path: ${path}`
                );
                if (shouldResetCart(message)) {
                    queueCartReload();
                }
            });
        }

        if (networkError) {
            console.log(`[Network error]: ${networkError}`);
            if (networkError.statusCode === 403) {
                queueCartReload();
            }
        }

        if (response) {
            const { data, errors } = response;
            let pathToCartItems;

            errors.forEach(({ message, path }, index) => {
                if (
                    message === 'Some of the products are out of stock.' ||
                    message ===
                        'There are no source items with the in stock status' ||
                    message === 'The requested qty is not available'
                ) {
                    if (!pathToCartItems) {
                        pathToCartItems = path.slice(0, -1);
                    }

                    response.errors[index] = null;
                }
            });

            if (pathToCartItems) {
                const cartItems = getWithPath(data, pathToCartItems);
                const filteredCartItems = cartItems.filter(
                    cartItem => cartItem !== null
                );
                setWithPath(data, pathToCartItems, filteredCartItems);

                const filteredErrors = response.errors.filter(
                    error => error !== null
                );
                response.errors = filteredErrors.length
                    ? filteredErrors
                    : undefined;
            }
        }
    });
}
