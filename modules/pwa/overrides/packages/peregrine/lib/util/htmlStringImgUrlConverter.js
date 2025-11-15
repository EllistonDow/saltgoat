import makeUrl from '@magento/peregrine/lib/util/makeUrl';
import resolveLinkProps from '@magento/peregrine/lib/util/resolveLinkProps';
import DOMPurify from 'dompurify';

const SG_TEMPLATE_SIGNATURE = '<!-- sg-sync:';

const htmlStringImgUrlConverter = htmlString => {
    const temporaryElement = document.createElement('div');
    const shouldBypassSanitize =
        typeof htmlString === 'string' && htmlString.includes(SG_TEMPLATE_SIGNATURE);

    const sanitizedHtml = shouldBypassSanitize
        ? htmlString
        : DOMPurify.sanitize(htmlString);

    temporaryElement.innerHTML = sanitizedHtml;

    for (const imgElement of temporaryElement.getElementsByTagName('img')) {
        imgElement.src = makeUrl(imgElement.src, {
            type: 'image-wysiwyg',
            quality: 85
        });
    }

    for (const linkElement of temporaryElement.getElementsByTagName('a')) {
        const linkProps = resolveLinkProps(linkElement.href);
        linkElement.href = linkProps.to || linkProps.href;
    }

    return temporaryElement.innerHTML;
};

export default htmlStringImgUrlConverter;
