package handlers

import (
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
)

func TestCreateOrder_Validation(t *testing.T) {
	h := &Handler{db: nil}

	tests := []struct {
		name       string
		body       string
		wantStatus int
		wantError  string
	}{
		{
			name:       "empty body",
			body:       `{}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "customer_id and items required",
		},
		{
			name:       "missing items",
			body:       `{"customer_id":1}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "customer_id and items required",
		},
		{
			name:       "empty items array",
			body:       `{"customer_id":1,"items":[]}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "customer_id and items required",
		},
		{
			name:       "missing customer_id",
			body:       `{"items":[{"product_id":1,"quantity":1}]}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "customer_id and items required",
		},
		{
			name:       "zero quantity",
			body:       `{"customer_id":1,"items":[{"product_id":1,"quantity":0}]}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "quantity must be positive",
		},
		{
			name:       "negative quantity",
			body:       `{"customer_id":1,"items":[{"product_id":1,"quantity":-3}]}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "quantity must be positive",
		},
		{
			name:       "invalid JSON",
			body:       `{broken`,
			wantStatus: http.StatusBadRequest,
			wantError:  "invalid JSON",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/api/v1/orders",
				strings.NewReader(tt.body))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)

			err := h.CreateOrder(c)
			if err != nil {
				t.Fatalf("handler returned error: %v", err)
			}
			if rec.Code != tt.wantStatus {
				t.Errorf("status = %d, want %d", rec.Code, tt.wantStatus)
			}
			var resp map[string]string
			if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
				t.Fatalf("invalid JSON response: %v", err)
			}
			if resp["error"] != tt.wantError {
				t.Errorf("error = %q, want %q", resp["error"], tt.wantError)
			}
		})
	}
}

func TestGetOrder_InvalidID(t *testing.T) {
	h := &Handler{db: nil}
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/orders/abc", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetParamNames("id")
	c.SetParamValues("abc")

	err := h.GetOrder(c)
	if err != nil {
		t.Fatalf("handler returned error: %v", err)
	}
	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}

func TestMoneyRounding(t *testing.T) {
	// Verify that the rounding approach used in CreateOrder avoids float64 issues.
	// Classic example: 0.1 + 0.2 != 0.3 in float64.
	tests := []struct {
		name      string
		unitPrice float64
		quantity  int
		want      float64
	}{
		{"simple", 10.00, 3, 30.00},
		{"fractional", 19.99, 2, 39.98},
		{"small price high qty", 0.10, 100, 10.00},
		{"classic rounding trap", 33.33, 3, 99.99},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := math.Round(tt.unitPrice*float64(tt.quantity)*100) / 100
			if got != tt.want {
				t.Errorf("round(%v * %d) = %v, want %v", tt.unitPrice, tt.quantity, got, tt.want)
			}
		})
	}
}

func TestOrderItemJSON_UsesPrice(t *testing.T) {
	// Ensure OrderItem serializes "price" not "unit_price" (B2 fix verification).
	oi := OrderItem{ID: 1, ProductID: 2, Quantity: 3, Price: 9.99}
	data, err := json.Marshal(oi)
	if err != nil {
		t.Fatal(err)
	}
	var m map[string]any
	if err := json.Unmarshal(data, &m); err != nil {
		t.Fatal(err)
	}
	if _, ok := m["price"]; !ok {
		t.Error("OrderItem JSON should contain 'price' key")
	}
	if _, ok := m["unit_price"]; ok {
		t.Error("OrderItem JSON should not contain 'unit_price' key")
	}
}
