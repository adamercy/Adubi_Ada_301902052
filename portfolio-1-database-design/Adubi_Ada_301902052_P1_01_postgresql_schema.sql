-- =====================================================================
-- AdaLink E-commerce Marketplace
-- MIT 8103 Advanced Database Systems - Portfolio 1: Database Design
-- File: 01_postgresql_schema.sql
-- Purpose: The PostgreSQL half of the AdaLink split design.
--
-- Split design: each store keeps the data it is responsible for changing.
--   PostgreSQL (this file, 13 tables) is the master for everything that
--   involves money, stock or strict referential integrity:
--     state, customer, address, vendor, warehouse, category, product,
--     warehouse_stock, orders, order_item, payment, payout, shipment
--   MongoDB (02_mongodb_schema.js) is the master for content and event
--   data that never feeds a financial calculation:
--     products collection         -> Product's multivalued {specification}
--     reviews collection          -> Customer reviews Product (rule 16)
--     shipment_tracking collection-> ShipmentEvent (rules E11, 15)
--   The two stores are linked by shared identifiers (product_id,
--   customer_id, shipment_id), never by copying the same data twice
--   as a master.
--
-- DBMS: PostgreSQL 16 or later. Safe to re-run.
-- =====================================================================

DROP TABLE IF EXISTS review, shipment_event, shipment, payment, order_item,
                     payout, orders, warehouse_stock, product_specification,
                     product, category, warehouse, vendor, address, customer,
                     state CASCADE;
DROP FUNCTION IF EXISTS check_review_after_delivery() CASCADE;
DROP FUNCTION IF EXISTS check_sale_payout() CASCADE;


-- =====================================================================
-- PART A. TABLES FROM ENTITIES
-- Mapping rule: each entity becomes a table; its identifier becomes the
-- primary key; its attributes become columns. For every one-to-many
-- relationship, the primary key of the "one" side is added as a foreign
-- key on the "many" side (NOT NULL where participation is mandatory).
-- =====================================================================

-- State (rule E3). Reference data used by address, vendor and warehouse.
CREATE TABLE state (
    state_code   CHAR(2)      PRIMARY KEY,                       -- e.g. 'LA' = Lagos
    state_name   VARCHAR(40)  NOT NULL UNIQUE,
    geo_region   VARCHAR(15)  NOT NULL
        CHECK (geo_region IN ('North Central','North East','North West',
                              'South East','South South','South West'))
);

-- Customer (rule E1). customer_id is also used by MongoDB reviews.
CREATE TABLE customer (
    customer_id        BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    firstname          VARCHAR(50)  NOT NULL,
    lastname           VARCHAR(50)  NOT NULL,
    email              VARCHAR(120) NOT NULL UNIQUE
        CHECK (email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'),
    phone_num          VARCHAR(14)  NOT NULL UNIQUE
        CHECK (phone_num ~ '^\+234[789][01][0-9]{8}$'),         -- Nigerian mobile, e.g. +2348031234567
    registration_date  DATE         NOT NULL DEFAULT CURRENT_DATE
);

-- Address (rule E2)
--   Customer saves Address (rule 1, 1:N)  -> customer_id FK, NOT NULL
--   Address located_in State (rule 3, N:1) -> state_code FK, NOT NULL
CREATE TABLE address (
    address_id    BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    address_line  VARCHAR(150) NOT NULL,                         -- addressLine: house number and street
    city          VARCHAR(60)  NOT NULL,
    is_default    BOOLEAN      NOT NULL DEFAULT false,
    customer_id   BIGINT       NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    state_code    CHAR(2)      NOT NULL REFERENCES state(state_code),
    UNIQUE (address_id, customer_id)       -- target of the composite FK from orders (rule 10)
);

-- Rule 2: of the addresses a customer saves, at most one is the default.
-- A partial unique index: uniqueness applies only to default addresses.
CREATE UNIQUE INDEX ux_address_one_default_per_customer
    ON address (customer_id) WHERE is_default;

-- Vendor (rule E4)
--   State contains Vendor (rule 3) -> state_code FK
CREATE TABLE vendor (
    vendor_id      BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    business_name  VARCHAR(100) NOT NULL UNIQUE,
    email_address  VARCHAR(120) NOT NULL UNIQUE
        CHECK (email_address ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$'),
    phone_number   VARCHAR(14)  NOT NULL
        CHECK (phone_number ~ '^\+234[789][01][0-9]{8}$'),
    date_joined    DATE         NOT NULL DEFAULT CURRENT_DATE,
    state_code     CHAR(2)      NOT NULL REFERENCES state(state_code)
);

-- Warehouse (rule E7)
--   State contains Warehouse (rule 3) -> state_code FK
CREATE TABLE warehouse (
    warehouse_id    INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    warehouse_code  VARCHAR(10)  NOT NULL UNIQUE,                -- e.g. 'LAG-01'
    warehouse_name  VARCHAR(60)  NOT NULL,
    state_code      CHAR(2)      NOT NULL REFERENCES state(state_code)
);

-- Category (rule E5). The commission rate feeds every payout.
CREATE TABLE category (
    category_id      INT          GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category_name    VARCHAR(60)  NOT NULL UNIQUE,
    commission_rate  NUMERIC(4,2) NOT NULL
        CHECK (commission_rate BETWEEN 0 AND 50)                 -- percent kept by AdaLink
);

-- Product (rule E6): the product's core record.
--   Vendor lists Product (rule 4)        -> vendor_id FK
--   Product belongs_to Category (rule 5) -> category_id FK
--   The multivalued {specification} is stored in MongoDB (products
--   collection, _id = product_id), not here.
CREATE TABLE product (
    product_id    BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sku_code      VARCHAR(30)   NOT NULL UNIQUE,
    product_name  VARCHAR(150)  NOT NULL,
    unit_price    NUMERIC(12,2) NOT NULL CHECK (unit_price > 0), -- current price in Naira
    date_listed   DATE          NOT NULL DEFAULT CURRENT_DATE,
    is_available  BOOLEAN       NOT NULL DEFAULT true,           -- currently available for purchase
    vendor_id     BIGINT        NOT NULL REFERENCES vendor(vendor_id)     ON DELETE RESTRICT,
    category_id   INT           NOT NULL REFERENCES category(category_id) ON DELETE RESTRICT
);

-- Order (rule E8). "order" is a reserved word in SQL, so the table is "orders".
--   Customer places Order (rule 9)        -> customer_id FK
--   Order delivered_to Address (rule 10)  -> address_id FK
--   Rule 10: the address must belong to the customer who placed the order,
--   enforced with a composite foreign key (address_id, customer_id).
CREATE TABLE orders (
    order_id      BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_date    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    order_status  VARCHAR(12)   NOT NULL DEFAULT 'pending'
        CHECK (order_status IN ('pending','paid','shipped','delivered','cancelled','refunded')),
    delivery_fee  NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (delivery_fee >= 0),   -- 0 = free delivery
    total_amount  NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),   -- derived (rule 12)
    customer_id   BIGINT        NOT NULL REFERENCES customer(customer_id) ON DELETE RESTRICT,
    address_id    BIGINT        NOT NULL,
    FOREIGN KEY (address_id, customer_id)
        REFERENCES address (address_id, customer_id) ON DELETE RESTRICT
);

-- Payout (rule E12)
--   Vendor receives Payout (rule 17) -> vendor_id FK
CREATE TABLE payout (
    payout_id          BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    start_date         DATE          NOT NULL,
    end_date           DATE          NOT NULL,
    gross_amount       NUMERIC(14,2) NOT NULL CHECK (gross_amount >= 0),       -- derived (rule 19)
    commission_amount  NUMERIC(14,2) NOT NULL CHECK (commission_amount >= 0),  -- derived (rule 19)
    net_amount         NUMERIC(14,2) NOT NULL,
    payout_status      VARCHAR(10)   NOT NULL DEFAULT 'pending'
        CHECK (payout_status IN ('pending','paid','failed')),
    bank_transfer_ref  VARCHAR(40)   UNIQUE,
    date_paid          TIMESTAMPTZ,
    vendor_id          BIGINT        NOT NULL REFERENCES vendor(vendor_id) ON DELETE RESTRICT,
    CHECK (end_date = start_date + 6),                         -- rule 17: covers one week
    CHECK (net_amount = gross_amount - commission_amount),     -- rule 19
    CHECK (commission_amount <= gross_amount),
    CHECK (payout_status <> 'paid' OR (date_paid IS NOT NULL AND bank_transfer_ref IS NOT NULL)),
    UNIQUE (vendor_id, start_date)                             -- rule 17: one payout per vendor per week
);

-- Payment (rule E9)
--   Order has Payment attempts (rule 13) -> order_id FK
CREATE TABLE payment (
    payment_id         BIGINT        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    payment_method     VARCHAR(16)   NOT NULL
        CHECK (payment_method IN ('card','bank_transfer','ussd','wallet','pay_on_delivery')),
    amount             NUMERIC(14,2) NOT NULL CHECK (amount > 0),
    payment_status     VARCHAR(10)   NOT NULL
        CHECK (payment_status IN ('pending','successful','failed','refunded')),
    payment_reference  VARCHAR(40)   NOT NULL UNIQUE,          -- reference from the payment provider
    date_made          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    date_paid          TIMESTAMPTZ,
    order_id           BIGINT        NOT NULL REFERENCES orders(order_id) ON DELETE RESTRICT,
    CHECK (payment_status <> 'successful' OR date_paid IS NOT NULL),
    CHECK (date_paid IS NULL OR date_paid >= date_made)
);

-- Shipment (rule E10)
--   Order carries Shipment (rule 14, one-to-one, optional on the
--   shipment side) -> order_id FK made UNIQUE: at most one shipment per order
--   Warehouse dispatches Shipment (rule 14, 1:N) -> warehouse_id FK
--   Its tracking events (ShipmentEvent) are stored in MongoDB
--   (shipment_tracking collection, _id = shipment_id). PostgreSQL stays
--   the master for delivery_date, which the order status depends on.
CREATE TABLE shipment (
    shipment_id    BIGINT       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tracking_num   VARCHAR(20)  NOT NULL UNIQUE,
    carrier        VARCHAR(40)  NOT NULL,
    dispatch_date  DATE         NOT NULL,
    delivery_date  DATE,
    order_id       BIGINT       NOT NULL UNIQUE REFERENCES orders(order_id) ON DELETE RESTRICT,
    warehouse_id   INT          NOT NULL REFERENCES warehouse(warehouse_id) ON DELETE RESTRICT,
    CHECK (delivery_date IS NULL OR delivery_date >= dispatch_date)
);


-- =====================================================================
-- PART B. TABLES FROM MANY-TO-MANY RELATIONSHIPS
-- Mapping rule: each many-to-many relationship becomes its own table.
-- Its primary key combines the primary keys of the two entities, and
-- the relationship's own attributes become its columns.
-- (The third many-to-many relationship, Customer reviews Product, is
-- stored in MongoDB: reviews collection.)
-- =====================================================================

-- Warehouse stocks Product (rule 8). Decremented inside checkout.
CREATE TABLE warehouse_stock (
    warehouse_id              INT          NOT NULL REFERENCES warehouse(warehouse_id) ON DELETE RESTRICT,
    product_id                BIGINT       NOT NULL REFERENCES product(product_id)     ON DELETE RESTRICT,
    qty_on_hand               INT          NOT NULL CHECK (qty_on_hand >= 0),      -- never negative
    reorder_level             INT          NOT NULL DEFAULT 10 CHECK (reorder_level >= 0),
    updated_stock_level_date  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (warehouse_id, product_id)
);

-- Order contains Product (rule 11), plus the aggregation:
-- Payout settles the sale (rule 18). "settles" is one-to-many from
-- Payout to this relationship, so payout_id is a foreign key here.
-- It allows NULL: a sale is unpaid until the vendor's weekly payout.
CREATE TABLE order_item (
    order_id          BIGINT        NOT NULL REFERENCES orders(order_id)    ON DELETE CASCADE,
    product_id        BIGINT        NOT NULL REFERENCES product(product_id) ON DELETE RESTRICT,
    quantity_ordered  INT           NOT NULL CHECK (quantity_ordered >= 1),
    unit_price        NUMERIC(12,2) NOT NULL CHECK (unit_price > 0),            -- price actually paid
    commission_rate   NUMERIC(4,2)  NOT NULL CHECK (commission_rate BETWEEN 0 AND 50), -- rate at time of sale
    payout_id         BIGINT        REFERENCES payout(payout_id) ON DELETE RESTRICT,
    PRIMARY KEY (order_id, product_id)    -- rule 11: a product appears at most once in any order
);


-- =====================================================================
-- PART C. TRIGGER: a rule that involves other tables
-- Rule 18: a sale is settled only by a payout to the vendor who sold
-- the product, and only once its order has been delivered. A CHECK
-- constraint sees only the row being saved and a foreign key only checks
-- that a row exists, so this rule is enforced by a trigger.
-- =====================================================================
CREATE FUNCTION check_sale_payout() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.payout_id IS NOT NULL THEN
        IF (SELECT vendor_id FROM payout  WHERE payout_id  = NEW.payout_id)
           IS DISTINCT FROM
           (SELECT vendor_id FROM product WHERE product_id = NEW.product_id) THEN
            RAISE EXCEPTION 'Product % in order % was sold by a different vendor than payout %',
                            NEW.product_id, NEW.order_id, NEW.payout_id
                  USING ERRCODE = 'integrity_constraint_violation';
        END IF;
        IF (SELECT order_status FROM orders WHERE order_id = NEW.order_id) <> 'delivered' THEN
            RAISE EXCEPTION 'Order % is not delivered, so its sales cannot be paid out yet',
                            NEW.order_id
                  USING ERRCODE = 'integrity_constraint_violation';
        END IF;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_sale_payout
    BEFORE INSERT OR UPDATE OF payout_id, product_id ON order_item
    FOR EACH ROW EXECUTE FUNCTION check_sale_payout();


-- =====================================================================
-- Table descriptions, visible in pgAdmin under each table's Properties
-- =====================================================================
COMMENT ON TABLE state           IS 'Entity State: 36 Nigerian states + FCT (rule E3)';
COMMENT ON TABLE customer        IS 'Entity Customer: registered AdaLink shoppers (rule E1)';
COMMENT ON TABLE address         IS 'Entity Address: delivery addresses; at most one default per customer (rules E2, 1, 2)';
COMMENT ON TABLE vendor          IS 'Entity Vendor: businesses selling on AdaLink (rule E4)';
COMMENT ON TABLE warehouse       IS 'Entity Warehouse: AdaLink fulfilment centres (rule E7)';
COMMENT ON TABLE category        IS 'Entity Category: product categories with commission rate (rule E5)';
COMMENT ON TABLE product         IS 'Entity Product: core product record (rule E6); specifications are in MongoDB';
COMMENT ON TABLE warehouse_stock IS 'M:N relationship Warehouse stocks Product (rule 8)';
COMMENT ON TABLE orders          IS 'Entity Order: customer orders (rule E8)';
COMMENT ON TABLE order_item      IS 'M:N relationship Order contains Product; settled by a Payout (rules 11, 18)';
COMMENT ON TABLE payment         IS 'Entity Payment: payment attempts per order (rule E9)';
COMMENT ON TABLE shipment        IS 'Entity Shipment: the one parcel that delivers an order (rule E10); tracking events are in MongoDB';
COMMENT ON TABLE payout          IS 'Entity Payout: weekly vendor payments (rule E12)';

SELECT 'AdaLink PostgreSQL schema created: ' || count(*) || ' tables' AS result
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
