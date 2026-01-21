package main

import (
	"context"
	"flag"
	"fmt"
	"html/template"
	"io"
	"net/http"
	"os"
	"runtime"
	"strings"
	"time"

	"github.com/davidaparicio/microsvcs/projects/blue/internal/name"
	"github.com/davidaparicio/microsvcs/projects/blue/internal/version"
	"github.com/google/uuid"
	"github.com/labstack/echo/v4"
	ffclient "github.com/thomaspoignant/go-feature-flag"
	"github.com/thomaspoignant/go-feature-flag/ffcontext"
	"github.com/thomaspoignant/go-feature-flag/retriever/fileretriever"
)

var users = make(map[string]ffcontext.EvaluationContext, 2500)

// PageData holds all data to be rendered in the template
type PageData struct {
	Users      map[string]string
	SystemInfo SystemInfo
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

	configFile := flag.String("configFile", "./demo-flags.goff.yaml", "flags.goff.yaml")
	flag.Parse()

	_ = ffclient.Init(ffclient.Config{
		PollingInterval: 1 * time.Second,
		Context:         context.Background(),
		Retriever: &fileretriever.Retriever{
			Path: *configFile,
		},
	})

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
	// Get user color variations
	mapToRender := make(map[string]string, 2500)
	for k, user := range users {
		color, _ := ffclient.StringVariation("color-box", user, "grey")
		mapToRender[k] = color
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

func healthzHandler(c echo.Context) error {
	return c.NoContent(http.StatusOK)
}
