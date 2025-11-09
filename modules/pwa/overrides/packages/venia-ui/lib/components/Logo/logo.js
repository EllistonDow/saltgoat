import React from 'react';
import PropTypes from 'prop-types';
import { useStyle } from '../../classify';
import Image from '../Image';
import logo from './tattoo-logo.svg';

const Logo = props => {
    const { height, width } = props;
    const classes = useStyle({}, props.classes);

    return (
        <Image
            classes={{ image: classes.logo }}
            height={height}
            src={logo}
            alt="Tattoo"
            title="Tattoo"
            width={width}
        />
    );
};

Logo.propTypes = {
    classes: PropTypes.shape({
        logo: PropTypes.string
    }),
    height: PropTypes.number,
    width: PropTypes.number
};

Logo.defaultProps = {
    height: 24,
    width: 120
};

export default Logo;
