import React from 'react';
import { FormattedMessage } from 'react-intl';

import styles from './freePayment.module.css';

const FreeEditable = () => (
    <div className={styles.container}>
        <FormattedMessage
            id="payment.free.editable"
            defaultMessage="Free checkout — there is no billing information to edit."
        />
    </div>
);

export default FreeEditable;
