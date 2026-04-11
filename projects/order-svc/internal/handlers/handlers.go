package handlers

import (
	"errors"
	"regexp"
	"strconv"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/labstack/echo/v4"
)

// Handler holds shared dependencies for all route handlers.
type Handler struct {
	db *pgxpool.Pool
}

// New returns a Handler wired to the given connection pool.
func New(db *pgxpool.Pool) *Handler {
	return &Handler{db: db}
}

// isNotFound checks for pgx.ErrNoRows using errors.Is for wrapped errors (S10).
func isNotFound(err error) bool {
	return errors.Is(err, pgx.ErrNoRows)
}

// parsePagination extracts limit and offset query params with safe defaults (S7).
func parsePagination(c echo.Context) (limit, offset int) {
	limit = 20
	offset = 0
	if v := c.QueryParam("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 100 {
			limit = n
		}
	}
	if v := c.QueryParam("offset"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n >= 0 {
			offset = n
		}
	}
	return
}

var emailRegexp = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

// isValidEmail performs basic email format validation (S3).
func isValidEmail(email string) bool {
	return emailRegexp.MatchString(email)
}
