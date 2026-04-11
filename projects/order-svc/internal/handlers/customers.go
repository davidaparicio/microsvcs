package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/labstack/echo/v4"
)

// Customer maps to the customers table (baseline schema).
type Customer struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	Email     string    `json:"email"`
	CreatedAt time.Time `json:"created_at"`
}

func (h *Handler) ListCustomers(c echo.Context) error {
	limit, offset := parsePagination(c)
	rows, err := h.db.Query(c.Request().Context(),
		`SELECT id, name, email, created_at FROM customers ORDER BY id LIMIT $1 OFFSET $2`,
		limit, offset)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to list customers"})
	}
	defer rows.Close()

	customers := []Customer{}
	for rows.Next() {
		var cu Customer
		if err := rows.Scan(&cu.ID, &cu.Name, &cu.Email, &cu.CreatedAt); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to scan customer"})
		}
		customers = append(customers, cu)
	}
	if err := rows.Err(); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to iterate customers"})
	}
	return c.JSON(http.StatusOK, customers)
}

func (h *Handler) GetCustomer(c echo.Context) error {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id"})
	}

	var cu Customer
	err = h.db.QueryRow(c.Request().Context(),
		`SELECT id, name, email, created_at FROM customers WHERE id = $1`, id).
		Scan(&cu.ID, &cu.Name, &cu.Email, &cu.CreatedAt)
	if err != nil {
		if isNotFound(err) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "customer not found"})
		}
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get customer"})
	}
	return c.JSON(http.StatusOK, cu)
}

func (h *Handler) CreateCustomer(c echo.Context) error {
	var body struct {
		Name  string `json:"name"`
		Email string `json:"email"`
	}
	if err := c.Bind(&body); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
	}
	if body.Name == "" || body.Email == "" {
		return c.JSON(http.StatusUnprocessableEntity, map[string]string{"error": "name and email required"})
	}
	if !isValidEmail(body.Email) {
		return c.JSON(http.StatusUnprocessableEntity, map[string]string{"error": "invalid email format"})
	}

	var cu Customer
	err := h.db.QueryRow(c.Request().Context(), `
		INSERT INTO customers (name, email) VALUES ($1, $2)
		RETURNING id, name, email, created_at`,
		body.Name, body.Email).
		Scan(&cu.ID, &cu.Name, &cu.Email, &cu.CreatedAt)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to create customer"})
	}
	return c.JSON(http.StatusCreated, cu)
}
