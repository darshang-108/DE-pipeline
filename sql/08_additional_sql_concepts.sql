-- =============================================================================
-- 08_additional_sql_concepts.sql
-- Demonstrates: INSERT/UPDATE/DELETE, MERGE/UPSERT, Transactions,
-- ACID & Isolation Levels, SCD Types 1/2/3, Stored Procedure,
-- Trigger, and JSONB queries.
-- =============================================================================


-- =============================================================
-- 1. INSERT / UPDATE / DELETE demonstrations
-- =============================================================

-- INSERT a new product
INSERT INTO dim_product (product_name, category, price)
VALUES ('Standing Desk Converter', 'Home Office', 249.99);

SELECT * FROM dim_product WHERE product_name = 'Standing Desk Converter';

-- UPDATE the price
UPDATE dim_product
SET    price = 229.99, updated_at = NOW()
WHERE  product_name = 'Standing Desk Converter';

SELECT product_name, price, updated_at FROM dim_product
WHERE  product_name = 'Standing Desk Converter';

-- DELETE the product
DELETE FROM dim_product
WHERE  product_name = 'Standing Desk Converter';

-- Verify deletion
SELECT COUNT(*) AS remaining FROM dim_product
WHERE  product_name = 'Standing Desk Converter';


-- =============================================================
-- 2. MERGE / UPSERT (INSERT ... ON CONFLICT)
-- =============================================================

-- PostgreSQL-style UPSERT: insert or update on conflict
INSERT INTO dim_product (product_name, category, price)
VALUES ('Wireless Mouse', 'Electronics', 31.99)
ON CONFLICT (product_name)
DO UPDATE SET price      = EXCLUDED.price,
              updated_at = NOW();

-- Check the updated price
SELECT product_name, price FROM dim_product
WHERE  product_name = 'Wireless Mouse';

-- Restore original price for consistency with the rest of the pipeline
UPDATE dim_product SET price = 29.99, updated_at = NOW()
WHERE  product_name = 'Wireless Mouse';


-- =============================================================
-- 3. Transactions — COMMIT and ROLLBACK
-- =============================================================

-- Example A: Successful transaction (COMMIT)
BEGIN;
    INSERT INTO dim_product (product_name, category, price)
    VALUES ('Bluetooth Speaker', 'Audio', 69.99);

    -- We can verify inside the transaction:
    SELECT product_name, price FROM dim_product
    WHERE  product_name = 'Bluetooth Speaker';
COMMIT;
-- The row is now permanently saved.

-- Example B: Rolled-back transaction (ROLLBACK)
BEGIN;
    INSERT INTO dim_product (product_name, category, price)
    VALUES ('Gaming Mouse', 'Electronics', 59.99);

    -- Oops, wrong price — abort the whole transaction
ROLLBACK;

-- Verify: Gaming Mouse was NOT inserted
SELECT COUNT(*) AS should_be_zero FROM dim_product
WHERE  product_name = 'Gaming Mouse';

-- Clean up the Bluetooth Speaker (it was just for demo)
DELETE FROM dim_product WHERE product_name = 'Bluetooth Speaker';


-- =============================================================
-- 4. ACID Properties & Transaction Isolation Levels
-- =============================================================

/*
ACID RECAP:
─────────────────────────────────────────────────────────
A — Atomicity:   All statements in a transaction succeed or none do.
                  The ROLLBACK example above demonstrates this.
C — Consistency: Constraints (CHECK, FK, UNIQUE) are enforced at
                  commit time, so the database never violates rules.
I — Isolation:   Concurrent transactions don't see each other's
                  uncommitted changes (at default READ COMMITTED).
D — Durability:  Once COMMIT returns, the data survives crashes
                  (WAL-backed guarantee).
*/

-- Show the current isolation level
SHOW default_transaction_isolation;

-- Demonstrate setting a stricter isolation level:
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    -- Inside this transaction, we see a stable snapshot.
    -- Other concurrent commits won't be visible until we commit/rollback.
    SELECT COUNT(*) AS product_count FROM dim_product;
COMMIT;

-- Serializable level (strictest):
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    SELECT COUNT(*) AS product_count FROM dim_product;
COMMIT;

/*
ISOLATION LEVEL SUMMARY:
─────────────────────────────────────────────────────────
Level              | Dirty Read | Non-Repeatable Read | Phantom Read
READ UNCOMMITTED*  | No**       | Yes                 | Yes
READ COMMITTED     | No         | Yes                 | Yes
REPEATABLE READ    | No         | No                  | No***
SERIALIZABLE       | No         | No                  | No

 *  PostgreSQL treats READ UNCOMMITTED the same as READ COMMITTED.
 ** PostgreSQL never allows dirty reads regardless of level.
*** PostgreSQL's REPEATABLE READ also prevents phantom reads (uses
    snapshot isolation, not traditional locking).
*/


-- =============================================================
-- 5. Slowly Changing Dimensions (SCD) Examples
-- =============================================================

-- ----- SCD Type 1: Overwrite (already demonstrated in MERGE) -----
-- The MERGE in 04_merge_dimensions.sql updates the price in-place.
-- No history is kept — the old value is lost.

-- ----- SCD Type 2: Add new row with versioning -----
DROP TABLE IF EXISTS dim_product_scd2;

CREATE TABLE dim_product_scd2 (
    surrogate_key  SERIAL PRIMARY KEY,
    product_name   VARCHAR(100) NOT NULL,
    category       VARCHAR(50)  NOT NULL,
    price          NUMERIC(10,2) NOT NULL,
    effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_to   DATE DEFAULT '9999-12-31',       -- open-ended for current row
    is_current     BOOLEAN NOT NULL DEFAULT TRUE
);

-- Insert original record
INSERT INTO dim_product_scd2 (product_name, category, price, effective_from)
VALUES ('Wireless Mouse', 'Electronics', 24.99, '2025-06-01');

-- Price changes to 29.99 on 2026-01-01.
-- Step 1: Close the old version
UPDATE dim_product_scd2
SET    effective_to = '2025-12-31',
       is_current   = FALSE
WHERE  product_name = 'Wireless Mouse' AND is_current = TRUE;

-- Step 2: Insert the new version
INSERT INTO dim_product_scd2 (product_name, category, price, effective_from)
VALUES ('Wireless Mouse', 'Electronics', 29.99, '2026-01-01');

-- View full history
SELECT * FROM dim_product_scd2 ORDER BY effective_from;


-- ----- SCD Type 3: Add column for previous value -----
DROP TABLE IF EXISTS dim_product_scd3;

CREATE TABLE dim_product_scd3 (
    product_id     SERIAL PRIMARY KEY,
    product_name   VARCHAR(100) NOT NULL UNIQUE,
    category       VARCHAR(50)  NOT NULL,
    current_price  NUMERIC(10,2) NOT NULL,
    previous_price NUMERIC(10,2),                   -- NULL until first change
    price_changed_on DATE
);

-- Insert original
INSERT INTO dim_product_scd3 (product_name, category, current_price)
VALUES ('Wireless Mouse', 'Electronics', 24.99);

-- Price changes: shift current → previous, set new current
UPDATE dim_product_scd3
SET    previous_price   = current_price,
       current_price    = 29.99,
       price_changed_on = '2026-01-01'
WHERE  product_name = 'Wireless Mouse';

SELECT * FROM dim_product_scd3;


-- =============================================================
-- 6. Stored Procedure — process_staging()
-- =============================================================
-- Wraps validation + dimension merge + fact load in a single call.

CREATE OR REPLACE PROCEDURE process_staging()
LANGUAGE plpgsql
AS $$
DECLARE
    v_valid_count   INT;
    v_invalid_count INT;
    v_loaded_count  INT;
BEGIN
    -- Validate staging rows (same logic as 03_load_and_validate_csv.sql)
    UPDATE staging_sales
    SET    is_valid          = FALSE,
           validation_errors = CONCAT_WS('; ',
               CASE WHEN product_name IS NULL OR TRIM(product_name) = ''
                    THEN 'Missing product_name' END,
               CASE WHEN quantity IS NULL OR quantity <= 0
                    THEN 'Invalid quantity' END,
               CASE WHEN sale_date IS NULL
                         OR sale_date < '2026-01-01'
                         OR sale_date >= '2026-04-01'
                    THEN 'sale_date out of range' END
           )
    WHERE  is_valid IS NULL
      AND  ((product_name IS NULL OR TRIM(product_name) = '')
         OR (quantity IS NULL OR quantity <= 0)
         OR (sale_date IS NULL OR sale_date < '2026-01-01' OR sale_date >= '2026-04-01'));

    UPDATE staging_sales SET is_valid = TRUE WHERE is_valid IS NULL;

    SELECT COUNT(*) INTO v_valid_count   FROM staging_sales WHERE is_valid = TRUE;
    SELECT COUNT(*) INTO v_invalid_count FROM staging_sales WHERE is_valid = FALSE;

    -- MERGE products
    MERGE INTO dim_product AS tgt
    USING (
        SELECT product_name, category, MAX(unit_price) AS unit_price
        FROM   staging_sales WHERE is_valid = TRUE
        GROUP  BY product_name, category
    ) AS src ON tgt.product_name = src.product_name
    WHEN MATCHED THEN
        UPDATE SET price = src.unit_price, updated_at = NOW()
    WHEN NOT MATCHED THEN
        INSERT (product_name, category, price) VALUES (src.product_name, src.category, src.unit_price);

    -- MERGE customers
    MERGE INTO dim_customer AS tgt
    USING (
        SELECT DISTINCT ON (customer_email)
               customer_first_name AS first_name,
               customer_last_name  AS last_name,
               customer_email      AS email,
               customer_city       AS city,
               customer_state      AS state
        FROM   staging_sales WHERE is_valid = TRUE
        ORDER  BY customer_email, staging_id DESC
    ) AS src ON tgt.email = src.email
    WHEN MATCHED THEN
        UPDATE SET first_name = src.first_name, last_name = src.last_name,
                   city = src.city, state = src.state, updated_at = NOW()
    WHEN NOT MATCHED THEN
        INSERT (first_name, last_name, email, city, state)
        VALUES (src.first_name, src.last_name, src.email, src.city, src.state);

    -- Load fact table
    INSERT INTO fact_sales (order_id, product_id, customer_id,
                            quantity, unit_price, total_amount, sale_date)
    SELECT s.order_id, p.product_id, c.customer_id,
           s.quantity, s.unit_price, s.quantity * s.unit_price, s.sale_date
    FROM   staging_sales s
    JOIN   dim_product   p ON p.product_name = s.product_name
    JOIN   dim_customer  c ON c.email        = s.customer_email
    WHERE  s.is_valid = TRUE
    ON CONFLICT (order_id, sale_date) DO NOTHING;

    GET DIAGNOSTICS v_loaded_count = ROW_COUNT;

    RAISE NOTICE 'Processing complete — valid: %, invalid: %, loaded to fact: %',
                 v_valid_count, v_invalid_count, v_loaded_count;
END;
$$;

-- To call: CALL process_staging();
-- (Not calling here to avoid re-processing already loaded data.)


-- =============================================================
-- 7. Trigger — Audit trail for dim_product changes
-- =============================================================

DROP TABLE IF EXISTS product_audit_log CASCADE;

CREATE TABLE product_audit_log (
    log_id       SERIAL PRIMARY KEY,
    product_id   INT NOT NULL,
    product_name VARCHAR(100),
    old_price    NUMERIC(10,2),
    new_price    NUMERIC(10,2),
    changed_by   TEXT DEFAULT current_user,
    changed_at   TIMESTAMP DEFAULT NOW(),
    operation    VARCHAR(10)
);

-- Trigger function
CREATE OR REPLACE FUNCTION fn_product_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO product_audit_log (product_id, product_name, old_price, new_price, operation)
        VALUES (OLD.product_id, OLD.product_name, OLD.price, NEW.price, 'UPDATE');
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO product_audit_log (product_id, product_name, old_price, new_price, operation)
        VALUES (OLD.product_id, OLD.product_name, OLD.price, NULL, 'DELETE');
        RETURN OLD;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO product_audit_log (product_id, product_name, old_price, new_price, operation)
        VALUES (NEW.product_id, NEW.product_name, NULL, NEW.price, 'INSERT');
        RETURN NEW;
    END IF;
END;
$$;

-- Attach trigger to dim_product
DROP TRIGGER IF EXISTS trg_product_audit ON dim_product;

CREATE TRIGGER trg_product_audit
AFTER INSERT OR UPDATE OR DELETE ON dim_product
FOR EACH ROW EXECUTE FUNCTION fn_product_audit();

-- Test the trigger
INSERT INTO dim_product (product_name, category, price)
VALUES ('Test Trigger Product', 'Test', 9.99);

UPDATE dim_product SET price = 12.99
WHERE  product_name = 'Test Trigger Product';

DELETE FROM dim_product
WHERE  product_name = 'Test Trigger Product';

-- View audit log — should have 3 entries (INSERT, UPDATE, DELETE)
SELECT * FROM product_audit_log ORDER BY log_id;


-- =============================================================
-- 8. JSONB Queries
-- =============================================================

-- Add a JSONB metadata column to demonstrate JSONB capabilities.
-- Using a separate demo table to avoid altering the main schema.

DROP TABLE IF EXISTS product_metadata_demo;

CREATE TABLE product_metadata_demo (
    product_id   INT PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL,
    metadata     JSONB
);

INSERT INTO product_metadata_demo VALUES
(1, 'Wireless Mouse', '{
    "brand": "TechCo",
    "color": "Black",
    "weight_grams": 85,
    "wireless": true,
    "connectivity": ["Bluetooth", "USB-A Dongle"],
    "specs": {"dpi": 1600, "battery_life_hours": 120}
}'),
(2, 'Mechanical Keyboard', '{
    "brand": "KeyMaster",
    "color": "Silver",
    "weight_grams": 950,
    "wireless": false,
    "connectivity": ["USB-C"],
    "specs": {"switch_type": "Cherry MX Blue", "key_count": 104}
}'),
(3, 'Noise Cancelling Headphones', '{
    "brand": "SoundWave",
    "color": "Navy",
    "weight_grams": 250,
    "wireless": true,
    "connectivity": ["Bluetooth 5.2", "AUX 3.5mm"],
    "specs": {"driver_size_mm": 40, "battery_life_hours": 30, "anc": true}
}');

-- Query 1: Extract a top-level key
SELECT product_name,
       metadata->>'brand'  AS brand,
       metadata->>'color'  AS color
FROM   product_metadata_demo;

-- Query 2: Extract a nested key
SELECT product_name,
       metadata->'specs'->>'dpi' AS dpi
FROM   product_metadata_demo
WHERE  metadata->'specs' ? 'dpi';

-- Query 3: Filter by a boolean JSONB value
SELECT product_name
FROM   product_metadata_demo
WHERE  (metadata->>'wireless')::boolean = TRUE;

-- Query 4: Expand a JSONB array
SELECT product_name,
       jsonb_array_elements_text(metadata->'connectivity') AS connection_type
FROM   product_metadata_demo;

-- Query 5: Use @> containment operator
SELECT product_name
FROM   product_metadata_demo
WHERE  metadata @> '{"brand": "TechCo"}';

-- Create a GIN index for efficient JSONB lookups
CREATE INDEX IF NOT EXISTS idx_product_metadata_gin
    ON product_metadata_demo USING GIN (metadata);
