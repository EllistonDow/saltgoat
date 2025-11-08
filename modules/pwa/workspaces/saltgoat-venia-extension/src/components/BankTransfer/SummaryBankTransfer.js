import React from 'react';
import { shape, string } from 'prop-types';
import { useIntl } from 'react-intl';

const SummaryBankTransfer = ({ selectedPaymentMethod }) => {
    const { formatMessage } = useIntl();
    const title =
        selectedPaymentMethod?.title ||
        formatMessage({
            id: 'bankTransfer.summaryTitle',
            defaultMessage: 'Bank Transfer'
        });

    return (
        <div>
            <strong>{title}</strong>
            <p>
                {formatMessage({
                    id: 'bankTransfer.summaryDescription',
                    defaultMessage:
                        'We will send transfer instructions with your order confirmation email.'
                })}
            </p>
        </div>
    );
};

SummaryBankTransfer.propTypes = {
    selectedPaymentMethod: shape({
        title: string
    })
};

export default SummaryBankTransfer;
