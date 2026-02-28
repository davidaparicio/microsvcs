# Order Management Microservice — PoC Walkthrough

A hands-on demonstration of sequential PostgreSQL migrations, intentional failure
scenarios, and rollback mechanics using **golang-migrate**.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| `docker` + `docker compose` | Run PostgreSQL |
| `go 1.22+` | Build and run the service |
| `psql` *(optional)* | Seed directly; `make docker-seed` works without it |
| `migrate` CLI | `make tools` installs it via `go install` |

```bash
# One-time: install the migrate CLI
make tools

# Copy and review environment variables
cp .env.example .env
```

---

## Phase 1 — Stable Baseline (migrations 001–004)

Bring up Postgres, apply the four baseline migrations, seed realistic data, and
verify the service is healthy.

```bash
make docker-up       # starts postgres:16-alpine, waits for healthcheck
make migrate-up      # applies 001–004
make docker-seed     # loads seeds/seed.sql via docker exec (no local psql needed)
make run             # server listens on :8080
```

### Smoke-test the API

```bash
# List customers (5 rows, including "Charlie" with no last name)
curl -s http://localhost:8080/api/v1/customers | jq .

# List products (PROD-003 has stock = -5 — dirty data)
curl -s http://localhost:8080/api/v1/products | jq .

# Create a new order
curl -s -X POST http://localhost:8080/api/v1/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":1,"items":[{"product_id":1,"quantity":2}]}' | jq .

# Retrieve order with items
curl -s http://localhost:8080/api/v1/orders/1 | jq .
```

Expected: all requests return `200`/`201`; `order_items` rows have a `unit_price`
field (column name as-of migration 004).

---

## Phase 2 — Apply Risky Migrations One by One (005–009)

### Migration 005 — Add nullable `discount` column

```bash
make migrate-up
```

**What happens:** `ALTER TABLE order_items ADD COLUMN discount NUMERIC(5,2)` —
no rows are touched, no constraints added. Safe to apply at any time.

```bash
# Verify
psql "$DATABASE_URL" -c "\d order_items"
```

**Rollback:** `make migrate-down` — trivial `DROP COLUMN`.

---

### Migration 006 — Set `discount NOT NULL DEFAULT 0`

```bash
make migrate-up
```

**What happens:**
1. `UPDATE order_items SET discount = 0 WHERE discount IS NULL` — backfills existing rows.
2. `ALTER COLUMN discount SET NOT NULL, SET DEFAULT 0` — tightens the constraint.

```bash
# Verify no NULLs remain
psql "$DATABASE_URL" -c "SELECT count(*) FROM order_items WHERE discount IS NULL;"
# → 0
```

**Rollback challenge:** `DROP NOT NULL` is easy in SQL, but the semantics shift —
rows that were explicitly set to `0` are now indistinguishable from backfilled ones.

---

### Migration 007 — Rename `unit_price` to `price`

```bash
make migrate-up
```

**What happens:** `ALTER TABLE order_items RENAME COLUMN unit_price TO price` —
one DDL statement, instant in Postgres.

**App impact:** the running server still references `unit_price` in every SQL
query inside `orders.go`. Hit any order endpoint now:

```bash
curl -s http://localhost:8080/api/v1/orders/1 | jq .
# → {"error":"ERROR: column \"unit_price\" does not exist (SQLSTATE 42703)"}
```

The API is broken. Blue/green deployment or a view alias (`unit_price` pointing
to `price`) is the production-safe approach.

**Rollback:**

```bash
make migrate-down    # renames price → unit_price; app recovers immediately
```

Rollback is trivial in SQL — but any code that was *already updated* to use
`price` now breaks in the other direction.

---

### Migration 008 — Add `CHECK (stock >= 0)` constraint

> **This migration intentionally fails.**

```bash
make migrate-up
```

**Expected error:**

```
error: migration failed: pq: check constraint "chk_stock_non_negative"
       of relation "products" is violated by some row
       (details: dirty)
```

PostgreSQL scans every row when adding a `CHECK` constraint. `PROD-003` has
`stock = -5`, which violates the new constraint before it can be committed.

golang-migrate marks the database as **dirty** (version = 8, dirty = true).
Any further `migrate up` or `migrate down` will refuse to run until the dirty
state is resolved.

---

## Phase 3 — Observe and Diagnose the Failure

```bash
# Confirm dirty state
psql "$DATABASE_URL" -c "SELECT * FROM schema_migrations;"
# → version=8, dirty=true

# Identify the offending row
psql "$DATABASE_URL" -c "SELECT id, sku, name, stock FROM products WHERE stock < 0;"
# → PROD-003 | Gadget X | -5
```

---

## Phase 4 — Rollback and Recovery

Two paths are available.

### Option A — Fix the data and retry

```bash
# 1. Clear the dirty flag without running any SQL
make migrate-force V=7

# 2. Fix the dirty data
psql "$DATABASE_URL" -c "UPDATE products SET stock = 0 WHERE stock < 0;"

# 3. Re-apply migration 008
make migrate-up
```

Migration 008 now succeeds. The constraint is in place.

### Option B — Roll back to 007 and leave the constraint out

```bash
# Dirty flag must be cleared first
make migrate-force V=7

# Nothing to undo for 008 (it never committed), so we are back at 007
# Confirm
psql "$DATABASE_URL" -c "SELECT * FROM schema_migrations;"
# → version=7, dirty=false
```

---

### Migration 009 — Split `name` into `first_name` / `last_name`

*(Assumes Option A was taken and migration 008 succeeded.)*

```bash
make migrate-up
```

**What happens:**

1. `ADD COLUMN first_name`, `ADD COLUMN last_name` (nullable).
2. `UPDATE` splits on the first space — best-effort.
3. `ALTER COLUMN first_name SET NOT NULL`.
4. `DROP COLUMN name` — **destructive**.

```bash
# Inspect the result
psql "$DATABASE_URL" -c "SELECT id, first_name, last_name, email FROM customers;"
```

| id | first_name | last_name | email |
|----|-----------|-----------|-------|
| 1 | Alice | Johnson | alice@example.com |
| 2 | Bob | Smith | bob@example.com |
| 3 | Charlie | *(NULL)* | charlie@example.com |
| 4 | María | García | maria@example.com |
| 5 | Test | User | test@example.com |

`Charlie` has no last name — `last_name` is `NULL`. This is valid (the column
allows `NULL`) but demonstrates how single-token names survive imperfectly.

**Rollback:**

```bash
make migrate-down
```

The down migration reconstructs `name` via `TRIM(CONCAT(first_name, ' ', last_name))`.

```bash
psql "$DATABASE_URL" -c "SELECT id, name FROM customers;"
```

| id | name |
|----|------|
| 3 | Charlie *(no trailing space — TRIM handles it)* |
| 4 | María García |

Original fidelity is **not guaranteed**. A name like `"O'Brien, Mary-Jo"` (no
space) would have had `last_name = NULL` and round-trips to `"O'Brien, Mary-Jo"`
correctly — but `"Jean  Claude"` (double space) becomes `"Jean Claude"`.

---

## Phase 5 — What Survived, What Didn't

| Migration | Rollback result | Data integrity |
|-----------|----------------|---------------|
| 005 add nullable `discount` | Clean `DROP COLUMN` | No data lost |
| 006 `NOT NULL DEFAULT 0` | `DROP NOT NULL` — easy | `0` values indistinguishable from backfill |
| 007 rename `unit_price → price` | Rename back — SQL trivial | No data lost, but app code is now out of sync in both directions |
| 008 `CHECK stock >= 0` | Dropped constraint, dirty row survives | No data lost; negative stock still present unless cleaned |
| 009 split `name → first/last` | Reconstructed from parts | Single-space fidelity OK; multi-space names lose extra whitespace |

### Key takeaways

- **Nullable-first** is always safer than adding `NOT NULL` directly.
- **Column renames** have zero SQL cost but a high operational cost — blue/green
  or a compatibility view is essential in production.
- **`CHECK` constraints on existing tables** require clean data *before* the
  migration runs, not after.
- **Destructive transformations** (`DROP COLUMN`) make rollback a data
  reconstruction exercise, not a pure schema revert.
- **`migrate force`** is a scalpel, not a sledgehammer — it clears the dirty
  flag so you can retry or roll back, but it does not fix the underlying data.
