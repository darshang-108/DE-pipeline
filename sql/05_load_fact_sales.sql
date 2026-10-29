-- =============================================================================
-- 05_load_fact_sales.sql
-- Load validated staging rows into the partitioned fact_sales table.
-- Deduplication ensures no order_id is inserted twice.
-- =============================================================================

-- -------------------------------------------------------
-- Insert valid staging rows into fact_sales
-- -------------------------------------------------------
-- Join staging → dim_product and dim_customer to resolve surrogate keys.
-- The ON CONFLICT clause prevents duplicates on re-runs.

INSERT INTO fact_sales (order_id, product_id, customer_id,
                        quantity, unit_price, total_amount, sale_date)
SELECT s.order_id,
       p.product_id,
       c.customer_id,
       s.quantity,
       s.unit_price,
       s.quantity * s.unit_price  AS total_amount,
       s.sale_date
FROM   staging_sales s
JOIN   dim_product   p ON p.product_name = s.product_name
JOIN   dim_customer  c ON c.email        = s.customer_email
WHERE  s.is_valid = TRUE
ON CONFLICT (order_id, sale_date) DO NOTHING;    -- skip duplicates

-- -------------------------------------------------------
-- Verify row distribution across partitions
-- -------------------------------------------------------
SELECT 'fact_sales_2026_01' AS partition_name, COUNT(*) AS rows
FROM   fact_sales_2026_01
UNION ALL
SELECT 'fact_sales_2026_02', COUNT(*) FROM fact_sales_2026_02
UNION ALL
SELECT 'fact_sales_2026_03', COUNT(*) FROM fact_sales_2026_03;

-- Show a few sample rows
SELECT sale_id, order_id, product_id, customer_id,
       quantity, unit_price, total_amount, sale_date
FROM   fact_sales
ORDER  BY sale_date, sale_id
LIMIT  10;

-- -------------------------------------------------------
-- Total loaded vs. total valid staging
-- -------------------------------------------------------
SELECT 'staging (valid)'  AS source, COUNT(*) AS cnt
FROM   staging_sales WHERE is_valid = TRUE
UNION ALL
SELECT 'fact_sales',      COUNT(*) FROM fact_sales;
