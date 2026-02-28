-- Removing the NOT NULL + default is safe; existing rows keep their 0 values.
ALTER TABLE order_items
    ALTER COLUMN discount DROP NOT NULL,
    ALTER COLUMN discount DROP DEFAULT;
