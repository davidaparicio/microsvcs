-- Rename back — harmless in SQL, but any code updated for "price" now breaks again.
ALTER TABLE order_items
    RENAME COLUMN price TO unit_price;
