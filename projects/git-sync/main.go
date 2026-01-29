package main

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/config"
	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/sync"
	"github.com/davidaparicio/microsvcs/projects/git-sync/internal/version"
	"github.com/labstack/echo/v4"
	"github.com/robfig/cron/v3"
)

func main() {
	version.PrintVersion()

	cfg := config.LoadFromEnv()
	if err := cfg.Validate(); err != nil {
		fmt.Fprintf(os.Stderr, "Configuration error: %v\n", err)
		os.Exit(1)
	}

	// Initialize syncer
	syncer, err := sync.NewSyncer(cfg)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to initialize syncer: %v\n", err)
		os.Exit(1)
	}

	// Initial sync
	fmt.Println("Performing initial sync...")
	if err := syncer.Sync(context.Background()); err != nil {
		fmt.Fprintf(os.Stderr, "Initial sync failed: %v\n", err)
		os.Exit(1)
	}

	// If SYNC_ONCE is true, exit after initial sync
	if cfg.SyncOnce {
		fmt.Println("SYNC_ONCE is enabled, exiting after initial sync")
		return
	}

	// Setup cron scheduler
	c := cron.New()
	_, err = c.AddFunc(cfg.SyncInterval, func() {
		ctx := context.Background()
		if err := syncer.Sync(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "Sync failed: %v\n", err)
		}
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to schedule sync: %v\n", err)
		os.Exit(1)
	}
	c.Start()
	defer c.Stop()

	fmt.Printf("Sync scheduled with interval: %s\n", cfg.SyncInterval)

	// HTTP server for health checks
	e := echo.New()
	e.HideBanner = true
	e.GET("/healthz", healthzHandler(syncer))
	e.GET("/readyz", readyzHandler(syncer))
	e.GET("/metrics", metricsHandler(syncer))
	e.GET("/version", versionHandler)

	// Graceful shutdown
	go func() {
		if err := e.Start(fmt.Sprintf(":%s", cfg.Port)); err != nil && err != http.ErrServerClosed {
			fmt.Fprintf(os.Stderr, "HTTP server error: %v\n", err)
		}
	}()

	fmt.Printf("Health check server listening on port %s\n", cfg.Port)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	fmt.Println("Shutting down gracefully...")
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := e.Shutdown(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Shutdown error: %v\n", err)
	}
}

func healthzHandler(syncer *sync.Syncer) echo.HandlerFunc {
	return func(c echo.Context) error {
		if syncer.IsHealthy() {
			return c.NoContent(http.StatusNoContent)
		}
		return c.NoContent(http.StatusServiceUnavailable)
	}
}

func readyzHandler(syncer *sync.Syncer) echo.HandlerFunc {
	return func(c echo.Context) error {
		if syncer.IsHealthy() {
			return c.JSON(http.StatusOK, map[string]string{"status": "ready"})
		}
		return c.JSON(http.StatusServiceUnavailable, map[string]string{"status": "not ready"})
	}
}

func metricsHandler(syncer *sync.Syncer) echo.HandlerFunc {
	return func(c echo.Context) error {
		status := syncer.GetStatus()
		return c.JSON(http.StatusOK, status)
	}
}

func versionHandler(c echo.Context) error {
	return c.JSON(http.StatusOK, map[string]string{
		"version":   version.Version,
		"gitCommit": version.GitCommit,
		"buildDate": version.BuildDate,
	})
}
