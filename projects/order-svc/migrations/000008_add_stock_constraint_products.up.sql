-- Phase 2: INTENTIONALLY FAILS with seed data.
-- PROD-003 has stock = -5.  PostgreSQL scans all rows when adding a CHECK
-- constraint and raises:
--   ERROR: check constraint "chk_stock_non_negative" of relation "products"
--          is violated by some row
--
-- Recovery steps:
--   1.  make migrate-force V=7   (clear the "dirty" flag)
--   2.  UPDATE products SET stock = 0 WHERE stock < 0;
--   3.  make migrate-up

ALTER TABLE products
    ADD CONSTRAINT chk_stock_non_negative CHECK (stock >= 0);
