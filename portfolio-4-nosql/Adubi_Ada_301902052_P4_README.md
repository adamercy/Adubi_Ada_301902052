# Portfolio 4: NoSQL and Advanced Data Models (MongoDB)

In this portfolio I built a **document model** in MongoDB for the same AdaLink multi-vendor e-commerce platform. MongoDB holds the data whose shape varies or grows as a stream of events; PostgreSQL keeps the money, stock and orders.

**Files:** `02_mongodb_schema.js` (collections, validation rules, indexes), three `adalink.*.json` data files (5,000 products, 10,498 reviews, 4,391 parcels), `AdaLink_P4_queries.js` (Q1–Q5) and `screenshots/`.

## The model

| Collection | One document per | Design | Link to PostgreSQL |
| --- | --- | --- | --- |
| `products` | product | Specifications **embedded**; their fields differ by product type | `_id` = `product_id` |
| `reviews` | review | Own collection, **referencing** the product | `customer_id`, `product_id` |
| `shipment_tracking` | parcel | Tracking events **embedded** as an ordered array | `_id` = `shipment_id` |

Product 777 has `{ brand: "Tecno", ram: "8 GB", storage: "128 GB" }`, while a bag of rice has `{ weight: "50 kg", rice_type: "Long grain parboiled" }`. Each collection has a `$jsonSchema` validator that rejects documents breaking its rules, and a unique index allows one review per customer per product. I generated the data from the PostgreSQL data, so every ID matches a real row.

## Implementation and results

I ran the schema script and imported the files in MongoDB Compass, then ran each query in the mongosh panel.

| Query | What it does | Result |
| --- | --- | --- |
| Q1 Find | Phones with 8 GB RAM, cheapest first | 5 products, from ₦137,750 |
| Q2 Insert | Customer 9 reviews her LG TV, then the same insert again | Saved; repeat refused with `E11000 duplicate key error` |
| Q3 Aggregate | Five best-rated products with 30+ reviews | Top: Binatone Blender, 4.4 from 54 reviews |
| Q4 Update | `$push` a "returned" event onto parcel ADL000271557 | 1 document modified |
| Q5 Read | That parcel's full history | 7 events, "created" to "returned" |

## Why the document model suits this data

- **Specifications vary by product.** In tables they would need many mostly empty columns or an extra table joined on every read. A document stores only what each product has, and Q1 queries it directly.
- **Tracking events belong to one parcel and only grow.** Embedded, a new event is one small update (Q4) and the whole history is one read with no join (Q5).
- **Reviews can run into hundreds per product,** so they sit in their own collection and keep product documents small. Q3 shows the aggregation pipeline reporting across all of them.

Other NoSQL models fit less well. Key-value suits simple lookups by one key, which is why AdaLink's shopping carts would use Redis, but it cannot search inside specifications. Column stores suit analysis of huge volumes, and graph databases suit connections such as "customers who bought this also bought". Neither describes a product catalogue or a parcel history.

## Reference: 
- [mongodb.com/docs/manual/replication](https://www.mongodb.com/docs/manual/replication/)

