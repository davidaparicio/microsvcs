# order-svc — development Makefile
# Prerequisites:
#   docker compose, go, psql (or use the docker-psql target)
#   go install github.com/golang-migrate/migrate/v4/cmd/migrate@latest

-include .env
export

DATABASE_URL ?= postgres://order_user:order_pass@localhost:5432/order_db?sslmode=disable
MIGRATE       = migrate -path ./migrations -database "$(DATABASE_URL)"

# Number of steps to roll back (default 1).  Override: make migrate-down N=3
N ?= 1

.PHONY: run migrate-up migrate-down migrate-force seed \
        docker-up docker-down docker-psql tools help

## Run the server (requires a running Postgres)
run:
	go run ./cmd/server

## Apply all pending migrations
migrate-up:
	$(MIGRATE) up

## Roll back N steps (default 1).  Example: make migrate-down N=2
migrate-down:
	$(MIGRATE) down $(N)

## Force-set migration version without running SQL (clears dirty state).
## Usage: make migrate-force V=7
migrate-force:
	@test -n "$(V)" || (echo "Usage: make migrate-force V=<version>"; exit 1)
	$(MIGRATE) force $(V)

## Seed the database with test data (run after migrate-up baseline 001-004).
## Requires psql in PATH; alternatively use: make docker-psql
seed:
	psql "$(DATABASE_URL)" -f ./seeds/seed.sql

## Start Postgres in Docker
docker-up:
	docker compose up -d --wait

## Stop and remove Postgres container (data volume preserved)
docker-down:
	docker compose down

## Open a psql shell inside the running container
docker-psql:
	docker compose exec postgres psql -U order_user -d order_db

## Seed via docker exec (no local psql needed)
docker-seed:
	docker compose exec -T postgres psql -U order_user -d order_db \
	    < ./seeds/seed.sql

## Install the golang-migrate CLI
tools:
	go install github.com/golang-migrate/migrate/v4/cmd/migrate@latest

## Show this help
help:
	@grep -E '^##' Makefile | sed 's/## /  /'
