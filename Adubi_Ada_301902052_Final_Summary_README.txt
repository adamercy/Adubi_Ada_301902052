MIT 8103 Advanced Database Systems: Portfolio Summary

A multi-vendor e-commerce platform | Adubi Ada | Student ID: 301902052

GitHub repository: [https://github.com/adamercy/Adubi_Ada_301902052]

Overview
AdaLink, a multi-vendor E-commerce platform, was used as a case study across all five portfolios. This platform provided a place where a lot of vendors all over Nigeria showcase their goods for customers to patronize them. They span the 36 states and the FCT, with eight regional warehouses in total, and the vendors received their payouts every other week. The sample data generated was split between PostgreSQL and MongoDB, the first contained orders, money, and stock, while the later, reviews, delivery tracking, and product details, which are linked by their IDs. All the portfolios build on one another, and you can find the screenshots, code, and README in the repository.

The summaries of all the portfolios
Portfolio 1: Database Design and Modelling. This part contains the written business rules and the Crow’s-foot ER diagram, which was mapped into 13 PostgreSQL tables, 13 primary keys, 17 foreign keys, 14 unique, and 28 CHECK constraints, as well as a partial unique index and a trigger. 11 tables reach BCNF; ‘orders and payouts’ keep a computed or repeated column on purpose, and these were protected by constraints. Also, the Nigeria sample data generated includes 300,000 orders.

Portfolio 2: Query Processing and Optimization. Five queries with EXPLAIN (ANALYZE, BUFFERS) were tested on PostgreSQL 18. An index reduced a customer’s history from 81.7ms to 0.25 ms; a partial index reduced open orders from 345.5ms to 8.3ms, and an expression index reduced an email login from 29.6ms to 0.11ms. The quarterly sales report got no faster with indexes, but it was reduced from 375.4ms to 27.5ms with a materialized view, and the rewritten correlated subquery reduced the payout audit from 29.7ms to 272.7ms.

Portfolio 3: Transactions and Concurrency. I demonstrated this part with two pyAdmin sessions on one phone’s stock in Lagos and Kano. This displayed a commit (10/10 turned to 8/12), a rollback (3/17 inside the transaction, returned to 8/12 after ‘ROLLBACK’), and, of course, the isolation (session B saw 8 until session A committed, then it became 7), and the concurrency control part (session B waited for a row lock, and the stock ended at 5, with no sale lost).

Portfolio 4: NoSQL and Advanced Data Models. I used MongoDB Atlas to build a document model: reviews in their own collections, products with embedded specifications, and parcels with embedded tracking events, enforced by validators and unique indexes. 5,000 products were loaded, 10,498 reviews were loaded, and 4,391 parcels were produced from the PostgreSQL data; I ran five operations (find, insert, aggregate, $push, update, and a one-read parcel history, and it also explained why a document model fits this data better than tables, key-value, column, and graph models.

Portfolio 5: Distributed and Cloud database. My system’s Atlas cluster (free tier, AWS Paris, MongoDB 8.0.37) is a three-node replica set. I established the primary, saved a review with a majority write concern, read it back from a secondary (‘shard-00-02’), and analyzed automatic failover, eventual consistency, and how the AdaLink database will shard reviews by a hashed ‘product_id’ as it grows.

Screenshots and Proof
Each portfolio folder in the repository contains screenshots, scripts, and a README that ties them together.

Individual Reflection
It took so much thought to design the split between PostgreSQL and MongoDB, and those choices for examples, keeping reviews in their collection, formed portfolios 4, and 5.

After reviewing portfolio 2, it totally changed how I think about performance. I expected that indexes would solve every slow query, but the quarterly report read 93% fewer pages with indexes and was still no faster. Although a materialized view was used to fix it. Rewriting the 30-second payout audit as a join, with no index at all, reduced it to under 0.3 seconds. Now I know that how a query is written matters as much as its indexes.

Portfolio 3 taught me that simple examples explain concepts better than complex ones: I reduced my first complex transaction examples down to one per concept, and seeing session B wait on a lock made concurrency control concrete.

Subsequently, I will screenshot each before-and-after pair in one sitting (I had to re-run Q4), experiment with stricter isolation levels, and use a less-privileged database user from the start instead of the admin role.

Reference
- MongoDB, Inc. (2026) *Replication and Replica Set Fundamentals*. Available at: [mongodb.com/docs/manual/replication] (https://www.mongodb.com/docs/manual/replication/) (Accessed: 9 November 2026).
-MongoDB, Inc. (2026) *Write Concern*. Available at: [mongodb.com/docs/current/reference/write-concern] (https://www.mongodb.com/docs/current/reference/write-concern/) (Accessed: 9 November 2026).
- MongoDB, Inc. (2026) *Best Practices for Data Modeling in MongoDB*. Available at: [mongodb.com/docs/current/reference/write-concern] (https://www.mongodb.com/docs/current/reference/write-concern/) (Accessed: 9 November 2026).
- [https://www.postgresql.org/docs/18/ddl-constraints.html]
- [https://www.postgresql.org/docs/18/using-explain.html]
- [https://www.postgresql.org/docs/18/tutorial-transactions.html]
- [https://www.postgresql.org/docs/18/transaction-iso.html]
- [https://www.postgresql.org/docs/18/indexes-unique.html]
- Anthropic (2026) *Claude* \ [AI assistant\]. Available at: [claude.ai] (https://claude.ai) (Accessed: 9 November 2026).

AI-use declaration
In this Continuous Assessment, Claude (Anthropic), an AI Assistant, was used. It assisted me in writing the design document based on my decisions, wrote the SQL and MongoDB scripts, and generated Nigerian sample data. The design decisions were made by me, including splitting and simplifying the PostgreSQL/MongoDB transaction examples. I ran every script on my PostgreSQL and set up MongoDB Atlas, took all the screenshots, and checked the results against the assessment requirements, and edited the written work. I understand the work, and remain responsible for its accuracy.

