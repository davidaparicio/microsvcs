-- Rollback is trivial — dropping a constraint never touches data.
-- But the negative-stock row is still there; re-applying 008 will fail again
-- unless the data is cleaned first.
ALTER TABLE products
    DROP CONSTRAINT IF EXISTS chk_stock_non_negative;
