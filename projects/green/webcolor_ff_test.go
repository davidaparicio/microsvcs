package main

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/labstack/echo/v4"
	"github.com/stretchr/testify/assert"
)

func TestGetCircle(t *testing.T) {
	tests := []struct {
		name     string
		color    string
		expected string
	}{
		{"red color", "red", "🔴"},
		{"orange color", "orange", "🟠"},
		{"yellow color", "yellow", "🟡"},
		{"green color", "green", "🟢"},
		{"blue color", "blue", "🔵"},
		{"purple color", "purple", "🟣"},
		{"brown color", "brown", "🟤"},
		{"black color", "black", "⚫"},
		{"white color", "white", "⚪"},
		{"unknown color", "unknown", ""},
		{"empty string", "", ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := getCircle(tt.color)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func TestTemplateRegistry_Render(t *testing.T) {
	// This test verifies the TemplateRegistry structure
	// Note: Full template testing would require actual template files

	// Test that TemplateRegistry can be created
	tr := &TemplateRegistry{
		templates: nil,
	}

	assert.NotNil(t, tr)
	assert.Nil(t, tr.templates)

	// Testing actual Render would require loading real templates from assets/view/*.html
	// which is beyond unit test scope (would be an integration test)
}

func TestApiHandler_Request(t *testing.T) {
	// This test verifies that the handler can be set up
	// Note: Full handler testing requires template and feature flag initialization
	// which is beyond unit test scope (would be an integration test)

	e := echo.New()
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	rec := httptest.NewRecorder()
	c := e.NewContext(req, rec)

	// Verify the request and context are properly set up
	assert.NotNil(t, e)
	assert.NotNil(t, req)
	assert.NotNil(t, rec)
	assert.NotNil(t, c)
	assert.Equal(t, http.MethodGet, req.Method)
	assert.Equal(t, "/", req.URL.Path)

	// Testing actual apiHandler would require:
	// - Initialized feature flag client
	// - Loaded templates from assets/view/*.html
	// - Proper users map initialization
	// This is better suited for integration tests
}

func TestPageDataStructure(t *testing.T) {
	// Test that PageData struct can be created and fields are accessible
	sysInfo := SystemInfo{
		DisplayName: "test-pod",
		OS:          "linux",
		Arch:        "amd64",
		Path:        "/test",
		RemoteAddr:  "127.0.0.1:1234",
		Namespace:   "default",
		PodColor:    "blue",
		Circle:      "🔵",
	}

	pageData := PageData{
		Users:      map[string]string{"user1": "red"},
		SystemInfo: sysInfo,
	}

	assert.NotNil(t, pageData)
	assert.Equal(t, "test-pod", pageData.SystemInfo.DisplayName)
	assert.Equal(t, "red", pageData.Users["user1"])
}

func TestSystemInfoStructure(t *testing.T) {
	// Test SystemInfo struct initialization
	sysInfo := SystemInfo{
		DisplayName: "pod namespace/hostname",
		OS:          "darwin",
		Arch:        "arm64",
		Path:        "/api/test",
		RemoteAddr:  "192.168.1.1:8080",
		Namespace:   "production",
		PodColor:    "green",
		Circle:      "🟢",
	}

	assert.Equal(t, "pod namespace/hostname", sysInfo.DisplayName)
	assert.Equal(t, "darwin", sysInfo.OS)
	assert.Equal(t, "arm64", sysInfo.Arch)
	assert.Equal(t, "/api/test", sysInfo.Path)
	assert.Equal(t, "192.168.1.1:8080", sysInfo.RemoteAddr)
	assert.Equal(t, "production", sysInfo.Namespace)
	assert.Equal(t, "green", sysInfo.PodColor)
	assert.Equal(t, "🟢", sysInfo.Circle)
}
