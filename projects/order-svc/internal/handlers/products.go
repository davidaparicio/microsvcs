package handlers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// Product maps to the products table.
// After migration 008 a CHECK(stock >= 0) constraint is added.
type Product struct {
	ID        int       `json:"id"`
	SKU       string    `json:"sku"`
	Name      string    `json:"name"`
	Price     float64   `json:"price"`
	Stock     int       `json:"stock"`
	CreatedAt time.Time `json:"created_at"`
}

func (h *Handler) ListProducts(w http.ResponseWriter, r *http.Request) {
	rows, err := h.db.Query(r.Context(),
		`SELECT id, sku, name, price, stock, created_at FROM products ORDER BY id`)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	defer rows.Close()

	products := []Product{}
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.SKU, &p.Name, &p.Price, &p.Stock, &p.CreatedAt); err != nil {
			writeError(w, http.StatusInternalServerError, err.Error())
			return
		}
		products = append(products, p)
	}
	if err := rows.Err(); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, products)
}

func (h *Handler) GetProduct(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.Atoi(chi.URLParam(r, "id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid id")
		return
	}

	var p Product
	err = h.db.QueryRow(r.Context(),
		`SELECT id, sku, name, price, stock, created_at FROM products WHERE id = $1`, id).
		Scan(&p.ID, &p.SKU, &p.Name, &p.Price, &p.Stock, &p.CreatedAt)
	if err != nil {
		if err == pgx.ErrNoRows {
			writeError(w, http.StatusNotFound, "product not found")
			return
		}
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, p)
}

func (h *Handler) CreateProduct(w http.ResponseWriter, r *http.Request) {
	var body struct {
		SKU   string  `json:"sku"`
		Name  string  `json:"name"`
		Price float64 `json:"price"`
		Stock int     `json:"stock"`
	}
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if body.SKU == "" || body.Name == "" {
		writeError(w, http.StatusUnprocessableEntity, "sku and name required")
		return
	}

	var p Product
	err := h.db.QueryRow(r.Context(), `
		INSERT INTO products (sku, name, price, stock) VALUES ($1, $2, $3, $4)
		RETURNING id, sku, name, price, stock, created_at`,
		body.SKU, body.Name, body.Price, body.Stock).
		Scan(&p.ID, &p.SKU, &p.Name, &p.Price, &p.Stock, &p.CreatedAt)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusCreated, p)
}
