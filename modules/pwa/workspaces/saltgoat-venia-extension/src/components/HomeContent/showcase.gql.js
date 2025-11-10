import { gql } from '@apollo/client';

export const SHOWCASE_QUERY = gql`
    query SaltgoatShowcaseData($categoryIds: [String!]) {
        storeConfig {
            store_name
            category_url_suffix
        }
        categoryList(filters: { ids: { in: $categoryIds } }) {
            items {
                id
                name
                url_path
                image
                image_path
                meta_title
            }
        }
    }
`;

export default SHOWCASE_QUERY;
