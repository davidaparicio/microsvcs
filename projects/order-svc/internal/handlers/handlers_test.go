package handlers

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"
)

func TestIsValidEmail(t *testing.T) {
	tests := []struct {
		email string
		want  bool
	}{
		{"user@example.com", true},
		{"user.name+tag@example.co.uk", true},
		{"user@sub.domain.com", true},
		{"", false},
		{"not-an-email", false},
		{"@example.com", false},
		{"user@", false},
		{"user@.com", false},
		{"user@com", false},
	}
	for _, tt := range tests {
		t.Run(tt.email, func(t *testing.T) {
			if got := isValidEmail(tt.email); got != tt.want {
				t.Errorf("isValidEmail(%q) = %v, want %v", tt.email, got, tt.want)
			}
		})
	}
}

func TestParsePagination(t *testing.T) {
	tests := []struct {
		name       string
		query      string
		wantLimit  int
		wantOffset int
	}{
		{"defaults", "", 20, 0},
		{"custom limit", "?limit=10", 10, 0},
		{"custom offset", "?offset=5", 20, 5},
		{"both", "?limit=50&offset=25", 50, 25},
		{"limit too high", "?limit=200", 20, 0},
		{"limit zero", "?limit=0", 20, 0},
		{"negative limit", "?limit=-1", 20, 0},
		{"negative offset", "?offset=-1", 20, 0},
		{"non-numeric limit", "?limit=abc", 20, 0},
		{"max limit", "?limit=100", 100, 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := echo.New()
			req := httptest.NewRequest(http.MethodGet, "/"+tt.query, nil)
			rec := httptest.NewRecorder()
			c := e.NewContext(req, rec)

			limit, offset := parsePagination(c)
			if limit != tt.wantLimit {
				t.Errorf("limit = %d, want %d", limit, tt.wantLimit)
			}
			if offset != tt.wantOffset {
				t.Errorf("offset = %d, want %d", offset, tt.wantOffset)
			}
		})
	}
}
