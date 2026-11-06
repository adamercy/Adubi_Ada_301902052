-- Session A Script
-- [SETUP]: start with 10 phones in each warehouse
UPDATE warehouse_stock SET qty_on_hand = 10 WHERE warehouse_id IN (2, 5) AND product_id = 777;

SELECT warehouse_id, qty_on_hand FROM warehouse_stock
WHERE product_id = 777 ORDER BY warehouse_id;
-- Expected: Lagos (2) = 10, Kano (5) = 10

-- [E1-1] Session A: move 2 phones from Lagos to Kano, commit, then check
BEGIN;
UPDATE warehouse_stock SET qty_on_hand = qty_on_hand - 2 WHERE warehouse_id = 2 AND product_id = 777;
UPDATE warehouse_stock SET qty_on_hand = qty_on_hand + 2 WHERE warehouse_id = 5 AND product_id = 777;
COMMIT;

SELECT warehouse_id, qty_on_hand FROM warehouse_stock
WHERE product_id = 777 ORDER BY warehouse_id;
-- Expected: Lagos = 8, Kano = 12. The change is saved permanently.

-- [E2-1] Session A: start moving 5 phones from Lagos to Kano (do not commit)
BEGIN;
UPDATE warehouse_stock SET qty_on_hand = qty_on_hand - 5 WHERE warehouse_id = 2 
AND product_id = 777; -- UPDATE 1
UPDATE warehouse_stock SET qty_on_hand = qty_on_hand + 5 WHERE warehouse_id = 5 
AND product_id = 777; -- UPDATE 2
SELECT warehouse_id, qty_on_hand FROM warehouse_stock
WHERE product_id = 777 ORDER BY warehouse_id; -- SELECT to CONFIRM operation

-- [E2-2] Session A: cancel the move, then check
ROLLBACK;
SELECT warehouse_id, qty_on_hand FROM warehouse_stock
WHERE product_id = 777 ORDER BY warehouse_id;
-- Expected: Lagos = 8, Kano = 12 again. Both updates were undone.

-- [E3-1] Session A: sell 1 phone in Lagos (do not commit)
BEGIN;
UPDATE warehouse_stock SET qty_on_hand = qty_on_hand - 1 WHERE warehouse_id = 2 AND product_id = 777;
SELECT qty_on_hand AS lagos_stock_seen_by_A FROM warehouse_stock
WHERE warehouse_id = 2 AND product_id = 777;
-- Expected: 7. A sees its own change.

-- [E3-3] Session A: commit the sale
COMMIT;

-- [E4-1] Session A: first customer buys a phone (do not commit)
BEGIN;
UPDATE warehouse_stock SET qty_on_hand = qty_on_hand - 1 WHERE warehouse_id = 2 
AND product_id = 777;
SELECT qty_on_hand AS lagos_stock_seen_by_A FROM warehouse_stock
WHERE warehouse_id = 2 AND product_id = 777;
-- Expected: 6

-- [E4-3] Session A: commit the first sale
COMMIT;
-- Now look at Session B: its update finishes and shows 5.
-- Both sales were counted (7 - 1 - 1 = 5), so no update was lost.
