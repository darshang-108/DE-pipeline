-- =============================================================================
-- 06_indexes_and_optimization.sql
-- Composite index, partial index, and EXPLAIN ANALYZE demonstrations.
-- =============================================================================

-- -------------------------------------------------------
-- 1. Composite Index on (product_id, sale_date)
-- -------------------------------------------------------
-- Speeds up queries that filter or join on product_id and optionally
-- narrow by sale_date.  PostgreSQL can also use this index for queries
-- that filter on product_id alone (leftmost prefix).

CREATE INDEX IF NOT EXISTS idx_fact_sales_product_date
    ON fact_sales (product_id, sale_date);

-- -------------------------------------------------------
-- 2. Partial Index — high-value orders only
-- -------------------------------------------------------
-- Covers only rows where total_amount > 100.  This is a smaller index
-- that accelerates queries specifically targeting high-value orders.

CREATE INDEX IF NOT EXISTS idx_fact_sales_high_value
    ON fact_sales (total_amount)
    WHERE total_amount > 100;

-- -------------------------------------------------------
-- 3. Additional useful index on customer_id
-- -------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_fact_sales_customer
    ON fact_sales (customer_id);

-- -------------------------------------------------------
-- 4. EXPLAIN ANALYZE — observe the query plan
-- -------------------------------------------------------

-- Query A: Monthly revenue for a specific product (uses composite index + partition pruning)
EXPLAIN ANALYZE
SELECT p.product_name,
       SUM(f.total_amount) AS revenue
FROM   fact_sales f
JOIN   dim_product p ON p.product_id = f.product_id
WHERE  f.sale_date >= '2026-02-01'
  AND  f.sale_date <  '2026-03-01'
GROUP  BY p.product_name
ORDER  BY revenue DESC;

/*
EXPECTED PLAN HIGHLIGHTS (actual numbers depend on your data):
──────────────────────────────────────────────────────────────
• The planner should show "Append" with only fact_sales_2026_02 scanned
  (partition pruning eliminates Jan and Mar partitions).
• An Index Scan or Bitmap Index Scan on idx_fact_sales_product_date may
  appear if the planner decides it's cheaper than a sequential scan.
• With only ~14 rows in the February partition, PostgreSQL may still
  choose a Seq Scan because the table is small.  This is normal and
  expected — the optimiser correctly judges that reading a handful of
  pages sequentially is faster than index lookups.
•
  ** Do NOT claim the index "improves performance" unless the EXPLAIN
     output actually shows it being used.  On a 42-row dataset the
     indexes exist for correctness of demonstration, not for measurable
     speed gains. **
*/

-- Query B: High-value orders (uses partial index)
EXPLAIN ANALYZE
SELECT f.order_id, f.total_amount, f.sale_date
FROM   fact_sales f
WHERE  f.total_amount > 100
ORDER  BY f.total_amount DESC;

/*
EXPECTED PLAN HIGHLIGHTS:
──────────────────────────────────────────────────────────────
• If the partial index is used you will see:
  "Index Scan using idx_fact_sales_high_value on fact_sales_2026_XX"
• Again, on small data the planner may prefer a Seq Scan.
  That's a correct optimiser decision, not a problem.
*/

-- Query C: Show that partition pruning works
EXPLAIN ANALYZE
SELECT *
FROM   fact_sales
WHERE  sale_date = '2026-01-15';

/*
PARTITION PRUNING EXPLANATION:
──────────────────────────────────────────────────────────────
The WHERE clause restricts sale_date to a single value in January.
PostgreSQL's partition pruning recognises that only the
fact_sales_2026_01 partition can contain matching rows and skips
the other two partitions entirely.

Look for:
  →  Seq Scan on fact_sales_2026_01   (only this partition appears)
  →  The Feb and Mar partitions are NOT in the plan at all.

This avoids scanning ~2/3 of the data even without any index.
*/
