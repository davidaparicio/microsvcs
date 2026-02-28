package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"

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

	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	if err := pool.Ping(context.Background()); err != nil {
		log.Fatalf("ping db: %v", err)
	}
	log.Println("database connected")

	r := chi.NewRouter()
	r.Use(middleware.Logger)
	r.Use(middleware.Recoverer)

	r.Get("/health", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok"}`))
	})

	h := handlers.New(pool)

	r.Route("/api/v1", func(r chi.Router) {
		r.Route("/customers", func(r chi.Router) {
			r.Get("/", h.ListCustomers)
			r.Post("/", h.CreateCustomer)
			r.Get("/{id}", h.GetCustomer)
		})
		r.Route("/products", func(r chi.Router) {
			r.Get("/", h.ListProducts)
			r.Post("/", h.CreateProduct)
			r.Get("/{id}", h.GetProduct)
		})
		r.Route("/orders", func(r chi.Router) {
			r.Get("/", h.ListOrders)
			r.Post("/", h.CreateOrder)
			r.Get("/{id}", h.GetOrder)
		})
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("listening on :%s", port)
	if err := http.ListenAndServe(":"+port, r); err != nil {
		log.Fatalf("server: %v", err)
	}
}
