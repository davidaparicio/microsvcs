package handlers

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// OrderItem maps to order_items.
// IMPORTANT: references column "unit_price" — broken after migration 007 renames it to "price".
// To fix post-007: rename UnitPrice→Price here and update all SQL below.
type OrderItem struct {
	ID        int     `json:"id"`
	ProductID int     `json:"product_id"`
	Quantity  int     `json:"quantity"`
	UnitPrice float64 `json:"unit_price"` // column renamed to "price" in migration 007
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

func (h *Handler) ListOrders(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.Query(r.Context(),
		`SELECT id, customer_id, status, total, created_at FROM orders ORDER BY id`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	orders := []Order{}
	for rows.Next() {
		var o Order
		if err := rows.Scan(&o.ID, &o.CustomerID, &o.Status, &o.Total, &o.CreatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		orders = append(orders, o)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, orders)
}

func (h *Handler) GetOrder(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}

	var o Order
	err = h.db.QueryRow(r.Context(),
		`SELECT id, customer_id, status, total, created_at FROM orders WHERE id = $1`, id).
		Scan(&o.ID, &o.CustomerID, &o.Status, &o.Total, &o.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeError(w, http.StatusNotFound, "order not found")
			return
		}
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	// Fetch items — references unit_price; breaks after migration 007 renames it to "price"
	irows, err := h.db.Query(r.Context(), `
		SELECT id, product_id, quantity, unit_price
		FROM order_items WHERE order_id = $1 ORDER BY id`, id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer irows.Close()

	o.Items = []OrderItem{}
	for irows.Next() {
		var oi OrderItem
		if err := irows.Scan(&oi.ID, &oi.ProductID, &oi.Quantity, &oi.UnitPrice); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		o.Items = append(o.Items, oi)
	}
	writeJSON(w, http.StatusOK, o)
}

func (h *Handler) CreateOrder(w http.ResponseWriter, r *http.Request) {
	var body struct {
		CustomerID int `json:"customer_id"`
		Items      []struct {
			ProductID int `json:"product_id"`
			Quantity  int `json:"quantity"`
		} `json:"items"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if body.CustomerID == 0 || len(body.Items) == 0 {
		writeError(w, http.StatusUnprocessableEntity, "customer_id and items required")
		return
	}

	tx, err := h.db.Begin(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer tx.Rollback(r.Context()) //nolint:errcheck

	var o Order
	err = tx.QueryRow(r.Context(), `
		INSERT INTO orders (customer_id, status, total)
		VALUES ($1, 'pending', 0)
		RETURNING id, customer_id, status, total, created_at`,
		body.CustomerID).
		Scan(&o.ID, &o.CustomerID, &o.Status, &o.Total, &o.CreatedAt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}

	var total float64
	for _, item := range body.Items {
		// Snapshot the current product price into the order item
		var unitPrice float64
		err = tx.QueryRow(r.Context(),
			`SELECT price FROM products WHERE id = $1`, item.ProductID).
			Scan(&unitPrice)
		if err != nil {
			if err == pgx.ErrNoRows {
				writeError(w, http.StatusUnprocessableEntity,
					fmt.Sprintf("product %d not found", item.ProductID))
				return
			}
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}

		// Insert order item — references unit_price; breaks after migration 007
		var oi OrderItem
		err = tx.QueryRow(r.Context(), `
			INSERT INTO order_items (order_id, product_id, quantity, unit_price)
			VALUES ($1, $2, $3, $4)
			RETURNING id, product_id, quantity, unit_price`,
			o.ID, item.ProductID, item.Quantity, unitPrice).
			Scan(&oi.ID, &oi.ProductID, &oi.Quantity, &oi.UnitPrice)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		o.Items = append(o.Items, oi)
		total += unitPrice * float64(item.Quantity)
	}

	if _, err = tx.Exec(r.Context(),
		`UPDATE orders SET total = $1 WHERE id = $2`, total, o.ID); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	o.Total = total

	if err := tx.Commit(r.Context()); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, o)
}
