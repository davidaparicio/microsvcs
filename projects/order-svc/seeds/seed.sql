-- =============================================================================
-- Seed data for order-svc PoC
-- Run AFTER migrations 001-004 (baseline schema).
--
-- Intentional dirty data:
--   PROD-003  stock = -5   → blocks migration 008 (CHECK stock >= 0)
--   "Charlie" single token → last_name = NULL after migration 009 (OK, nullable)
--   order_5   no items     → valid edge-case for cancelled orders
-- =============================================================================

-- -----------------------------------------------------------------------------
-- customers
-- -----------------------------------------------------------------------------
INSERT INTO customers (name, email) VALUES
    ('Alice Johnson', 'alice@example.com'),   -- normal: first + last
    ('Bob Smith',     'bob@example.com'),     -- normal: first + last
    ('Charlie',       'charlie@example.com'), -- single token: last_name=NULL post-009
    ('María García',  'maria@example.com'),   -- unicode: splits correctly
    ('Test User',     'test@example.com');    -- used for cancelled order

-- -----------------------------------------------------------------------------
-- products  (DIRTY: PROD-003 has stock = -5 → breaks migration 008)
-- -----------------------------------------------------------------------------
INSERT INTO products (sku, name, price, stock) VALUES
    ('PROD-001', 'Widget A',      9.99,  100),
    ('PROD-002', 'Widget B',     24.99,   50),
    ('PROD-003', 'Gadget X',    149.99,   -5),  -- DIRTY: negative stock
    ('PROD-004', 'Gadget Y',    299.99,    0),
    ('PROD-005', 'Doohickey Z',   4.99,  200);

-- -----------------------------------------------------------------------------
-- orders
-- -----------------------------------------------------------------------------
INSERT INTO orders (customer_id, status, total) VALUES
    (1, 'confirmed',  54.96),  -- Alice
    (2, 'pending',   149.99),  -- Bob
    (3, 'shipped',   299.99),  -- Charlie
    (4, 'delivered',  14.97),  -- María
    (5, 'cancelled',   0.00);  -- Test User — no items (edge case)

-- -----------------------------------------------------------------------------
-- order_items  (column is "unit_price" until migration 007 renames it to "price")
-- -----------------------------------------------------------------------------
INSERT INTO order_items (order_id, product_id, quantity, unit_price) VALUES
    (1, 1, 3,   9.99),   -- 3 × Widget A  = 29.97
    (1, 2, 1,  24.99),   -- 1 × Widget B  = 24.99  → order 1 total = 54.96 ✓
    (2, 3, 1, 149.99),   -- 1 × Gadget X  = 149.99 → order 2 total = 149.99 ✓
    (3, 4, 1, 299.99),   -- 1 × Gadget Y  = 299.99 → order 3 total = 299.99 ✓
    (4, 5, 3,   4.99);   -- 3 × Doohickey = 14.97  → order 4 total = 14.97 ✓
-- order 5 (cancelled) intentionally has no items
