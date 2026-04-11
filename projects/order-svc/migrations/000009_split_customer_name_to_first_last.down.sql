-- Rolling back re-creates "name" by concatenating first+last.
-- Data fidelity is NOT preserved:
--   Original "Charlie"    stored as first_name='Charlie', last_name=NULL
--   Reconstructed name  = 'Charlie'  (trailing space trimmed — acceptable)
--   Original "María García" → 'María García' (round-trips correctly)
--
-- Any customer whose original name had more than one space loses that info.

ALTER TABLE customers
    ADD COLUMN name VARCHAR(255);

UPDATE customers
SET    name = TRIM(CONCAT(first_name, ' ', COALESCE(last_name, '')));

ALTER TABLE customers
    ALTER COLUMN name SET NOT NULL;

ALTER TABLE customers
    DROP COLUMN first_name,
    DROP COLUMN last_name;
