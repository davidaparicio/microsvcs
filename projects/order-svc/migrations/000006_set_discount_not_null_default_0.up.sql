-- Phase 2: RISKY — backfill NULLs then tighten constraint.
-- If this migration fails mid-way the table is left in dirty state.
-- Rollback challenge: easy to DROP NOT NULL, but data semantics change.

-- Step 1: fill any NULLs so the NOT NULL constraint can be applied
UPDATE order_items
SET    discount = 0
WHERE  discount IS NULL;

-- Step 2: enforce NOT NULL and add a default for future inserts
ALTER TABLE order_items
    ALTER COLUMN discount SET NOT NULL,
    ALTER COLUMN discount SET DEFAULT 0;
