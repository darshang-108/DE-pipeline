-- =============================================================================
-- 01_create_schema.sql
-- E-commerce SQL Data Engineering Pipeline
-- Creates the database, staging table, dimension tables, and partitioned
-- fact table with monthly range partitions for Jan–Mar 2026.
-- =============================================================================

-- Run this first as a superuser or a user with CREATEDB privilege.
-- If running inside psql, uncomment the next two lines:
-- DROP DATABASE IF EXISTS ecommerce_pipeline;
-- CREATE DATABASE ecommerce_pipeline;

-- Connect to the database before running the rest:
-- \c ecommerce_pipeline

-- -------------------------------------------------------
-- Clean slate: drop tables in dependency order
-- -------------------------------------------------------
DROP TABLE IF EXISTS fact_sales       CASCADE;
DROP TABLE IF EXISTS staging_sales    CASCADE;
DROP TABLE IF EXISTS dim_product      CASCADE;
DROP TABLE IF EXISTS dim_customer     CASCADE;

-- -------------------------------------------------------
-- DIMENSION: dim_product
-- -------------------------------------------------------
CREATE TABLE dim_product (
    product_id   SERIAL       PRIMARY KEY,
    product_name VARCHAR(100) NOT NULL UNIQUE,
    category     VARCHAR(50)  NOT NULL,
    price        NUMERIC(10,2) NOT NULL CHECK (price > 0),
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP    NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE dim_product IS 'Product dimension — one row per unique product.';

-- -------------------------------------------------------
-- DIMENSION: dim_customer
-- -------------------------------------------------------
CREATE TABLE dim_customer (
    customer_id  SERIAL       PRIMARY KEY,
    first_name   VARCHAR(50)  NOT NULL,
    last_name    VARCHAR(50)  NOT NULL,
    email        VARCHAR(100) NOT NULL UNIQUE,
    city         VARCHAR(50),
    state        VARCHAR(50),
    created_at   TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMP    NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE dim_customer IS 'Customer dimension — one row per unique customer (keyed on email).';

-- -------------------------------------------------------
-- FACT: fact_sales  (range-partitioned by sale_date)
-- -------------------------------------------------------
-- NOTE: In a partitioned table the PRIMARY KEY and UNIQUE constraints
--       must include the partition key (sale_date).
--       Global uniqueness on order_id alone cannot be enforced by the
--       database across partitions; the ETL layer handles deduplication.
CREATE TABLE fact_sales (
    sale_id      SERIAL,
    order_id     VARCHAR(20)   NOT NULL,
    product_id   INT           NOT NULL REFERENCES dim_product(product_id),
    customer_id  INT           NOT NULL REFERENCES dim_customer(customer_id),
    quantity     INT           NOT NULL CHECK (quantity > 0),
    unit_price   NUMERIC(10,2) NOT NULL CHECK (unit_price > 0),
    total_amount NUMERIC(12,2) NOT NULL,
    sale_date    DATE          NOT NULL,

    PRIMARY KEY (sale_id, sale_date),
    UNIQUE      (order_id, sale_date)
) PARTITION BY RANGE (sale_date);

COMMENT ON TABLE fact_sales IS 'Fact table — sales transactions, range-partitioned by month.';

-- -------------------------------------------------------
-- Monthly partitions: January, February, March 2026
-- -------------------------------------------------------
CREATE TABLE fact_sales_2026_01 PARTITION OF fact_sales
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE fact_sales_2026_02 PARTITION OF fact_sales
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE fact_sales_2026_03 PARTITION OF fact_sales
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

-- -------------------------------------------------------
-- STAGING: staging_sales  (mirrors the incoming CSV layout)
-- -------------------------------------------------------
CREATE TABLE staging_sales (
    staging_id          SERIAL       PRIMARY KEY,
    order_id            VARCHAR(20),
    product_name        VARCHAR(100),
    category            VARCHAR(50),
    unit_price          NUMERIC(10,2),
    customer_first_name VARCHAR(50),
    customer_last_name  VARCHAR(50),
    customer_email      VARCHAR(100),
    customer_city       VARCHAR(50),
    customer_state      VARCHAR(50),
    quantity            INT,
    sale_date           DATE,
    loaded_at           TIMESTAMP    NOT NULL DEFAULT NOW(),
    is_valid            BOOLEAN      DEFAULT NULL,
    validation_errors   TEXT
);

COMMENT ON TABLE staging_sales IS 'Landing area for raw CSV data. Rows are validated before promotion to fact/dim tables.';

-- -------------------------------------------------------
-- Verification
-- -------------------------------------------------------
SELECT tablename
FROM   pg_tables
WHERE  schemaname = 'public'
ORDER  BY tablename;
