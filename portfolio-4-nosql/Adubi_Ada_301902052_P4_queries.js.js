// =====================================================================
// AdaLink E-commerce Marketplace
// MIT 8103 Advanced Database Systems - Portfolio 4: NoSQL (MongoDB)
// File: AdaLink_P4_queries.js
// Purpose: Five example operations on the AdaLink document model.
//
// Needs: 02_mongodb_schema.js run first, then the three JSON files
//        imported (products 5,000 / reviews 10,498 / shipment_tracking 4,391).
//
// HOW TO RUN (MongoDB Compass)
//   Open the >_MONGOSH panel at the bottom of Compass. Copy ONE query
//   block at a time (from its [Q..] label to the next label), paste it
//   at the prompt and press Enter. Screenshot each result.
// =====================================================================

use adalink


// ---------------------------------------------------------------------
// [Q1] FIND: phones and tablets with 8 GB of RAM, cheapest first
// Searches inside the embedded "specifications" object. Only products
// that have a "ram" specification can match; a bag of rice simply has
// no such field, and no empty column is needed for it.
// ---------------------------------------------------------------------
db.products.find(
  { "category.category_id": 1, "specifications.ram": "8 GB", is_available: true },
  { product_name: 1, unit_price: 1, "specifications.ram": 1,
    "specifications.storage": 1, "vendor.business_name": 1 }
).sort({ unit_price: 1 }).limit(5)


// ---------------------------------------------------------------------
// [Q2] INSERT: customer 9 reviews the TV she received
// Chiamaka Adeyemi (customer 9) received an LG 32-inch LED TV
// (product 2083) on 26 April 2026. Both IDs are the same as in PostgreSQL.
// ---------------------------------------------------------------------
db.reviews.insertOne({
  customer_id: 9,
  product_id: 2083,
  rating: 5,
  comment: "Clear picture and it arrived in Onitsha in two days.",
  review_date: new Date("2026-11-05")
})

// [Q2b] Run the same insert again to test the rules:
// it is refused with "E11000 duplicate key error", because the unique
// index ux_reviews_customer_product allows one review per customer per product.
db.reviews.insertOne({
  customer_id: 9,
  product_id: 2083,
  rating: 5,
  comment: "Clear picture and it arrived in Onitsha in two days.",
  review_date: new Date("2026-11-05")
})


// ---------------------------------------------------------------------
// [Q3] AGGREGATE: the five best-rated products (at least 30 reviews)
// Groups all reviews by product, works out each average, keeps the
// well-reviewed ones, then looks up each product's name.
// ---------------------------------------------------------------------
db.reviews.aggregate([
  { $group: { _id: "$product_id",
              average_rating: { $avg: "$rating" },
              reviews: { $sum: 1 } } },
  { $match: { reviews: { $gte: 30 } } },
  { $sort: { average_rating: -1, reviews: -1 } },
  { $limit: 5 },
  { $lookup: { from: "products", localField: "_id", foreignField: "_id", as: "product" } },
  { $project: { _id: 0,
                product_id: "$_id",
                product_name: { $first: "$product.product_name" },
                average_rating: { $round: ["$average_rating", 1] },
                reviews: 1 } }
])


// ---------------------------------------------------------------------
// [Q4] UPDATE: add a "returned" event to a parcel
// Order 271557 was refunded. Its parcel ADL000271557 already has six
// events (including one failed delivery attempt); $push adds the return
// as event 7 at the end of the embedded events array.
// ---------------------------------------------------------------------
db.shipment_tracking.updateOne(
  { tracking_num: "ADL000271557" },
  { $push: { events: {
      event_id: 7,
      event_status: "returned",
      location: "Lagos Island Hub, Lekki",
      event_date: new Date("2026-09-08"),
      event_time: "11:30",
      details: { reason: "Customer requested a refund", condition: "Unopened" }
  } } }
)


// ---------------------------------------------------------------------
// [Q5] READ ONE PARCEL: the full delivery history of ADL000271557
// One read returns the whole history, because the events are stored
// inside the parcel's own document. $unwind turns the array into one
// row per event so it reads like a timeline.
// ---------------------------------------------------------------------
db.shipment_tracking.aggregate([
  { $match: { tracking_num: "ADL000271557" } },
  { $unwind: "$events" },
  { $project: { _id: 0,
                step: "$events.event_id",
                status: "$events.event_status",
                location: "$events.location",
                date: { $dateToString: { format: "%Y-%m-%d", date: "$events.event_date" } },
                time: "$events.event_time" } }
])
