-- =============================================================================
-- 03_load_and_validate_csv.sql
-- Bulk-load the CSV into staging_sales, then validate every row.
-- =============================================================================

-- -------------------------------------------------------
-- Step 1: Truncate staging (idempotent re-runs)
-- -------------------------------------------------------
TRUNCATE TABLE staging_sales RESTART IDENTITY;

-- -------------------------------------------------------
-- Step 2: Bulk-load using COPY
-- -------------------------------------------------------
-- IMPORTANT: Update the file path below to match your local system.
--
-- Option A — running inside psql (backslash-copy, client-side):
-- \copy staging_sales(order_id, product_name, category, unit_price, customer_first_name, customer_last_name, customer_email, customer_city, customer_state, quantity, sale_date) FROM 'C:/Users/darsh/Documents/data_grokr_week_6/data/sales_data.csv' WITH (FORMAT csv, HEADER true);
--
-- Option B — running as superuser (server-side COPY):
COPY staging_sales(
    order_id, product_name, category, unit_price,
    customer_first_name, customer_last_name, customer_email,
    customer_city, customer_state, quantity, sale_date
)
FROM 'C:/Users/darsh/Documents/data_grokr_week_6/data/sales_data.csv'
WITH (FORMAT csv, HEADER true);

-- Quick row count check
SELECT COUNT(*) AS rows_loaded FROM staging_sales;

-- -------------------------------------------------------
-- Step 3: Data Validation
-- -------------------------------------------------------
-- Rule 1: product_name must not be NULL or empty
-- Rule 2: quantity must be > 0
-- Rule 3: unit_price must be > 0
-- Rule 4: sale_date must fall within our partition range (Jan–Mar 2026)
-- Rule 5: order_id must not be NULL or empty
-- Rule 6: customer_email must not be NULL or empty

-- Mark invalid rows
UPDATE staging_sales
SET    is_valid          = FALSE,
       validation_errors = CONCAT_WS('; ',
           CASE WHEN product_name IS NULL OR TRIM(product_name) = ''
                THEN 'Missing product_name' END,
           CASE WHEN quantity IS NULL OR quantity <= 0
                THEN 'Invalid quantity (must be > 0)' END,
           CASE WHEN unit_price IS NULL OR unit_price <= 0
                THEN 'Invalid unit_price (must be > 0)' END,
           CASE WHEN sale_date IS NULL
                     OR sale_date < '2026-01-01'
                     OR sale_date >= '2026-04-01'
                THEN 'sale_date out of partition range (Jan–Mar 2026)' END,
           CASE WHEN order_id IS NULL OR TRIM(order_id) = ''
                THEN 'Missing order_id' END,
           CASE WHEN customer_email IS NULL OR TRIM(customer_email) = ''
                THEN 'Missing customer_email' END
       )
WHERE  (product_name IS NULL OR TRIM(product_name) = '')
   OR  (quantity IS NULL OR quantity <= 0)
   OR  (unit_price IS NULL OR unit_price <= 0)
   OR  (sale_date IS NULL OR sale_date < '2026-01-01' OR sale_date >= '2026-04-01')
   OR  (order_id IS NULL OR TRIM(order_id) = '')
   OR  (customer_email IS NULL OR TRIM(customer_email) = '');

-- Mark remaining rows as valid
UPDATE staging_sales
SET    is_valid = TRUE
WHERE  is_valid IS NULL;

-- -------------------------------------------------------
-- Step 4: Validation Summary
-- -------------------------------------------------------
SELECT is_valid,
       COUNT(*) AS row_count
FROM   staging_sales
GROUP  BY is_valid
ORDER  BY is_valid;

-- Show rejected rows for inspection
SELECT staging_id, order_id, product_name, quantity, sale_date, validation_errors
FROM   staging_sales
WHERE  is_valid = FALSE;
