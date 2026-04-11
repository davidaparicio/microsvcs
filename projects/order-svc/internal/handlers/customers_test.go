package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/labstack/echo/v4"
)

func TestCreateCustomer_Validation(t *testing.T) {
	// Handler has nil db — if validation passes and db is accessed, it panics,
	// confirming the validation path was not reached.
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
			wantError:  "name and email required",
		},
		{
			name:       "missing email",
			body:       `{"name":"Alice"}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "name and email required",
		},
		{
			name:       "missing name",
			body:       `{"email":"a@b.com"}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "name and email required",
		},
		{
			name:       "invalid email format",
			body:       `{"name":"Alice","email":"not-an-email"}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "invalid email format",
		},
		{
			name:       "email without domain",
			body:       `{"name":"Alice","email":"alice@"}`,
			wantStatus: http.StatusUnprocessableEntity,
			wantError:  "invalid email format",
		},
		{
			name:       "invalid JSON",
			body:       `{invalid`,
			wantStatus: http.StatusBadRequest,
			wantError:  "invalid JSON",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := echo.New()
			req := httptest.NewRequest(http.MethodPost, "/api/v1/customers",
				strings.NewReader(tt.body))
			req.Header.Set(echo.HeaderContentType, echo.MIMEApplicationJSON)
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)

			err := h.CreateCustomer(c)
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

func TestGetCustomer_InvalidID(t *testing.T) {
	h := &Handler{db: nil}
	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/api/v1/customers/abc", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)
	c.SetParamNames("id")
	c.SetParamValues("abc")

	err := h.GetCustomer(c)
	if err != nil {
		t.Fatalf("handler returned error: %v", err)
	}
	if rec.Code != http.StatusBadRequest {
		t.Errorf("status = %d, want %d", rec.Code, http.StatusBadRequest)
	}
}
