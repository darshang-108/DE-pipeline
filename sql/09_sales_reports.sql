-- =============================================================================
-- 09_sales_reports.sql
-- Analytical queries on the loaded fact_sales data.
-- =============================================================================

-- -------------------------------------------------------
-- Report 1: Total Revenue and Total Number of Sales
-- -------------------------------------------------------
SELECT COUNT(*)           AS total_sales,
       SUM(total_amount)  AS total_revenue,
       ROUND(AVG(total_amount), 2) AS avg_order_value
FROM   fact_sales;


-- -------------------------------------------------------
-- Report 2: Monthly Sales Summary
-- -------------------------------------------------------
SELECT TO_CHAR(sale_date, 'YYYY-MM')   AS sale_month,
       COUNT(*)                        AS num_orders,
       SUM(quantity)                   AS units_sold,
       SUM(total_amount)               AS monthly_revenue,
       ROUND(AVG(total_amount), 2)     AS avg_order_value
FROM   fact_sales
GROUP  BY TO_CHAR(sale_date, 'YYYY-MM')
ORDER  BY sale_month;


-- -------------------------------------------------------
-- Report 3: Top 5 Products by Revenue
-- -------------------------------------------------------
SELECT p.product_name,
       p.category,
       COUNT(f.sale_id)        AS times_sold,
       SUM(f.quantity)         AS total_units,
       SUM(f.total_amount)     AS total_revenue
FROM   fact_sales   f
JOIN   dim_product  p ON p.product_id = f.product_id
GROUP  BY p.product_name, p.category
ORDER  BY total_revenue DESC
LIMIT  5;


-- -------------------------------------------------------
-- Report 4: Customer-wise Spending
-- -------------------------------------------------------
SELECT c.first_name || ' ' || c.last_name AS customer_name,
       c.email,
       c.city,
       COUNT(f.sale_id)        AS total_orders,
       SUM(f.total_amount)     AS total_spent,
       ROUND(AVG(f.total_amount), 2) AS avg_order_value
FROM   fact_sales    f
JOIN   dim_customer  c ON c.customer_id = f.customer_id
GROUP  BY c.customer_id, c.first_name, c.last_name, c.email, c.city
ORDER  BY total_spent DESC;


-- -------------------------------------------------------
-- Report 5: Sales Grouped by Product Category
-- -------------------------------------------------------
SELECT p.category,
       COUNT(f.sale_id)        AS num_orders,
       SUM(f.quantity)         AS total_units,
       SUM(f.total_amount)     AS category_revenue,
       ROUND(100.0 * SUM(f.total_amount) /
             (SELECT SUM(total_amount) FROM fact_sales), 1
       ) AS revenue_pct
FROM   fact_sales   f
JOIN   dim_product  p ON p.product_id = f.product_id
GROUP  BY p.category
ORDER  BY category_revenue DESC;


-- -------------------------------------------------------
-- Bonus Report: Month-over-Month Revenue Growth
-- -------------------------------------------------------
WITH monthly AS (
    SELECT TO_CHAR(sale_date, 'YYYY-MM') AS sale_month,
           SUM(total_amount)             AS revenue
    FROM   fact_sales
    GROUP  BY TO_CHAR(sale_date, 'YYYY-MM')
)
SELECT sale_month,
       revenue,
       LAG(revenue) OVER (ORDER BY sale_month)  AS prev_month_revenue,
       CASE
           WHEN LAG(revenue) OVER (ORDER BY sale_month) IS NOT NULL
           THEN ROUND(
               100.0 * (revenue - LAG(revenue) OVER (ORDER BY sale_month))
                     / LAG(revenue) OVER (ORDER BY sale_month), 1
           )
       END AS growth_pct
FROM   monthly
ORDER  BY sale_month;
