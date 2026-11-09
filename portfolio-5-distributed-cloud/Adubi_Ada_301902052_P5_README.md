# Portfolio 5: Distributed and Cloud Database

In this portfolio I show the AdaLink MongoDB database running as a distributed cloud database on **MongoDB Atlas**, the same cluster I used in Portfolio 4. I demonstrate deployment, replication and consistency with evidence, and discuss availability and sharding, which the free tier cannot demonstrate.

**Files:** `AdaLink_P5_replication.js` (four commands) and `screenshots/`.

## Deployment

| Setting | Value |
| --- | --- |
| Service | MongoDB Atlas, free tier (Cluster0) |
| Cloud and region | AWS, Paris (eu-west-3) |
| Type | Replica set, 3 nodes |
| MongoDB version | 8.0.37 |
| Data | `adalink` database: products, reviews, shipment_tracking |

Access is restricted in two ways. The IP access list allows only three specific addresses (no open `0.0.0.0/0` entry), and connections need a database user that signs in with SCRAM password authentication.

## Results

| Step | What I did | Result |
| --- | --- | --- |
| P5-1 | Asked the cluster which servers it has (`db.hello()`) | Replica set `atlas-pmxhwm-shard-0`; 3 servers; primary `shard-00-01` |
| P5-2 | Customer 9 reviewed her wardrobe with `writeConcern: "majority"` | `acknowledged: true` |
| P5-3 | Read the new review with `readPref("secondary")` | The review was returned from a copy |
| P5-4 | Checked which server answered P5-3 | `shard-00-02`, a secondary, not the primary |

## Discussion

**Replication.** Every write goes to the primary (`shard-00-01`), and the two secondaries copy each change, so all three servers hold the full AdaLink data. P5-3 and P5-4 prove it: a review written to the primary was read back from `shard-00-02`.

**Consistency.** With `writeConcern: "majority"`, MongoDB confirmed the review only after at least two of the three servers had saved it, so it survives the loss of any one server. Reads from a secondary can be a moment behind the primary (eventual consistency), so AdaLink would use them only where that is acceptable, such as showing reviews.

**Availability.** If the primary fails, the secondaries elect a new primary within seconds, and the application carries on because its connection string lists all three servers and retries the write. The free tier cannot test a failover and has no backups, so production would use a paid tier with backups, in a region nearer Nigeria such as AWS Cape Town.

**Sharding.** Sharding splits data across several replica sets, which the free tier does not allow, so this is a design for growth. Reviews would be sharded on a hashed `product_id` and shipment tracking on a hashed `_id`; the 5,000 products are too few to need it. On the PostgreSQL side, a managed service such as Amazon RDS would keep a standby copy for failover, and the `orders` table could be partitioned by `order_date`.

**Improvement.** My database user has the broad `atlasAdmin` role. In production the application would get a user with `readWrite` access to `adalink` only.

## Reference
- [mongodb.com/docs/current/reference/write-concern](https://www.mongodb.com/docs/current/reference/write-concern/)

