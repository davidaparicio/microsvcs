-- Phase 1: stable baseline
CREATE TABLE products (
    id         SERIAL          PRIMARY KEY,
    sku        VARCHAR(100)    UNIQUE NOT NULL,
    name       VARCHAR(255)    NOT NULL,
    price      NUMERIC(10, 2)  NOT NULL CHECK (price >= 0),
    stock      INTEGER         NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);
