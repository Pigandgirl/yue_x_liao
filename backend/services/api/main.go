package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"yue_liao_api/internal/database"
	"yue_liao_api/internal/handlers"
	"yue_liao_api/internal/middleware"
	"yue_liao_api/internal/websocket"

	"github.com/gofiber/contrib/websocket"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
)

type Config struct {
	PostgresHost     string
	PostgresPort     string
	PostgresDB       string
	PostgresUser     string
	PostgresPassword string
	RedisHost        string
	RedisPort        string
	RedisPassword    string
	AppHost          string
	AppPort          string
	JWTSecret        string
	JWTExpiration    time.Duration
}

func main() {
	cfg := loadConfig()
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	db, err := database.NewPostgresDB(ctx,
		cfg.PostgresHost,
		cfg.PostgresPort,
		cfg.PostgresUser,
		cfg.PostgresPassword,
		cfg.PostgresDB,
	)
	if err != nil {
		log.Fatalf("Failed to connect to PostgreSQL: %v", err)
	}
	defer db.Close()

	log.Println("Connected to PostgreSQL")

	if err := db.RunMigrations(ctx); err != nil {
		log.Fatalf("Failed to run migrations: %v", err)
	}
	log.Println("Database migrations completed")

	var redisDB *database.RedisDB
	redisDB, err = database.NewRedisDB(ctx, cfg.RedisHost, cfg.RedisPort, cfg.RedisPassword)
	if err != nil {
		log.Printf("Warning: Failed to connect to Redis: %v (continuing without Redis)", err)
		redisDB = nil
	} else {
		defer redisDB.Close()
		log.Println("Connected to Redis")
	}

	userRepo := database.NewUserRepository(db)
	messageRepo := database.NewMessageRepository(db)

	jwtMgr := middleware.NewJWTManager(cfg.JWTSecret, cfg.JWTExpiration)

	hub := websocket.NewHub(userRepo, messageRepo, redisDB)
	go hub.Run(ctx)

	authHandler := handlers.NewAuthHandler(userRepo, jwtMgr)
	messageHandler := handlers.NewMessageHandler(messageRepo, userRepo)
	wsHandler := handlers.NewWebSocketHandler(hub, jwtMgr)

	app := fiber.New(fiber.Config{
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
		BodyLimit:    10 * 1024 * 1024,
	})

	app.Use(recover.New())
	app.Use(logger.New())
	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowMethods: "GET,POST,PUT,DELETE,OPTIONS",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
	}))

	app.Get("/health", func(c *fiber.Ctx) error {
		if err := db.Ping(c.Context()); err != nil {
			return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
				"status":   "unhealthy",
				"database": "disconnected",
			})
		}

		status := fiber.Map{"status": "healthy", "database": "connected"}
		if redisDB != nil {
			if err := redisDB.Ping(c.Context()); err != nil {
				status["redis"] = "disconnected"
			} else {
				status["redis"] = "connected"
			}
		} else {
			status["redis"] = "not configured"
		}

		return c.JSON(status)
	})

	app.Get("/ready", func(c *fiber.Ctx) error {
		if err := db.Ping(c.Context()); err != nil {
			return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
				"status": "not ready",
				"error":  "database not available",
			})
		}
		return c.JSON(fiber.Map{"status": "ready"})
	})

	api := app.Group("/api")

	auth := api.Group("/auth")
	auth.Post("/register", authHandler.Register)
	auth.Post("/login", authHandler.Login)

	apiProtected := api.Group("", middleware.JWTMiddleware(jwtMgr))

	apiProtected.Get("/me", authHandler.GetCurrentUser)
	apiProtected.Put("/public-key", authHandler.UpdatePublicKey)
	apiProtected.Get("/users/search", authHandler.SearchUsers)

	messages := apiProtected.Group("/messages")
	messages.Get("", messageHandler.GetMessages)
	messages.Get("/unread", messageHandler.GetUnreadCount)
	messages.Post("/read", messageHandler.MarkAsRead)

	conversations := apiProtected.Group("/conversations")
	conversations.Get("", messageHandler.GetConversations)
	conversations.Post("/:username/read", messageHandler.MarkConversationAsRead)
	conversations.Get("/:username/unread", func(c *fiber.Ctx) error {
		c.Query("with", c.Params("username"))
		return messageHandler.GetUnreadCount(c)
	})

	wsGroup := app.Group("/ws")
	wsGroup.Use(func(c *fiber.Ctx) error {
		if !wsHandler.UpgradeCheck(c) {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "WebSocket upgrade failed",
			})
		}
		return c.Next()
	})
	wsGroup.Get("", websocket.New(wsHandler.HandleWebSocket))

	app.Get("/api/online-users", wsHandler.GetOnlineUsers)
	app.Get("/api/users/:username/online", wsHandler.CheckUserOnline)

	go func() {
		addr := fmt.Sprintf("%s:%s", cfg.AppHost, cfg.AppPort)
		log.Printf("Server starting on %s", addr)
		if err := app.Listen(addr); err != nil {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")
	cancel()

	if err := app.Shutdown(); err != nil {
		log.Printf("Error shutting down server: %v", err)
	}

	log.Println("Server stopped")
}

func loadConfig() *Config {
	jwtExpiration := 24 * time.Hour
	if exp := os.Getenv("JWT_EXPIRATION_HOURS"); exp != "" {
		var hours int
		if _, err := fmt.Sscanf(exp, "%d", &hours); err == nil {
			jwtExpiration = time.Duration(hours) * time.Hour
		}
	}

	return &Config{
		PostgresHost:     getEnv("POSTGRES_HOST", "localhost"),
		PostgresPort:     getEnv("POSTGRES_PORT", "5432"),
		PostgresDB:       getEnv("POSTGRES_DB", "yue_liao"),
		PostgresUser:     getEnv("POSTGRES_USER", "yue_user"),
		PostgresPassword: getEnv("POSTGRES_PASSWORD", ""),
		RedisHost:        getEnv("REDIS_HOST", "localhost"),
		RedisPort:        getEnv("REDIS_PORT", "6379"),
		RedisPassword:    getEnv("REDIS_PASSWORD", ""),
		AppHost:          getEnv("APP_HOST", "0.0.0.0"),
		AppPort:          getEnv("APP_PORT", "8080"),
		JWTSecret:        getEnv("JWT_SECRET", "default-secret-change-in-production"),
		JWTExpiration:    jwtExpiration,
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}
