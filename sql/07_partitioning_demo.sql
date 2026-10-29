-- =============================================================================
-- 07_partitioning_demo.sql
-- Demonstrates partition pruning on fact_sales, plus brief examples
-- of LIST and HASH partitioning using small, self-contained tables.
-- =============================================================================

-- =============================================
-- PART A: Range Partitioning (already in use)
-- =============================================

-- Recap: fact_sales is range-partitioned on sale_date with 3 monthly partitions.
-- Let's verify how records are distributed.

SELECT tableoid::regclass AS partition_name,
       MIN(sale_date)     AS min_date,
       MAX(sale_date)     AS max_date,
       COUNT(*)           AS row_count
FROM   fact_sales
GROUP  BY tableoid
ORDER  BY min_date;

-- Partition pruning in action — only January's partition is scanned:
EXPLAIN (COSTS OFF)
SELECT * FROM fact_sales
WHERE  sale_date BETWEEN '2026-01-01' AND '2026-01-31';

-- Cross-partition query — all three partitions scanned:
EXPLAIN (COSTS OFF)
SELECT * FROM fact_sales
WHERE  sale_date BETWEEN '2026-01-01' AND '2026-03-31';


-- =============================================
-- PART B: LIST Partitioning Example
-- =============================================
-- A small demo table partitioned by product category.

DROP TABLE IF EXISTS demo_list_part CASCADE;

CREATE TABLE demo_list_part (
    id       SERIAL,
    name     VARCHAR(50) NOT NULL,
    category VARCHAR(30) NOT NULL,
    amount   NUMERIC(10,2),
    PRIMARY KEY (id, category)
) PARTITION BY LIST (category);

-- One partition per category
CREATE TABLE demo_list_electronics PARTITION OF demo_list_part
    FOR VALUES IN ('Electronics');

CREATE TABLE demo_list_accessories PARTITION OF demo_list_part
    FOR VALUES IN ('Accessories');

CREATE TABLE demo_list_home_office PARTITION OF demo_list_part
    FOR VALUES IN ('Home Office');

CREATE TABLE demo_list_audio PARTITION OF demo_list_part
    FOR VALUES IN ('Audio');

-- Insert sample rows
INSERT INTO demo_list_part (name, category, amount) VALUES
    ('Wireless Mouse',              'Electronics',  29.99),
    ('USB-C Hub',                   'Electronics',  49.99),
    ('Cable Management Kit',        'Accessories',  19.99),
    ('Monitor Arm',                 'Accessories',  79.99),
    ('LED Desk Lamp',               'Home Office',  34.99),
    ('Noise Cancelling Headphones', 'Audio',       149.99);

-- Show that list partition pruning routes rows correctly:
SELECT tableoid::regclass AS partition, name, category, amount
FROM   demo_list_part
ORDER  BY category, name;

-- Only the Electronics partition is scanned:
EXPLAIN (COSTS OFF)
SELECT * FROM demo_list_part WHERE category = 'Electronics';


-- =============================================
-- PART C: HASH Partitioning Example
-- =============================================
-- Distribute orders evenly across 4 buckets by order_id hash.

DROP TABLE IF EXISTS demo_hash_part CASCADE;

CREATE TABLE demo_hash_part (
    order_id   VARCHAR(20) NOT NULL,
    amount     NUMERIC(10,2),
    order_date DATE,
    PRIMARY KEY (order_id)
) PARTITION BY HASH (order_id);

CREATE TABLE demo_hash_part_0 PARTITION OF demo_hash_part
    FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE demo_hash_part_1 PARTITION OF demo_hash_part
    FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE demo_hash_part_2 PARTITION OF demo_hash_part
    FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE demo_hash_part_3 PARTITION OF demo_hash_part
    FOR VALUES WITH (MODULUS 4, REMAINDER 3);

-- Insert sample data
INSERT INTO demo_hash_part (order_id, amount, order_date) VALUES
    ('H-001', 100.00, '2026-01-01'),
    ('H-002', 200.00, '2026-01-02'),
    ('H-003', 150.00, '2026-01-03'),
    ('H-004', 300.00, '2026-01-04'),
    ('H-005', 250.00, '2026-01-05'),
    ('H-006', 175.00, '2026-01-06'),
    ('H-007',  50.00, '2026-01-07'),
    ('H-008', 125.00, '2026-01-08');

-- Distribution across hash buckets:
SELECT tableoid::regclass AS partition,
       COUNT(*)           AS row_count
FROM   demo_hash_part
GROUP  BY tableoid
ORDER  BY partition;

-- Hash pruning: looking up a specific order_id hashes to one bucket
EXPLAIN (COSTS OFF)
SELECT * FROM demo_hash_part WHERE order_id = 'H-003';

/*
HASH PARTITIONING NOTES:
──────────────────────────────────────────────────────────────
• Hash partitioning distributes rows roughly evenly; you cannot
  predict which bucket a specific value lands in.
• It is useful for spreading write load across partitions.
• Partition pruning works on equality predicates for the hash key.
• Range queries on the hash key will scan ALL buckets (no pruning).
*/
