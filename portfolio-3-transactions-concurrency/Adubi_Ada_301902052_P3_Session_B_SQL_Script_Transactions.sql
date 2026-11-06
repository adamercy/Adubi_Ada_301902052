-- Session B Script

-- [E3-2] Session B: read the same stock
SELECT qty_on_hand AS lagos_stock_seen_by_B FROM warehouse_stock
WHERE warehouse_id = 2 AND product_id = 777;
-- Expected: 8. B cannot see A's uncommitted change (no dirty read).

-- [E3-4] Session B: read the same stock again
SELECT qty_on_hand AS lagos_stock_seen_by_B FROM warehouse_stock
WHERE warehouse_id = 2 AND product_id = 777;
-- Expected: 7. Once A commits, B sees the change.

-- [E4-2] Session B: second customer buys the same phone
UPDATE warehouse_stock SET qty_on_hand = qty_on_hand - 1 WHERE warehouse_id = 2 
AND product_id = 777;
SELECT qty_on_hand AS lagos_stock_seen_by_B FROM warehouse_stock
WHERE warehouse_id = 2 AND product_id = 777;
-- Expected: this WAITS (spinner). A holds a lock on the row.
