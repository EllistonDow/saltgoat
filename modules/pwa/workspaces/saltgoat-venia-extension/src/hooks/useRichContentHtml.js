import { useMemo } from 'react';

const NEBULA_SIGNATURE = '<!-- sg-sync:';

const sanitizeHtml = (htmlString, sanitizer) => {
    if (!sanitizer || !htmlString) {
        return htmlString;
    }
    const shouldBypass = htmlString.includes(NEBULA_SIGNATURE);
    if (shouldBypass) {
        return htmlString;
    }

    return sanitizer(htmlString);
};

const useRichContentHtml = (htmlString, sanitizer) =>
    useMemo(() => sanitizeHtml(htmlString, sanitizer), [htmlString, sanitizer]);

export default useRichContentHtml;
