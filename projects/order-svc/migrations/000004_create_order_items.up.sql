-- Phase 1: stable baseline — PoC is working here
CREATE TABLE order_items (
    id         SERIAL         PRIMARY KEY,
    order_id   INTEGER        NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id INTEGER        NOT NULL REFERENCES products(id),
    quantity   INTEGER        NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);
