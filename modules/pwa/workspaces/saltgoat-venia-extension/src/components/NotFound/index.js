import React from 'react';
import { Link } from 'react-router-dom';
import '../../styles/theme.global.module.css';

const NotFound = () => (
    <div
        style={{
            minHeight: '60vh',
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
            gap: '16px',
            textAlign: 'center',
            padding: '40px 16px'
        }}
    >
        <h1 style={{ fontSize: '2rem', margin: 0 }}>Page Not Found</h1>
        <p style={{ maxWidth: '420px', color: 'var(--sg-subtext)' }}>
            The link you followed is invalid or the content has moved. Please return to the homepage.
        </p>
        <Link
            to="/"
            style={{
                padding: '12px 28px',
                borderRadius: '999px',
                background: 'var(--sg-primary)',
                color: 'var(--sg-primary-text)',
                textDecoration: 'none'
            }}
        >
            Back to Homepage
        </Link>
    </div>
);

export default NotFound;
