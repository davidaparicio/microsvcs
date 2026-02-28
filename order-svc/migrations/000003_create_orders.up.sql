-- Phase 1: stable baseline
CREATE TYPE order_status AS ENUM (
    'pending',
    'confirmed',
    'shipped',
    'delivered',
    'cancelled'
);

CREATE TABLE orders (
    id          SERIAL        PRIMARY KEY,
    customer_id INTEGER       NOT NULL REFERENCES customers(id),
    status      order_status  NOT NULL DEFAULT 'pending',
    total       NUMERIC(10,2) NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
