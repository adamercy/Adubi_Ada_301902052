// =====================================================================
// AdaLink E-commerce Marketplace
// MIT 8103 Advanced Database Systems - Portfolio 5: Distributed / Cloud
// File: AdaLink_P5_replication.js
// Purpose: Evidence that the AdaLink MongoDB database runs as a
//          replicated cloud database on MongoDB Atlas.
//
// Run in the mongosh panel of MongoDB Compass while connected to the
// Atlas cluster used in Portfolio 4. Paste ONE block at a time
// (from its [P5-..] label to the next label), press Enter and take a
// screenshot of the result.
// =====================================================================

use adalink


// ---------------------------------------------------------------------
// [P5-1] REPLICATION: which servers hold the database?
// An Atlas cluster is a replica set: three servers, each with a full
// copy of the data. One is the primary (takes all writes); the other
// two are secondaries (copy every change from the primary).
// ---------------------------------------------------------------------
h = db.hello();   // safe to run more than once
({ replica_set: h.setName, servers: h.hosts, primary: h.primary, connected_to: h.me, can_write_here: h.isWritablePrimary })


// ---------------------------------------------------------------------
// [P5-2] CONSISTENCY: a write confirmed by a majority of servers
// Customer 9 reviews the wardrobe she received in April 2026.
// writeConcern "majority" makes MongoDB reply only after at least two
// of the three servers have saved the review, so it survives the loss
// of any one server.
// ---------------------------------------------------------------------
db.reviews.insertOne(
  { customer_id: 9, product_id: 1086, rating: 4,
    comment: "Solid wardrobe, and the delivery team helped me set it up.",
    review_date: new Date("2026-11-07") },
  { writeConcern: { w: "majority", wtimeout: 5000 } }
)


// ---------------------------------------------------------------------
// [P5-3] REPLICATION AT WORK: read the new review from a SECONDARY
// readPref("secondary") sends the read to one of the copies, not the
// primary. The review is there because the primary replicated it.
// ---------------------------------------------------------------------
db.reviews.find({ customer_id: 9, product_id: 1086 }).readPref("secondary")


// ---------------------------------------------------------------------
// [P5-4] Which server answered the read in P5-3?
// The host shown here is a secondary: compare it with "primary" in P5-1.
// ---------------------------------------------------------------------
db.reviews.find({ customer_id: 9, product_id: 1086 }).readPref("secondary").explain().serverInfo
// (If Atlas refuses explain on the free tier, skip this step; P5-3 is enough.)
