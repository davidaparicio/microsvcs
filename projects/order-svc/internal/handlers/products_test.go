package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
)

func TestCreateProduct_Validation(t *testing.T) {
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
			wantError:  "sku and name required",
		},
		{
			name:       "missing name",
			body:       `{"sku":"SKU-001"}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "sku and name required",
		},
		{
			name:       "missing sku",
			body:       `{"name":"Widget"}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "sku and name required",
		},
		{
			name:       "negative price",
			body:       `{"sku":"SKU-001","name":"Widget","price":-1.50}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "price must not be negative",
		},
		{
			name:       "negative stock",
			body:       `{"sku":"SKU-001","name":"Widget","price":9.99,"stock":-5}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "stock must not be negative",
		},
		{
			name:       "invalid JSON",
			body:       `{broken`,
			wantStatus: http.StatusBadRequest,
			wantError:  "invalid JSON",
		},
		{
			name:       "zero price is valid",
			body:       `{"sku":"FREE-001","name":"Freebie","price":0,"stock":10}`,
			wantStatus: 0, // will panic (nil db) — skip status check
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// Skip tests that would reach the DB (valid input with nil db)
			if tt.wantStatus == 0 {
				t.Skip("valid input would hit nil db")
			}

			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/api/v1/products",
				strings.NewReader(tt.body))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)

			err := h.CreateProduct(c)
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

func TestGetProduct_InvalidID(t *testing.T) {
	h := &Handler{db: nil}
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/products/xyz", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetParamNames("id")
	c.SetParamValues("xyz")

	err := h.GetProduct(c)
	if err != nil {
		t.Fatalf("handler returned error: %v", err)
	}
	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}
