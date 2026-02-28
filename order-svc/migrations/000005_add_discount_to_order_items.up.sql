-- Phase 2: nullable first — safe to apply on existing data, no rows touched.
-- Rollback: simply drop the column.
ALTER TABLE order_items
    ADD COLUMN discount NUMERIC(5, 2);
