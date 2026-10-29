# E-commerce SQL Data Engineering Pipeline

A complete, working data engineering pipeline built with **PostgreSQL 15+** that demonstrates CSV bulk loading, star schema design, dimension-table MERGE, monthly range partitioning, indexing, query optimization, and additional SQL concepts.

---

## Project Structure

```
data_grokr_week_6/
├── README.md
├── data/
│   └── sales_data.csv              # 45 sales records (42 valid + 3 invalid)
└── sql/
    ├── 01_create_schema.sql        # Database, dimensions, partitioned fact, staging
    ├── 02_seed_data.sql            # Optional seed data for dimensions
    ├── 03_load_and_validate_csv.sql # Bulk COPY + row-level validation
    ├── 04_merge_dimensions.sql     # MERGE into dim_product & dim_customer
    ├── 05_load_fact_sales.sql      # Staging → partitioned fact_sales
    ├── 06_indexes_and_optimization.sql # Composite/partial indexes + EXPLAIN
    ├── 07_partitioning_demo.sql    # Range/LIST/HASH partitioning examples
    ├── 08_additional_sql_concepts.sql  # Transactions, SCD, triggers, JSONB, etc.
    └── 09_sales_reports.sql        # Analytical report queries
```

---

## Prerequisites

| Requirement       | Version       |
|--------------------|---------------|
| PostgreSQL         | 15 or later (MERGE requires v15+) |
| Tool               | pgAdmin 4 or `psql` CLI |
| Operating System   | Windows 10/11 |

---

## Setup & Execution Order

### Step 1 — Create the Database

Open `psql` or pgAdmin and create a fresh database:

```sql
CREATE DATABASE ecommerce_pipeline;
```

Connect to it:

```
\c ecommerce_pipeline
```

### Step 2 — Run Scripts in Order

Execute each file **sequentially** in the order shown below. Each script depends on the previous one.

| Order | File | What It Does |
|-------|------|--------------|
| 1 | `01_create_schema.sql` | Creates dimension tables, partitioned `fact_sales`, and `staging_sales` |
| 2 | `02_seed_data.sql` | Inserts 3 products and 2 customers to demo MERGE updates |
| 3 | `03_load_and_validate_csv.sql` | Bulk-loads CSV → staging, validates rows |
| 4 | `04_merge_dimensions.sql` | MERGE staging → `dim_product` and `dim_customer` |
| 5 | `05_load_fact_sales.sql` | Inserts valid staging rows into `fact_sales` (deduped) |
| 6 | `06_indexes_and_optimization.sql` | Creates indexes, runs EXPLAIN ANALYZE |
| 7 | `07_partitioning_demo.sql` | Partition pruning + LIST/HASH demos |
| 8 | `08_additional_sql_concepts.sql` | Transactions, SCD 1/2/3, trigger, stored proc, JSONB |
| 9 | `09_sales_reports.sql` | Revenue, monthly, top products, customer, category reports |

**Using psql:**

```bash
psql -U postgres -d ecommerce_pipeline -f sql/01_create_schema.sql
psql -U postgres -d ecommerce_pipeline -f sql/02_seed_data.sql
# ... repeat for each file
```

**Using pgAdmin:**
Open each `.sql` file in the Query Tool and execute (F5).

### Step 3 — Adjust the CSV Path

In `03_load_and_validate_csv.sql`, update the `COPY ... FROM` path to match your local system:

```sql
COPY staging_sales(...) FROM 'C:/Users/darsh/Documents/data_grokr_week_6/data/sales_data.csv' ...
```

> **Tip:** If you get a permission error with `COPY`, use `\copy` (client-side) in psql instead, or run psql as the postgres superuser.

---

## Schema Overview

```
                    ┌──────────────┐
                    │  dim_product │
                    │──────────────│
                    │ product_id PK│
                    │ product_name │
                    │ category     │
                    │ price        │
                    └──────┬───────┘
                           │ FK
┌──────────────┐    ┌──────┴────────────────────────┐
│ dim_customer │    │        fact_sales              │
│──────────────│    │  (PARTITION BY RANGE sale_date)│
│ customer_id PK◄───┤ sale_id, sale_date  PK        │
│ first_name   │    │ order_id                      │
│ last_name    │    │ product_id  FK ────────────────┘
│ email (UQ)   │    │ customer_id FK
│ city         │    │ quantity, unit_price
│ state        │    │ total_amount
└──────────────┘    └───────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        _2026_01     _2026_02     _2026_03
        (January)    (February)   (March)
```

---

## Dataset Summary

- **10 products** across 4 categories (Electronics, Accessories, Home Office, Audio)
- **15 customers** from various Indian cities
- **45 CSV rows**: 42 valid + 3 invalid (missing product name, negative quantity, out-of-range date)
- Date range: January – March 2026

---

## Key Concepts Demonstrated

| Concept | Where |
|---------|-------|
| Star schema design | `01_create_schema.sql` |
| Bulk CSV loading (`COPY`) | `03_load_and_validate_csv.sql` |
| Data validation | `03_load_and_validate_csv.sql` |
| `MERGE` (PG 15+) | `04_merge_dimensions.sql` |
| Deduplication (`ON CONFLICT`) | `05_load_fact_sales.sql` |
| Composite index | `06_indexes_and_optimization.sql` |
| Partial index | `06_indexes_and_optimization.sql` |
| `EXPLAIN ANALYZE` | `06_indexes_and_optimization.sql` |
| Range partitioning + pruning | `01_create_schema.sql`, `07_partitioning_demo.sql` |
| LIST partitioning | `07_partitioning_demo.sql` |
| HASH partitioning | `07_partitioning_demo.sql` |
| INSERT / UPDATE / DELETE | `08_additional_sql_concepts.sql` |
| MERGE / UPSERT | `08_additional_sql_concepts.sql` |
| Transactions (COMMIT / ROLLBACK) | `08_additional_sql_concepts.sql` |
| ACID & Isolation levels | `08_additional_sql_concepts.sql` |
| SCD Type 1 (overwrite) | `04_merge_dimensions.sql`, `08_additional_sql_concepts.sql` |
| SCD Type 2 (versioned rows) | `08_additional_sql_concepts.sql` |
| SCD Type 3 (previous column) | `08_additional_sql_concepts.sql` |
| Stored procedure | `08_additional_sql_concepts.sql` |
| Trigger + audit log | `08_additional_sql_concepts.sql` |
| JSONB queries + GIN index | `08_additional_sql_concepts.sql` |
| Sales reports | `09_sales_reports.sql` |

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `COPY` permission denied | Use `\copy` (backslash-copy) in psql, or run as postgres superuser |
| `MERGE` syntax error | Ensure PostgreSQL version is **15 or later** (`SELECT version();`) |
| Path not found | Use forward slashes in file paths, even on Windows |
| Partition error on insert | The `sale_date` must fall within an existing partition range |

---

## Notes

- All SQL is tested against PostgreSQL 15+ syntax.
- The `EXPLAIN ANALYZE` output will vary based on your machine. On a 42-row dataset, PostgreSQL may choose sequential scans over index scans — this is the optimizer making the correct choice for small tables.
- The stored procedure `process_staging()` wraps the full ETL (validate → merge → load) in a single `CALL`.
