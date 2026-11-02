// =====================================================================
// AdaLink E-commerce Marketplace
// MIT 8103 Advanced Database Systems - Portfolio 1: Database Design
// File: 02_mongodb_schema.js
// Purpose: The MongoDB half of the AdaLink split design.
//
// MongoDB is the master for content and event data that never feeds a
// financial calculation. Three collections:
//   products           Product's multivalued {specification} (rule E6),
//                      plus display copies of PostgreSQL product data
//   reviews            Customer reviews Product (rule 16), referencing products._id
//   shipment_tracking  ShipmentEvent (rules E11, 15), embedded per shipment
// Every collection has a $jsonSchema validator, so MongoDB rejects
// documents that break the rules, just as PostgreSQL CHECK constraints do.
//
// Links to PostgreSQL use the same identifiers:
//   products._id          = product.product_id
//   reviews.customer_id   = customer.customer_id
//   reviews.product_id    = product.product_id
//   shipment_tracking._id = shipment.shipment_id
// MongoDB cannot check that these exist in PostgreSQL, so the
// application checks them before writing (see the design document).
//
// How to run: mongosh "mongodb://localhost:27017" --file 02_mongodb_schema.js
// (or paste into the mongosh tab of MongoDB Compass). Safe to re-run.
// =====================================================================

db = db.getSiblingDB("adalink");

["products", "reviews", "shipment_tracking"].forEach(function (name) {
  if (db.getCollectionNames().includes(name)) { db.getCollection(name).drop(); }
});

const money = ["decimal", "double", "int", "long"];   // numeric types accepted for amounts
const id    = ["int", "long"];                         // identifiers shared with PostgreSQL


// ---------------------------------------------------------------------
// 1. products: the product catalogue document
// One document per product. MongoDB is the master for "specifications";
// every other field is a display copy refreshed from PostgreSQL (the
// master), so a catalogue page needs a single read.
// ---------------------------------------------------------------------
db.createCollection("products", {
  validator: { $jsonSchema: {
    bsonType: "object",
    title: "AdaLink product catalogue document",
    required: ["_id", "sku_code", "product_name", "unit_price", "is_available",
               "category", "vendor", "specifications", "synced_at"],
    properties: {
      _id:            { bsonType: id, description: "= product.product_id in PostgreSQL" },

      // ---- master data held only in MongoDB (rule E6) ----
      specifications: {
        bsonType: "object",
        description: "Multivalued {specification}: spec_name -> spec_value. Object keys are unique, " +
                     "so a product cannot have two specifications with the same name.",
        additionalProperties: { bsonType: "string", minLength: 1 }
      },

      // ---- display copies of PostgreSQL data (never edited here) ----
      sku_code:       { bsonType: "string", minLength: 1 },
      product_name:   { bsonType: "string", minLength: 1 },
      unit_price:     { bsonType: money, minimum: 0, exclusiveMinimum: true },
      is_available:   { bsonType: "bool" },
      category: {
        bsonType: "object", required: ["category_id", "category_name"],
        properties: { category_id: { bsonType: id }, category_name: { bsonType: "string" } }
      },
      vendor: {
        bsonType: "object", required: ["vendor_id", "business_name"],
        properties: { vendor_id: { bsonType: id }, business_name: { bsonType: "string" } }
      },

      // ---- summary computed from the reviews collection ----
      // Two numbers only, so the document stays the same size however
      // many reviews a product receives. The reviews themselves are never
      // embedded here: they live in the reviews collection.
      rating_summary: {
        bsonType: "object", required: ["average", "count"], additionalProperties: false,
        properties: {
          average: { bsonType: ["double", "int"], minimum: 0, maximum: 5 },
          count:   { bsonType: ["int", "long"], minimum: 0 }
        }
      },
      synced_at: { bsonType: "date", description: "When the PostgreSQL copies were last refreshed" }
    },
    additionalProperties: false     // no other fields, so reviews cannot be embedded by mistake
  } },
  validationLevel: "strict",
  validationAction: "error"
});
db.products.createIndex({ sku_code: 1 }, { unique: true, name: "ux_products_sku_code" });
db.products.createIndex({ "category.category_id": 1, is_available: 1 }, { name: "ix_products_category_available" });
db.products.createIndex({ product_name: "text" }, { name: "tx_products_name" });


// ---------------------------------------------------------------------
// 2. reviews: Customer reviews Product (rule 16)
// A collection of its own, one document per review. A product can
// receive thousands of reviews, so they are REFERENCED, not embedded:
// each review carries product_id, which matches products._id (and
// product.product_id in PostgreSQL). Product documents therefore stay
// small, and a product's reviews are fetched with
//   db.reviews.find({ product_id: 1 }).sort({ review_date: -1 })
// using the ix_reviews_product_latest index.
// Rule 16's "at most once per customer per product" is a unique index;
// the "only after delivery" check is made by the application against
// PostgreSQL before the review is inserted.
// ---------------------------------------------------------------------
db.createCollection("reviews", {
  validator: { $jsonSchema: {
    bsonType: "object",
    title: "AdaLink product review",
    required: ["customer_id", "product_id", "rating", "review_date"],
    additionalProperties: false,
    properties: {
      _id:         { bsonType: "objectId" },
      customer_id: { bsonType: id, description: "= customer.customer_id in PostgreSQL" },
      product_id:  { bsonType: id, description: "= product.product_id in PostgreSQL" },
      rating:      { bsonType: "int", minimum: 1, maximum: 5 },
      comment:     { bsonType: "string", maxLength: 2000, description: "optional" },
      review_date: { bsonType: "date" }
    }
  } },
  validationLevel: "strict",
  validationAction: "error"
});
db.reviews.createIndex({ customer_id: 1, product_id: 1 }, { unique: true, name: "ux_reviews_customer_product" });
db.reviews.createIndex({ product_id: 1, review_date: -1 }, { name: "ix_reviews_product_latest" });


// ---------------------------------------------------------------------
// 3. shipment_tracking: ShipmentEvent (rules E11, 15)
// One document per shipment, with its tracking events embedded as an
// array. Embedding enforces rule 15 by structure: an event can only
// belong to the shipment whose document contains it. New events are
// appended with $push. "details" holds carrier-specific data (driver,
// GPS, proof of delivery), which differs between couriers.
// ---------------------------------------------------------------------
db.createCollection("shipment_tracking", {
  validator: { $jsonSchema: {
    bsonType: "object",
    title: "AdaLink shipment tracking history",
    required: ["_id", "order_id", "tracking_num", "carrier", "events"],
    additionalProperties: false,
    properties: {
      _id:          { bsonType: id, description: "= shipment.shipment_id in PostgreSQL" },
      order_id:     { bsonType: id, description: "copy of shipment.order_id" },
      tracking_num: { bsonType: "string", description: "copy of shipment.tracking_num" },
      carrier:      { bsonType: "string", description: "copy of shipment.carrier" },
      events: {
        bsonType: "array",
        items: {
          bsonType: "object",
          required: ["event_id", "event_status", "location", "event_date", "event_time"],
          additionalProperties: false,
          properties: {
            event_id:     { bsonType: "int", minimum: 1, description: "1, 2, 3 ... within the shipment" },
            event_status: { enum: ["created", "picked_up", "in_transit", "out_for_delivery",
                                   "delivered", "failed_attempt", "returned"] },
            location:     { bsonType: "string", minLength: 1 },
            event_date:   { bsonType: "date" },
            event_time:   { bsonType: "string", pattern: "^([01][0-9]|2[0-3]):[0-5][0-9]$" },
            details:      { bsonType: "object", description: "optional, carrier-specific" }
          }
        }
      }
    }
  } },
  validationLevel: "strict",
  validationAction: "error"
});
db.shipment_tracking.createIndex({ tracking_num: 1 }, { unique: true, name: "ux_tracking_tracking_num" });
db.shipment_tracking.createIndex({ order_id: 1 }, { unique: true, name: "ux_tracking_order" });
db.shipment_tracking.createIndex({ "events.event_status": 1 }, { name: "ix_tracking_event_status" });


print("AdaLink MongoDB schema created: " +
      db.getCollectionNames().filter(n => ["products", "reviews", "shipment_tracking"].includes(n)).length +
      " collections");
