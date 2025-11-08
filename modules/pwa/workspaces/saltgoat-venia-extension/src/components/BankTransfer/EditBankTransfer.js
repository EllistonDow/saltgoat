import React from 'react';
import { useIntl } from 'react-intl';

const EditBankTransfer = () => {
    const { formatMessage } = useIntl();

    return (
        <p>
            {formatMessage({
                id: 'bankTransfer.editDescription',
                defaultMessage: 'Bank transfer instructions will be emailed after checkout.'
            })}
        </p>
    );
};

export default EditBankTransfer;
