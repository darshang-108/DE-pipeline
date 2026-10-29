-- =============================================================================
-- 02_seed_data.sql
-- Optional: Pre-load a small set of dimension data.
-- This lets us demonstrate that MERGE will UPDATE existing products and
-- INSERT only new ones when the CSV is processed.
-- =============================================================================

-- -------------------------------------------------------
-- Seed dim_product with 3 products (subset of what the CSV contains).
-- The price for "Wireless Mouse" is intentionally stale (24.99 vs 29.99
-- in the CSV) so the MERGE step shows an UPDATE in action.
-- -------------------------------------------------------
INSERT INTO dim_product (product_name, category, price)
VALUES
    ('Wireless Mouse',      'Electronics',  24.99),   -- stale price
    ('USB-C Hub',           'Electronics',  49.99),
    ('Mechanical Keyboard', 'Electronics',  89.99)
ON CONFLICT (product_name) DO NOTHING;

-- -------------------------------------------------------
-- Seed dim_customer with 2 customers
-- -------------------------------------------------------
INSERT INTO dim_customer (first_name, last_name, email, city, state)
VALUES
    ('Aarav',  'Sharma', 'aarav.sharma@email.com', 'Mumbai',    'Maharashtra'),
    ('Priya',  'Patel',  'priya.patel@email.com',  'Bangalore', 'Karnataka')
ON CONFLICT (email) DO NOTHING;

-- -------------------------------------------------------
-- Verify seeds
-- -------------------------------------------------------
SELECT 'dim_product rows' AS label, COUNT(*) AS cnt FROM dim_product
UNION ALL
SELECT 'dim_customer rows', COUNT(*) FROM dim_customer;
