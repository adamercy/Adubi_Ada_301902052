-- AdaLink E-commerce Marketplace
-- MIT 8103 Advanced Database Systems - Portfolio 2: Query Optimisation
-- File: AdaLink_P2_queries.sql
-- Purpose: Five business queries, each tested before and after an
--          optimisation, as reported in the Brief Performance Analysis.

DROP MATERIALIZED VIEW IF EXISTS mv_product_sales_monthly;
DROP INDEX IF EXISTS idx_id_orders, ix_orders_customer_date, ix_orders_open,
                     ix_orders_status_full, ix_customer_email_lower,
                     ix_orders_order_date, ix_order_item_product,
                     ix_product_category, ix_order_item_payout;


-- Q1. A CUSTOMER'S 10 LATEST ORDERS ("My Orders" page)
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

-- Q1 step 5. RESET
DROP INDEX idx_id_orders;

-- Q2. ORDERS STILL IN PROGRESS (operations dashboard)
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

-- Q3. CUSTOMER LOGIN BY EMAIL, IGNORING CAPITAL LETTERS
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

-- Q4. TOP 10 PRODUCTS IN A CATEGORY FOR A QUARTER (sales report)
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

-- Q4 step 6. AFTER 
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

-- Q4 step 7. RESET
DROP MATERIALIZED VIEW mv_product_sales_monthly;

-- Q5. PAYOUT CHECK: DOES EACH PAYOUT MATCH ITS SALES? (finance audit)
-- Q5 step 1. BEFORE 
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.payout_id, p.vendor_id, p.gross_amount,
       (SELECT sum(oi.quantity_ordered * oi.unit_price)
        FROM order_item oi
        WHERE oi.payout_id = p.payout_id) AS sales_total
FROM payout p
WHERE p.start_date = '2026-10-19';

-- Q5 step 2. FIX A: 
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.payout_id, p.vendor_id, p.gross_amount,
       sum(oi.quantity_ordered * oi.unit_price) AS sales_total
FROM payout p
JOIN order_item oi ON oi.payout_id = p.payout_id
WHERE p.start_date = '2026-10-19'
GROUP BY p.payout_id, p.vendor_id, p.gross_amount;

-- Q5 step 3.
CREATE INDEX ix_order_item_payout ON order_item (payout_id);

-- Q5 step 4. AFTER 
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.payout_id, p.vendor_id, p.gross_amount,
       (SELECT sum(oi.quantity_ordered * oi.unit_price)
        FROM order_item oi
        WHERE oi.payout_id = p.payout_id) AS sales_total
FROM payout p
WHERE p.start_date = '2026-10-19';

-- Q5 step 5. 
SELECT p.payout_id, p.vendor_id, p.gross_amount, t.sales_total
FROM payout p
JOIN (SELECT payout_id, sum(quantity_ordered * unit_price) AS sales_total
      FROM order_item
      WHERE payout_id IS NOT NULL
      GROUP BY payout_id) t ON t.payout_id = p.payout_id
WHERE p.gross_amount <> t.sales_total;

-- Q5 step 6. RESET
DROP INDEX ix_order_item_payout;

