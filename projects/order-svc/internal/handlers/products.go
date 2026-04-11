package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/labstack/echo/v4"
)

// Product maps to the products table.
type Product struct {
	ID        int       `json:"id"`
	SKU       string    `json:"sku"`
	Name      string    `json:"name"`
	Price     float64   `json:"price"`
	Stock     int       `json:"stock"`
	CreatedAt time.Time `json:"created_at"`
}

func (h *Handler) ListProducts(c echo.Context) error {
	limit, offset := parsePagination(c)
	rows, err := h.db.Query(c.Request().Context(),
		`SELECT id, sku, name, price, stock, created_at FROM products ORDER BY id LIMIT $1 OFFSET $2`,
		limit, offset)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to list products"})
	}
	defer rows.Close()

	products := []Product{}
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.SKU, &p.Name, &p.Price, &p.Stock, &p.CreatedAt); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to scan product"})
		}
		products = append(products, p)
	}
	if err := rows.Err(); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to iterate products"})
	}
	return c.JSON(http.StatusOK, products)
}

func (h *Handler) GetProduct(c echo.Context) error {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id"})
	}

	var p Product
	err = h.db.QueryRow(c.Request().Context(),
		`SELECT id, sku, name, price, stock, created_at FROM products WHERE id = $1`, id).
		Scan(&p.ID, &p.SKU, &p.Name, &p.Price, &p.Stock, &p.CreatedAt)
	if err != nil {
		if isNotFound(err) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "product not found"})
		}
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get product"})
	}
	return c.JSON(http.StatusOK, p)
}

func (h *Handler) CreateProduct(c echo.Context) error {
	var body struct {
		SKU   string  `json:"sku"`
		Name  string  `json:"name"`
		Price float64 `json:"price"`
		Stock int     `json:"stock"`
	}
	if err := c.Bind(&body); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
	}
	if body.SKU == "" || body.Name == "" {
		return c.JSON(http.StatusUnprocessableEntity, map[string]string{"error": "sku and name required"})
	}
	if body.Price < 0 {
		return c.JSON(http.StatusUnprocessableEntity, map[string]string{"error": "price must not be negative"})
	}
	if body.Stock < 0 {
		return c.JSON(http.StatusUnprocessableEntity, map[string]string{"error": "stock must not be negative"})
	}

	var p Product
	err := h.db.QueryRow(c.Request().Context(), `
		INSERT INTO products (sku, name, price, stock) VALUES ($1, $2, $3, $4)
		RETURNING id, sku, name, price, stock, created_at`,
		body.SKU, body.Name, body.Price, body.Stock).
		Scan(&p.ID, &p.SKU, &p.Name, &p.Price, &p.Stock, &p.CreatedAt)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to create product"})
	}
	return c.JSON(http.StatusCreated, p)
}
