package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"github.com/labstack/echo/v4"
	"github.com/labstack/echo/v4/middleware"

	"github.com/davidaparicio/microsvcs/order-svc/internal/handlers"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Println("no .env file, using environment variables")
	}

	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is required")
	}

	// S8: configure DB pool instead of using defaults.
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		log.Fatalf("parse db config: %v", err)
	}
	cfg.MaxConns = 25
	cfg.MinConns = 5

	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(context.Background()); err != nil {
		log.Fatalf("ping db: %v", err)
	}
	log.Println("database connected")

	e := echo.New()
	e.Use(middleware.Logger())
	e.Use(middleware.Recover())

	e.GET("/health", func(c echo.Context) error {
		return c.JSON(http.StatusOK, map[string]string{"status": "ok"})
	})

	h := handlers.New(pool)

	api := e.Group("/api/v1")

	customers := api.Group("/customers")
	customers.GET("", h.ListCustomers)
	customers.POST("", h.CreateCustomer)
	customers.GET("/:id", h.GetCustomer)

	products := api.Group("/products")
	products.GET("", h.ListProducts)
	products.POST("", h.CreateProduct)
	products.GET("/:id", h.GetProduct)

	orders := api.Group("/orders")
	orders.GET("", h.ListOrders)
	orders.POST("", h.CreateOrder)
	orders.GET("/:id", h.GetOrder)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// S2: graceful shutdown — handle SIGINT/SIGTERM for in-flight requests.
	go func() {
		if err := e.Start(":" + port); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("shutting down server...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := e.Shutdown(ctx); err != nil {
		log.Fatalf("server shutdown: %v", err)
	}
	log.Println("server stopped")
}
