-- Phase 2: DESTRUCTIVE TRANSFORMATION — data loss on rollback.
-- Splitting on the first space is best-effort:
--   "Charlie"       → first_name='Charlie', last_name=NULL
--   "María García"  → first_name='María',   last_name='García'
-- Rollback reconstructs "first last" but loses original fidelity
-- (e.g. "Charlie" round-trips as "Charlie ").

-- Step 1: add new columns (nullable while we back-fill)
ALTER TABLE customers
    ADD COLUMN first_name VARCHAR(127),
    ADD COLUMN last_name  VARCHAR(127);

-- Step 2: best-effort split on the first space
UPDATE customers
SET    first_name = SPLIT_PART(name, ' ', 1),
       last_name  = NULLIF(TRIM(SUBSTRING(name FROM POSITION(' ' IN name) + 1)), '');

-- Step 3: enforce NOT NULL on first_name only; last_name stays nullable
ALTER TABLE customers
    ALTER COLUMN first_name SET NOT NULL;

-- Step 4: drop the original column — DESTRUCTIVE, triggers data loss on rollback
ALTER TABLE customers
    DROP COLUMN name;
