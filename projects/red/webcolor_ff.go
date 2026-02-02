package main

import (
	"context"
	"flag"
	"fmt"
	"html/template"
	"io"
	"log"
	"math"
	"net/http"
	"os"
	"runtime"
	"strings"
	"sync"
	"time"

	"github.com/davidaparicio/microsvcs/projects/red/internal/name"
	"github.com/davidaparicio/microsvcs/projects/red/internal/version"
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	ffclient "github.com/thomaspoignant/go-feature-flag"
	"github.com/thomaspoignant/go-feature-flag/ffcontext"
	"github.com/thomaspoignant/go-feature-flag/retriever/fileretriever"
)

var users = make(map[string]ffcontext.EvaluationContext, 2500)

// renderMetrics tracks server-side rendering performance
type renderMetrics struct {
	mu           sync.Mutex
	requestCount int64
	totalMs      float64
	lastMs       float64
	maxMs        float64
	minMs        float64
}

func (m *renderMetrics) record(ms float64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.requestCount++
	m.totalMs += ms
	m.lastMs = ms
	if ms > m.maxMs {
		m.maxMs = ms
	}
	if m.minMs == 0 || ms < m.minMs {
		m.minMs = ms
	}
}

var metrics = &renderMetrics{}

// KPIData holds rendering speed metrics
type KPIData struct {
	ServerRenderMs float64
}

// PageData holds all data to be rendered in the template
type PageData struct {
	Users      map[string]string
	SystemInfo SystemInfo
	KPI        KPIData
}

// SystemInfo holds system and request information
type SystemInfo struct {
	DisplayName    string
	OS             string
	Arch           string
	Path           string
	RemoteAddr     string
	Namespace      string
	PodColor       string
	Circle         string
	ServiceVersion string
	ServiceCommit  string
}

func main() {
	version.PrintVersion()

	configFile := flag.String("configFile", "/app/config/demo-flags.goff.yaml", "path to feature flags file")
	flag.Parse()

	if err := ffclient.Init(ffclient.Config{
		PollingInterval: 1 * time.Second,
		Context:         context.Background(),
		Retriever: &fileretriever.Retriever{
			Path: *configFile,
		},
	}); err != nil {
		log.Fatalf("Failed to initialize feature flag client: %v", err)
	}

	e := echo.New()
	e.HideBanner = true
	e.Static("/js", "assets/js")
	e.Static("/css", "assets/css")
	// Instantiate a template registry and register all html files inside the view folder
	e.Renderer = &TemplateRegistry{templates: template.Must(template.ParseGlob("assets/view/*.html"))}

	// init users
	for i := 0; i < 2500; i++ {
		id := uuid.New()
		u := ffcontext.NewEvaluationContext(id.String())
		users[fmt.Sprintf("user%d", i)] = u
	}

	e.GET("/", apiHandler)
	e.GET("/version", versionHandler)
	e.GET("/healthz", healthzHandler)
	e.GET("/metrics", metricsHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	fmt.Printf("Starting HTTP server (%s/%s) listening on port %s.\n", runtime.GOOS, runtime.GOARCH, port)
	e.Logger.Fatal(e.Start(":" + port))
}

type TemplateRegistry struct {
	templates *template.Template
}

func (t *TemplateRegistry) Render(w io.Writer, name string, data any, c echo.Context) error {
	return t.templates.ExecuteTemplate(w, name, data)
}

func getCircle(color string) string {
	circles := map[string]string{
		"red":    "🔴",
		"orange": "🟠",
		"yellow": "🟡",
		"green":  "🟢",
		"blue":   "🔵",
		"purple": "🟣",
		"brown":  "🟤",
		"black":  "⚫",
		"white":  "⚪",
	}
	circle, exists := circles[color]
	if exists {
		return circle
	}
	return ""
}

func apiHandler(c echo.Context) error {
	start := time.Now()

	// Get user color variations
	mapToRender := make(map[string]string, 2500)
	for k, user := range users {
		color, err := ffclient.StringVariation("color-box", user, "grey")
		if err != nil {
			log.Printf("Feature flag evaluation error for %s: %v", k, err)
		}
		mapToRender[k] = color
	}

	serverRenderMs := float64(time.Since(start).Microseconds()) / 1000.0
	metrics.record(serverRenderMs)
	kpi := KPIData{
		ServerRenderMs: serverRenderMs,
	}

	// Get system information
	hostname := name.GetHostname()
	namespace := name.GetNamespace()
	displayName := ""
	if namespace == "" {
		displayName = hostname
	} else {
		displayName = "pod " + namespace + "/" + hostname
	}
	podColor := strings.SplitN(hostname, "-", 2)[0]
	circles := getCircle(namespace) + getCircle(podColor)

	sysInfo := SystemInfo{
		DisplayName:    displayName,
		OS:             runtime.GOOS,
		Arch:           runtime.GOARCH,
		Path:           c.Request().URL.Path,
		RemoteAddr:     c.Request().RemoteAddr,
		Namespace:      namespace,
		PodColor:       podColor,
		Circle:         circles,
		ServiceVersion: version.Version,
		ServiceCommit:  version.GitCommit,
	}

	pageData := PageData{
		Users:      mapToRender,
		SystemInfo: sysInfo,
		KPI:        kpi,
	}

	return c.Render(http.StatusOK, "template.html", pageData)
}

func versionHandler(c echo.Context) error {
	response := map[string]string{
		"version": version.Version,
		"commit":  version.GitCommit,
	}
	return c.JSON(http.StatusOK, response)
}

func metricsHandler(c echo.Context) error {
	metrics.mu.Lock()
	count := metrics.requestCount
	totalMs := metrics.totalMs
	lastMs := metrics.lastMs
	maxMs := metrics.maxMs
	minMs := metrics.minMs
	metrics.mu.Unlock()

	avgMs := 0.0
	if count > 0 {
		avgMs = math.Round(totalMs/float64(count)*100) / 100
	}

	out := fmt.Sprintf(
		"# HELP http_render_duration_milliseconds Server-side page render duration in milliseconds.\n"+
			"# TYPE http_render_duration_milliseconds gauge\n"+
			"http_render_duration_milliseconds{stat=\"last\"} %.2f\n"+
			"http_render_duration_milliseconds{stat=\"avg\"} %.2f\n"+
			"http_render_duration_milliseconds{stat=\"min\"} %.2f\n"+
			"http_render_duration_milliseconds{stat=\"max\"} %.2f\n"+
			"# HELP http_render_requests_total Total number of page render requests.\n"+
			"# TYPE http_render_requests_total counter\n"+
			"http_render_requests_total %d\n",
		lastMs, avgMs, minMs, maxMs, count,
	)
	return c.String(http.StatusOK, out)
}

func healthzHandler(c echo.Context) error {
	return c.NoContent(http.StatusOK)
}
