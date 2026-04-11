package handlers

import (
	"fmt"
	"math"
	"net/http"
	"strconv"
	"time"

	"github.com/labstack/echo/v4"
)

// OrderItem maps to order_items after migration 007 (unit_price renamed to price).
type OrderItem struct {
	ID        int     `json:"id"`
	ProductID int     `json:"product_id"`
	Quantity  int     `json:"quantity"`
	Price     float64 `json:"price"`
}

// Order maps to the orders table.
type Order struct {
	ID         int         `json:"id"`
	CustomerID int         `json:"customer_id"`
	Status     string      `json:"status"`
	Total      float64     `json:"total"`
	CreatedAt  time.Time   `json:"created_at"`
	Items      []OrderItem `json:"items,omitempty"`
}

func (h *Handler) ListOrders(c echo.Context) error {
	limit, offset := parsePagination(c)
	rows, err := h.db.Query(c.Request().Context(),
		`SELECT id, customer_id, status, total, created_at FROM orders ORDER BY id LIMIT $1 OFFSET $2`,
		limit, offset)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to list orders"})
	}
	defer rows.Close()

	orders := []Order{}
	for rows.Next() {
		var o Order
		if err := rows.Scan(&o.ID, &o.CustomerID, &o.Status, &o.Total, &o.CreatedAt); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to scan order"})
		}
		orders = append(orders, o)
	}
	if err := rows.Err(); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to iterate orders"})
	}
	return c.JSON(http.StatusOK, orders)
}

func (h *Handler) GetOrder(c echo.Context) error {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid id"})
	}

	var o Order
	err = h.db.QueryRow(c.Request().Context(),
		`SELECT id, customer_id, status, total, created_at FROM orders WHERE id = $1`, id).
		Scan(&o.ID, &o.CustomerID, &o.Status, &o.Total, &o.CreatedAt)
	if err != nil {
		if isNotFound(err) {
			return c.JSON(http.StatusNotFound, map[string]string{"error": "order not found"})
		}
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to get order"})
	}

	// Fetch items — uses "price" column (post migration 007)
	irows, err := h.db.Query(c.Request().Context(), `
		SELECT id, product_id, quantity, price
		FROM order_items WHERE order_id = $1 ORDER BY id`, id)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to fetch order items"})
	}
	defer irows.Close()

	o.Items = []OrderItem{}
	for irows.Next() {
		var oi OrderItem
		if err := irows.Scan(&oi.ID, &oi.ProductID, &oi.Quantity, &oi.Price); err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to scan order item"})
		}
		o.Items = append(o.Items, oi)
	}
	return c.JSON(http.StatusOK, o)
}

func (h *Handler) CreateOrder(c echo.Context) error {
	var body struct {
		CustomerID int `json:"customer_id"`
		Items      []struct {
			ProductID int `json:"product_id"`
			Quantity  int `json:"quantity"`
		} `json:"items"`
	}
	if err := c.Bind(&body); err != nil {
		return c.JSON(http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
	}
	if body.CustomerID == 0 || len(body.Items) == 0 {
		return c.JSON(http.StatusUnprocessableEntity, map[string]string{"error": "customer_id and items required"})
	}
	for _, item := range body.Items {
		if item.Quantity <= 0 {
			return c.JSON(http.StatusUnprocessableEntity, map[string]string{"error": "quantity must be positive"})
		}
	}

	ctx := c.Request().Context()
	tx, err := h.db.Begin(ctx)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to begin transaction"})
	}
	defer tx.Rollback(ctx) //nolint:errcheck

	var o Order
	err = tx.QueryRow(ctx, `
		INSERT INTO orders (customer_id, status, total)
		VALUES ($1, 'pending', 0)
		RETURNING id, customer_id, status, total, created_at`,
		body.CustomerID).
		Scan(&o.ID, &o.CustomerID, &o.Status, &o.Total, &o.CreatedAt)
	if err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to create order"})
	}

	var total float64
	for _, item := range body.Items {
		// Snapshot the current product price into the order item
		var unitPrice float64
		err = tx.QueryRow(ctx,
			`SELECT price FROM products WHERE id = $1`, item.ProductID).
			Scan(&unitPrice)
		if err != nil {
			if isNotFound(err) {
				return c.JSON(http.StatusUnprocessableEntity, map[string]string{
					"error": fmt.Sprintf("product %d not found", item.ProductID),
				})
			}
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to fetch product price"})
		}

		// Insert order item — uses "price" column (post migration 007)
		var oi OrderItem
		err = tx.QueryRow(ctx, `
			INSERT INTO order_items (order_id, product_id, quantity, price)
			VALUES ($1, $2, $3, $4)
			RETURNING id, product_id, quantity, price`,
			o.ID, item.ProductID, item.Quantity, unitPrice).
			Scan(&oi.ID, &oi.ProductID, &oi.Quantity, &oi.Price)
		if err != nil {
			return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to create order item"})
		}
		o.Items = append(o.Items, oi)
		// S6: round each line-item subtotal to avoid float64 accumulation errors
		total += math.Round(unitPrice*float64(item.Quantity)*100) / 100
	}

	// S9: explicitly set updated_at on total update
	if _, err = tx.Exec(ctx,
		`UPDATE orders SET total = $1, updated_at = NOW() WHERE id = $2`, total, o.ID); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to update order total"})
	}
	o.Total = total

	if err := tx.Commit(ctx); err != nil {
		return c.JSON(http.StatusInternalServerError, map[string]string{"error": "failed to commit order"})
	}
	return c.JSON(http.StatusCreated, o)
}
