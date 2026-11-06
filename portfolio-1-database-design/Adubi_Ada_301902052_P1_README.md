# Portfolio 1: Database Design and Modelling

## Case study

AdaLink is a **multi-vendor e-commerce platform**: it does not make the goods it sells. Independent businesses (vendors) list their products on AdaLink, and registered customers anywhere in Nigeria's 36 states and the Federal Capital Territory buy them online.

## Users

| User | What they use the database for |
| --- | --- |
| **Customers** | Register, save delivery addresses, browse and search the catalogue, place orders, pay, track deliveries, review products they received. |
| **Vendors** | List products and their specifications, update prices and availability, view their sales and weekly payouts. |
| **Warehouse and logistics staff** | Manage stock levels, dispatch orders. Courier systems send tracking events automatically. |
| **Customer support** | View customers' order, payment and delivery history; handle cancellations and refunds. |
| **Finance and administration** | Reconcile payments, calculate and send vendor payouts, set commission rates, produce sales and revenue reports. |

## Main operations

Key operations the database will support:

- **Register a customer** and save delivery addresses, one of which may be the default.
- **Add and update products**: list a product, change its price or availability, and record its specifications.
- **Search and browse the catalogue** by name and category, with each product's specifications and average rating.
- **Place an order**: check and reserve stock, record each product with the price paid and the commission rate at that moment, add the delivery fee and calculate the total, all in one transaction.
- **Record payments**, including failed attempts, retries and refunds.
- **Dispatch and track deliveries**: create the shipment, record each tracking event, and mark the order delivered.
- **Review a product**, allowed only after an order containing it has been delivered, and at most once per product.
- **Pay vendors weekly**: calculate each vendor's gross sales, commission and net amount, and link each sale to the payout that settled it.
- **Produce reports**: sales by product, category and state; stock below reorder level; revenue from commission and delivery fees.

## Database environment

AdaLink uses two databases, and each keeps the data it is responsible for changing.

- **PostgreSQL 16** is the system of record for everything that involves money, stock or strict integrity between tables: customers, vendors, products, stock, orders, payments, shipments and payouts.
- **MongoDB 8** holds content and event data that never feeds a financial calculation: product specifications, reviews and shipment tracking events.

The two are linked by shared identifiers such as `product_id` and `customer_id`.

## Business rules

The rules describe how AdaLink works and are the basis of the ER diagram. Part A names each entity, its identifier and its attributes. Part B states how the entities are related: the words *one*, *many*, *must* and *may* set each relationship's cardinality and participation, and where a relationship has attributes of its own, the rule says what is recorded *when* the relationship occurs (shown in bold).

### A. Entities and their attributes

**E1.** Each **customer** is identified by a customer ID and has a first name, a last name, an email address, a phone number (a Nigerian mobile number in +234 format) and a registration date. No two customers may share an email address or a phone number.

**E2.** Each **address** is identified by an address ID and has an addressLine, a city and an indicator showing whether it is the customer's default address.

**E3.** Each **state** is identified by its two-letter state code and has a state name, which is unique, and the geopolitical region it belongs to.

**E4.** Each **vendor** is identified by a vendor ID and has a business name and an email address, both unique, a phone number and the date the vendor joined AdaLink.

**E5.** Each **category** is identified by a category ID and has a name, which is unique, and a commission rate: the percentage of each sale that AdaLink keeps, between 0% and 50%.

**E6.** Each **product** is identified by a product ID and has a stock-keeping unit (SKU) code, which is unique, a name, a current unit price greater than zero, an indicator showing whether it is currently available for purchase, and the date it was listed. Each product also has a set of **specifications** that depends on its category, for example RAM and storage for a phone, or size and color for a shoe; each specification has a name and a value, and a product cannot have two specifications with the same name.

**E7.** Each **warehouse** is identified by a warehouse ID and has a code, which is unique, and a name.

**E8.** Each **order** is identified by an order ID and has an order date, a status (pending, paid, shipped, delivered, cancelled or refunded), a delivery fee, which may be zero for free delivery, and a total amount.

**E9.** Each **payment** is identified by a payment ID and has a method (card, bank transfer, USSD, wallet or pay on delivery), an amount greater than zero, a status (pending, successful, failed or refunded), a reference from the payment provider, which is unique, the date it was made and, if successful, the date it was paid.

**E10.** Each **shipment** is identified by a shipment ID and has a tracking number, which is unique, a carrier, a dispatch date and, once delivered, a delivery date, which cannot be earlier than the dispatch date.

**E11.** Each **shipment event** is identified by an event ID and has a status (created, picked up, in transit, out for delivery, delivered, failed attempt or returned), a location and the date and time it happened.

**E12.** Each **payout** is identified by a payout ID and has a period start date, a period end date, a gross amount, a commission amount, a net amount, a status (pending, paid or failed), a bank transfer reference, which is unique, and, once paid, the date it was paid.

### B. Relationships

#### Customers and locations

1. A customer may save many delivery addresses; each address belongs to exactly one customer.
2. Of the addresses a customer saves, at most one may be marked as the default (using the address's default indicator).
3. Each address, vendor and warehouse is located in exactly one state; a state may contain many addresses, vendors and warehouses.

#### Catalogue

4. A vendor may list many products; each product is listed by exactly one vendor.
5. Each product belongs to exactly one category; a category may contain many products.
6. A category may contain many sub-categories; each sub-category belongs to at most one parent category.
7. The commission AdaLink earns on a sale is set by the commission rate of the category of the product sold.
8. A product may be stocked in many warehouses, and a warehouse may stock many products. When a warehouse stocks a product, the **quantity on hand**, which can never be negative, the **reorder level** and the **date the stock level was last updated** are recorded.

#### Orders and payments

9. Only registered customers can buy. A customer may place many orders; each order is placed by exactly one customer.
10. Each order is delivered to exactly one address, which must belong to the customer who placed the order; an address may be used for many orders.
11. An order must contain at least one product, and a product may appear in many orders. When a product is included in an order, the **quantity ordered** (at least one), the **unit price actually paid** and the **commission rate that applied at the time of sale** are recorded. A product appears at most once in any order.
12. An order's total amount equals the quantity ordered times the unit price paid for every product in the order, plus the order's delivery fee.
13. An order may have many payment attempts (failed, successful or refunded); each payment belongs to exactly one order.

#### Delivery and reviews

14. An order is sent in at most one shipment (none until it is dispatched); each shipment carries exactly one order and leaves from exactly one warehouse. A warehouse may dispatch many shipments.
15. A shipment may have many shipment events; each shipment event belongs to exactly one shipment.
16. A customer may review many products, and a product may be reviewed by many customers, but only after an order containing that product has been delivered to the customer. A customer may review each product at most once. When a customer reviews a product, the **rating** (1 to 5), an optional **comment** and the **review date** are recorded.

#### Vendor payouts

17. A vendor may receive many payouts; each payout goes to exactly one vendor and covers one week of sales. A vendor receives at most one payout per week.
18. A payout may settle many products sold in delivered orders; each product sold in an order is settled by at most one payout, and only by a payout to the vendor who sold it. Delivery fees are kept by AdaLink and are never paid out.
19. A payout's gross amount is the quantity times the unit price paid for every product sale it settles; its commission amount applies the commission rate recorded at each sale; its net amount equals the gross amount minus the commission amount.

ERDiagram Link: [https://app.diagrams.net/#G1EiZ3CjIBjuppMmLiwRLIcKxS3fizAldl#%7B%22pageId%22%3A%22ojahub-erd%22%7D]

## Scope

AdaLink Ltd is a simulated online marketplace based in Lagos, Nigeria. The scenario is realistic but fictional: the organization, its people and its data are invented for this coursework, and all sample data is generated.

Reference: [https://www.postgresql.org/docs/18/ddl-constraints.html]
