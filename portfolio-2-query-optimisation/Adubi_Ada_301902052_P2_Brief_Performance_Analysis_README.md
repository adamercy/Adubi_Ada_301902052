# Adubi_Ada_301902052 Portfolio 2: Brief Performance Analysis

I tested five AdaLink queries to see how much indexing and other changes could speed them up. Four became 42 to 913 times faster; the quarterly sales report did not get faster with indexes and only improved with a materialised view.

## 1. What I tested and how

I chose five queries AdaLink would run every day and ran each one in pgAdmin 4 on PostgreSQL 18 on my own computer, using the sample data (300,000 orders and 600,000 order lines). I ran `EXPLAIN (ANALYZE, BUFFERS)` before and after each change and took screenshots of both plans. At the start PostgreSQL had only indexed primary keys and UNIQUE columns; it does not index foreign keys such as `orders.customer_id`. The SQL is in `Adubi_Ada_301903052_P2_Adalink_queries.sql`. 

## 2. Results

| Query | Optimisation | Plan change | Before (ms) | After (ms) | Pages read (8 kB) | Speed-up |
| --- | --- | --- | --- | --- | --- | --- |
| Q1 Customer's latest orders | Index on customer\_id | Seq Scan → Index Scan | 81.7 | 0.25 | 5,897 → 32 | 334× |
| Q2 Orders in progress | Partial index | Seq Scan → Bitmap Index Scan | 345.5 | 8.3 | 5,979 → 1,886 | 42× |
| Q3 Login by email | Index on lower(email) | Seq Scan → Bitmap Index Scan | 29.6 | 0.11 | 627 → 4 | 271× |
| Q4 Quarterly top products | (a) Three indexes (b) Materialised view | (a) Seq Scan on order\_item in both (b) reads summary rows only | 375.4 | (a) 415.2 (b) 27.5 | 165,335 → (a) 11,472 (b) 1,132 | (a) none (b) 13.7× |
| Q5 Payout audit | (a) Index on payout\_id (b) JOIN rewrite | (a) 200 Seq Scans → 200 Index Scans (b) one scan of order\_item | 29,708 | (a) 32.5 (b) 272.7 | (a) 1,816,191 → \~4,700 (b) 1,816,191 → 10,268 | (a) 913× (b) 109× |

## 3. What I found

An index helps most when a query needs only a small part of a table. When it needs most of the table, the query itself or the data it reads has to change.

Q1 and Q3 show this. Customer 9 has 26 of the 300,000 orders, yet without an index PostgreSQL read the whole table (5,897 pages); with one it read 32. Q3 also taught me that the index must match the query: PostgreSQL ignored the UNIQUE index on email because the query uses `lower(email)`, and only an index on that expression worked.

In Q2 I indexed only the 5,026 unfinished orders (1.7%). This partial index is 128 kB, against 11 MB for a full one, and the query ran 42 times faster.

Q4 was the most interesting result. Three indexes cut the pages read from 165,335 to 11,472, but the time did not improve (375.4 ms before, 415.2 ms after), because those pages were mostly in memory already and the report still adds up thousands of order lines. A materialised view of monthly sales per product brought it down to 27.5 ms.

Q5 showed that how a query is written can matter more than an index. The correlated subquery scanned all 600,000 order lines once per payout, 200 times over, and took almost 30 seconds. Rewritten as one JOIN it took 272.7 ms; with an index on payout\_id, the original took 32.5 ms.


