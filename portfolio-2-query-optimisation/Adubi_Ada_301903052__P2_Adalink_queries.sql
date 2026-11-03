-- =====================================================================
-- AdaLink E-commerce Marketplace
-- MIT 8103 Advanced Database Systems - Portfolio 2: Query Optimisation
-- File: AdaLink_P2_sample_queries.sql
-- Purpose: Five business queries, each tested before and after an
--          optimisation, as reported in the Brief Performance Analysis.
--
-- Needs: 01_postgresql_schema.sql, then
--        03_postgresql_sample_data_simple.sql (300,000 orders).
--
-- HOW TO USE (pgAdmin 4 Query Tool)
--   Run ONE step at a time: highlight it, press F5.
--   For every EXPLAIN step, press F5 twice and screenshot the second run:
--     * TOP of the plan    - row 1 to the first "Buffers:" line (pages read)
--     * BOTTOM of the plan - the "Execution Time" line
--   Remove "EXPLAIN (ANALYZE, BUFFERS)" from a step to see its rows.
--   Each query ends with a RESET step, so the next test starts clean.
--   The last section applies the recommended indexes and view.
--
-- RESULTS (my PC, PostgreSQL 18; see the Brief Performance Analysis)
--   Q  What it tests                     Before       After
--   1  Index on a foreign key            81.7 ms      0.25 ms
--   2  Partial index                     345.5 ms     8.3 ms
--   3  Expression index                  29.6 ms      0.11 ms
--   4  Indexes vs materialised view      375.4 ms     415.2 ms (indexes)
--                                                     27.5 ms (view)
--   5  Rewriting a correlated subquery   29,708 ms    272.7 ms (rewrite)
--                                                     32.5 ms (index)
--
-- Note: PostgreSQL indexes primary keys and UNIQUE columns
-- automatically, but NOT foreign keys, so orders.customer_id and
-- order_item.payout_id start with no index.
-- =====================================================================


-- =====================================================================
-- START: clear anything left from earlier tests (safe if none exist)
-- =====================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_product_sales_monthly;
DROP INDEX IF EXISTS idx_id_orders, ix_orders_customer_date, ix_orders_open,
                     ix_orders_status_full, ix_customer_email_lower,
                     ix_orders_order_date, ix_order_item_product,
                     ix_product_category, ix_order_item_payout;
ANALYZE;   -- make sure the planner's statistics are up to date


-- =====================================================================
-- Q1. A CUSTOMER'S 10 LATEST ORDERS ("My Orders" page)
-- Technique: index on the foreign key orders.customer_id.
--   Before: Parallel Seq Scan reads all 300,000 orders to find 26.
--   After:  Index Scan finds the customer's orders directly.
-- =====================================================================

-- Q1 step 1. BEFORE
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE customer_id = 9
ORDER BY order_date DESC
LIMIT 10;

-- Q1 step 2. FIX
CREATE INDEX idx_id_orders ON orders (customer_id);

-- Q1 step 3. AFTER (same query as step 1)
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE customer_id = 9
ORDER BY order_date DESC
LIMIT 10;

-- Q1 step 4. OPTIONAL refinement: a composite index also returns the
-- rows already in date order, so the remaining Sort step disappears.
-- CREATE INDEX ix_orders_customer_date ON orders (customer_id, order_date DESC);

-- Q1 step 5. RESET
DROP INDEX idx_id_orders;


-- =====================================================================
-- Q2. ORDERS STILL IN PROGRESS (operations dashboard)
-- Technique: PARTIAL index - indexes only the unfinished orders
-- (pending, paid, shipped), a small share of all orders.
--   Before: Parallel Seq Scan on orders.
--   After:  Bitmap Index Scan on the partial index.
-- =====================================================================

-- Q2 step 1. BEFORE
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, order_date, order_status, customer_id, total_amount
FROM orders
WHERE order_status IN ('pending','paid','shipped')
ORDER BY order_date;

-- Q2 step 2. FIX
CREATE INDEX ix_orders_open ON orders (order_date)
    WHERE order_status IN ('pending','paid','shipped');

-- Q2 step 3. AFTER
EXPLAIN (ANALYZE, BUFFERS)
SELECT order_id, order_date, order_status, customer_id, total_amount
FROM orders
WHERE order_status IN ('pending','paid','shipped')
ORDER BY order_date;

-- Q2 step 4. SIZE: partial index vs a full index on the same columns
CREATE INDEX ix_orders_status_full ON orders (order_status, order_date);
SELECT 'partial ix_orders_open'      AS index_name, pg_size_pretty(pg_relation_size('ix_orders_open'))        AS size
UNION ALL
SELECT 'full ix_orders_status_full', pg_size_pretty(pg_relation_size('ix_orders_status_full'));

-- Q2 step 5. RESET
DROP INDEX ix_orders_open, ix_orders_status_full;


-- =====================================================================
-- Q3. CUSTOMER LOGIN BY EMAIL, IGNORING CAPITAL LETTERS
-- Technique: EXPRESSION index on lower(email).
--   Before: Seq Scan. The UNIQUE index on email stores the email as
--           written, so it cannot be used once the column is wrapped
--           in lower().
--   After:  Bitmap Index Scan on the lower(email) index.
-- =====================================================================

-- Q3 step 1. BEFORE
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, firstname, lastname, phone_num
FROM customer
WHERE lower(email) = lower('Aisha.Akinola4242@gmail.com');

-- Q3 step 2. FIX
CREATE INDEX ix_customer_email_lower ON customer (lower(email));

-- Q3 step 3. AFTER
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_id, firstname, lastname, phone_num
FROM customer
WHERE lower(email) = lower('Aisha.Akinola4242@gmail.com');

-- Q3 step 4. RESET
DROP INDEX ix_customer_email_lower;


-- =====================================================================
-- Q4. TOP 10 PRODUCTS IN A CATEGORY FOR A QUARTER (sales report)
-- Business need: best-selling Home Appliances, July-September 2026.
-- Technique: indexes on the join and filter columns, then a
-- MATERIALISED VIEW of monthly sales per product.
--   Indexes: pages read fall sharply, but the time does not improve,
--            because the report still adds up thousands of order lines.
--   View:    the report reads about 15,000 summary rows instead of
--            600,000 order lines. It must be refreshed to include new
--            sales (REFRESH MATERIALIZED VIEW mv_product_sales_monthly).
-- =====================================================================

-- Q4 step 1. BEFORE
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.product_id, p.product_name, v.business_name,
       sum(oi.quantity_ordered)                 AS units,
       sum(oi.quantity_ordered * oi.unit_price) AS revenue
FROM order_item oi
JOIN orders  o ON o.order_id   = oi.order_id
JOIN product p ON p.product_id = oi.product_id
JOIN vendor  v ON v.vendor_id  = p.vendor_id
WHERE p.category_id = 4                                    -- Home Appliances
  AND o.order_status = 'delivered'
  AND o.order_date >= '2026-07-01' AND o.order_date < '2026-10-01'
GROUP BY p.product_id, p.product_name, v.business_name
ORDER BY units DESC, p.product_id                          -- product_id breaks ties
LIMIT 10;

-- Q4 step 2. FIX A: three indexes
CREATE INDEX ix_orders_order_date  ON orders (order_date);
CREATE INDEX ix_order_item_product ON order_item (product_id);
CREATE INDEX ix_product_category   ON product (category_id);
ANALYZE orders, order_item, product;

-- Q4 step 3. AFTER FIX A (same query as step 1)
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.product_id, p.product_name, v.business_name,
       sum(oi.quantity_ordered)                 AS units,
       sum(oi.quantity_ordered * oi.unit_price) AS revenue
FROM order_item oi
JOIN orders  o ON o.order_id   = oi.order_id
JOIN product p ON p.product_id = oi.product_id
JOIN vendor  v ON v.vendor_id  = p.vendor_id
WHERE p.category_id = 4
  AND o.order_status = 'delivered'
  AND o.order_date >= '2026-07-01' AND o.order_date < '2026-10-01'
GROUP BY p.product_id, p.product_name, v.business_name
ORDER BY units DESC, p.product_id
LIMIT 10;

-- Q4 step 4. Remove the three indexes before testing the view
DROP INDEX ix_orders_order_date, ix_order_item_product, ix_product_category;

-- Q4 step 5. FIX B: materialised view of monthly sales per product
CREATE MATERIALIZED VIEW mv_product_sales_monthly AS
SELECT date_trunc('month', o.order_date)::date        AS sales_month,
       oi.product_id,
       sum(oi.quantity_ordered)                       AS units,
       sum(oi.quantity_ordered * oi.unit_price)       AS revenue
FROM order_item oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY 1, 2;

CREATE INDEX ix_mv_sales_month ON mv_product_sales_monthly (sales_month);
ANALYZE mv_product_sales_monthly;

-- Q4 step 6. AFTER FIX B: the same report, read from the view
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.product_id, p.product_name, v.business_name,
       sum(m.units)   AS units,
       sum(m.revenue) AS revenue
FROM mv_product_sales_monthly m
JOIN product p ON p.product_id = m.product_id
JOIN vendor  v ON v.vendor_id  = p.vendor_id
WHERE p.category_id = 4
  AND m.sales_month >= '2026-07-01' AND m.sales_month < '2026-10-01'
GROUP BY p.product_id, p.product_name, v.business_name
ORDER BY units DESC, p.product_id
LIMIT 10;

-- (Run steps 1 and 6 without EXPLAIN to check both give the same 10 rows.)

-- Q4 step 7. RESET
DROP MATERIALIZED VIEW mv_product_sales_monthly;


-- =====================================================================
-- Q5. PAYOUT CHECK: DOES EACH PAYOUT MATCH ITS SALES? (finance audit)
-- Business need: for the week starting 19 Oct 2026, compare each
-- payout's gross_amount with the total of the sales it settles.
-- Technique: QUERY REWRITING, then an index.
--   Before:  a correlated subquery runs once for each of the 200
--            payouts, and each run scans all 600,000 order lines.
--   Rewrite: one JOIN + GROUP BY reads order_item once (no new index).
--   Index:   an index on order_item.payout_id turns each subquery run
--            into a short lookup.
-- =====================================================================

-- Q5 step 1. BEFORE (correlated subquery; can take many seconds)
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.payout_id, p.vendor_id, p.gross_amount,
       (SELECT sum(oi.quantity_ordered * oi.unit_price)
        FROM order_item oi
        WHERE oi.payout_id = p.payout_id) AS sales_total
FROM payout p
WHERE p.start_date = '2026-10-19';

-- Q5 step 2. FIX A: rewrite as one JOIN (no index yet)
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.payout_id, p.vendor_id, p.gross_amount,
       sum(oi.quantity_ordered * oi.unit_price) AS sales_total
FROM payout p
JOIN order_item oi ON oi.payout_id = p.payout_id
WHERE p.start_date = '2026-10-19'
GROUP BY p.payout_id, p.vendor_id, p.gross_amount;

-- Q5 step 3. FIX B: index on the foreign key
CREATE INDEX ix_order_item_payout ON order_item (payout_id);

-- Q5 step 4. AFTER FIX B (the original correlated query, now indexed)
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.payout_id, p.vendor_id, p.gross_amount,
       (SELECT sum(oi.quantity_ordered * oi.unit_price)
        FROM order_item oi
        WHERE oi.payout_id = p.payout_id) AS sales_total
FROM payout p
WHERE p.start_date = '2026-10-19';

-- Q5 step 5. The audit itself: payouts that do not match (expect no rows)
SELECT p.payout_id, p.vendor_id, p.gross_amount, t.sales_total
FROM payout p
JOIN (SELECT payout_id, sum(quantity_ordered * unit_price) AS sales_total
      FROM order_item
      WHERE payout_id IS NOT NULL
      GROUP BY payout_id) t ON t.payout_id = p.payout_id
WHERE p.gross_amount <> t.sales_total;

-- Q5 step 6. RESET
DROP INDEX ix_order_item_payout;


-- =====================================================================
-- FINISH: apply the recommendations (run last, after your screenshots)
-- The four indexes and the view recommended in the analysis.
-- =====================================================================
CREATE INDEX ix_orders_customer_date ON orders (customer_id, order_date DESC);   -- Q1 (refined)
CREATE INDEX ix_orders_open          ON orders (order_date)
    WHERE order_status IN ('pending','paid','shipped');                          -- Q2
CREATE INDEX ix_customer_email_lower ON customer (lower(email));                 -- Q3
CREATE INDEX ix_order_item_payout    ON order_item (payout_id);                  -- Q5

CREATE MATERIALIZED VIEW mv_product_sales_monthly AS                             -- Q4
SELECT date_trunc('month', o.order_date)::date        AS sales_month,
       oi.product_id,
       sum(oi.quantity_ordered)                       AS units,
       sum(oi.quantity_ordered * oi.unit_price)       AS revenue
FROM order_item oi
JOIN orders o ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY 1, 2;
CREATE INDEX ix_mv_sales_month ON mv_product_sales_monthly (sales_month);

ANALYZE;
