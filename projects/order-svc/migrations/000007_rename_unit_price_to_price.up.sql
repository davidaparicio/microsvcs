-- Phase 2: BREAKS running app instances.
-- Any code still referencing "unit_price" will get: column "unit_price" does not exist.
-- Blue/green deployment or a view alias is needed to roll this out safely.
-- Rollback: trivial SQL, but in-flight traffic will have already crashed.

ALTER TABLE order_items
    RENAME COLUMN unit_price TO price;
