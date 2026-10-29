-- =============================================================================
-- 04_merge_dimensions.sql
-- Use MERGE (PostgreSQL 15+) to upsert products and customers from staging
-- into the dimension tables.
-- =============================================================================

-- -------------------------------------------------------
-- MERGE into dim_product
-- -------------------------------------------------------
-- Logic:
--   • MATCHED   → update category and price (SCD Type 1 overwrite)
--   • NOT MATCHED → insert new product
--
-- We use DISTINCT on product_name from valid staging rows.
-- When the same product appears with different prices across orders,
-- the subquery picks the latest (MAX) price.

MERGE INTO dim_product AS tgt
USING (
    SELECT product_name,
           category,
           MAX(unit_price) AS unit_price      -- latest price if multiple
    FROM   staging_sales
    WHERE  is_valid = TRUE
    GROUP  BY product_name, category
) AS src
ON tgt.product_name = src.product_name
WHEN MATCHED THEN
    UPDATE SET category   = src.category,
               price      = src.unit_price,
               updated_at = NOW()
WHEN NOT MATCHED THEN
    INSERT (product_name, category, price, created_at, updated_at)
    VALUES (src.product_name, src.category, src.unit_price, NOW(), NOW());

-- Show result: notice "Wireless Mouse" price updated from 24.99 → 29.99
SELECT product_id, product_name, category, price, created_at, updated_at
FROM   dim_product
ORDER  BY product_id;

-- -------------------------------------------------------
-- MERGE into dim_customer
-- -------------------------------------------------------
MERGE INTO dim_customer AS tgt
USING (
    SELECT DISTINCT ON (customer_email)
           customer_first_name AS first_name,
           customer_last_name  AS last_name,
           customer_email      AS email,
           customer_city       AS city,
           customer_state      AS state
    FROM   staging_sales
    WHERE  is_valid = TRUE
    ORDER  BY customer_email, staging_id DESC     -- keep latest info per email
) AS src
ON tgt.email = src.email
WHEN MATCHED THEN
    UPDATE SET first_name = src.first_name,
               last_name  = src.last_name,
               city       = src.city,
               state      = src.state,
               updated_at = NOW()
WHEN NOT MATCHED THEN
    INSERT (first_name, last_name, email, city, state, created_at, updated_at)
    VALUES (src.first_name, src.last_name, src.email, src.city, src.state, NOW(), NOW());

-- Verify
SELECT customer_id, first_name, last_name, email, city, state
FROM   dim_customer
ORDER  BY customer_id;

-- -------------------------------------------------------
-- Summary counts
-- -------------------------------------------------------
SELECT 'dim_product'  AS table_name, COUNT(*) AS rows FROM dim_product
UNION ALL
SELECT 'dim_customer', COUNT(*) FROM dim_customer;
