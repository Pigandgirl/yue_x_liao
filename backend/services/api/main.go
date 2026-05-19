package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gofiber/contrib/websocket"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/gofiber/fiber/v2/middleware/recover"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
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
	MinioEndpoint    string
	MinioAccessKey   string
	MinioSecretKey   string
	MinioBucket      string
}

type App struct {
	fiber   *fiber.App
	config  *Config
	db      *pgxpool.Pool
	redis   *redis.Client
}

func main() {
	cfg := loadConfig()
	app := NewApp(cfg)

	if err := app.connectDatabase(); err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer app.db.Pool().Close()

	if err := app.connectRedis(); err != nil {
		log.Fatalf("Failed to connect to Redis: %v", err)
	}
	defer app.redis.Close()

	app.setupRoutes()

	go func() {
		if err := app.fiber.Listen(fmt.Sprintf("%s:%s", cfg.AppHost, cfg.AppPort)); err != nil {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	log.Printf("Server started on %s:%s", cfg.AppHost, cfg.AppPort)

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")
	if err := app.fiber.Shutdown(); err != nil {
		log.Printf("Error shutting down server: %v", err)
	}
	log.Println("Server stopped")
}

func loadConfig() *Config {
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
		MinioEndpoint:    getEnv("MINIO_ENDPOINT", "localhost:9000"),
		MinioAccessKey:   getEnv("MINIO_ROOT_USER", "minioadmin"),
		MinioSecretKey:   getEnv("MINIO_ROOT_PASSWORD", ""),
		MinioBucket:      getEnv("MINIO_BUCKET", "user-files"),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func NewApp(cfg *Config) *App {
	f := fiber.New(fiber.Config{
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
		BodyLimit:    100 * 1024 * 1024,
	})

	f.Use(recover.New())
	f.Use(logger.New())
	f.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowMethods: "GET,POST,PUT,DELETE,OPTIONS",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
	}))

	return &App{
		fiber:  f,
		config: cfg,
	}
}

func (a *App) connectDatabase() error {
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable",
		a.config.PostgresUser,
		a.config.PostgresPassword,
		a.config.PostgresHost,
		a.config.PostgresPort,
		a.config.PostgresDB,
	)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	poolConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return fmt.Errorf("failed to parse database config: %w", err)
	}

	poolConfig.MaxConns = 25
	poolConfig.MinConns = 5
	poolConfig.MaxConnLifetime = time.Hour
	poolConfig.MaxConnIdleTime = 30 * time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return fmt.Errorf("failed to create connection pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		return fmt.Errorf("failed to ping database: %w", err)
	}

	a.db = pool
	log.Println("Connected to PostgreSQL database")
	return nil
}

func (a *App) connectRedis() error {
	a.redis = redis.NewClient(&redis.Options{
		Addr:         fmt.Sprintf("%s:%s", a.config.RedisHost, a.config.RedisPort),
		Password:     a.config.RedisPassword,
		DB:           0,
		PoolSize:     50,
		MinIdleConns: 10,
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
	})

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := a.redis.Ping(ctx).Err(); err != nil {
		return fmt.Errorf("failed to ping Redis: %w", err)
	}

	log.Println("Connected to Redis")
	return nil
}

func (a *App) setupRoutes() {
	a.fiber.Get("/health", a.healthCheck)
	a.fiber.Get("/ready", a.readinessCheck)

	api := a.fiber.Group("/api/v1")

	api.Post("/auth/register", a.handleRegister)
	api.Post("/auth/login", a.handleLogin)

	users := api.Group("/users", a.authMiddleware)
	users.Get("/:id", a.getUser)
	users.Put("/:id", a.updateUser)

	messages := api.Group("/messages", a.authMiddleware)
	messages.Get("/:conversationId", a.getMessages)
	messages.Post("/", a.sendMessage)

	files := api.Group("/files", a.authMiddleware)
	files.Post("/upload", a.uploadFile)
	files.Get("/:fileId", a.downloadFile)
	files.Delete("/:fileId", a.deleteFile)

	a.fiber.Use("/ws", websocket.New(func(c *websocket.Conn) {
		a.handleWebSocket(c)
	}))
}

func (a *App) healthCheck(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"status": "healthy",
		"time":   time.Now().UTC(),
	})
}

func (a *App) readinessCheck(c *fiber.Ctx) error {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	if err := a.db.Ping(ctx); err != nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"status":   "unhealthy",
			"database": "disconnected",
		})
	}

	if err := a.redis.Ping(ctx).Err(); err != nil {
		return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
			"status": "unhealthy",
			"redis":  "disconnected",
		})
	}

	return c.JSON(fiber.Map{
		"status":   "ready",
		"database": "connected",
		"redis":    "connected",
	})
}

func (a *App) authMiddleware(c *fiber.Ctx) error {
	auth := c.Get("Authorization")
	if auth == "" {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "missing authorization header",
		})
	}
	return c.Next()
}

func (a *App) handleRegister(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"message": "register endpoint - to be implemented",
	})
}

func (a *App) handleLogin(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"message": "login endpoint - to be implemented",
	})
}

func (a *App) getUser(c *fiber.Ctx) error {
	userId := c.Params("id")
	return c.JSON(fiber.Map{
		"message": fmt.Sprintf("get user %s - to be implemented", userId),
	})
}

func (a *App) updateUser(c *fiber.Ctx) error {
	userId := c.Params("id")
	return c.JSON(fiber.Map{
		"message": fmt.Sprintf("update user %s - to be implemented", userId),
	})
}

func (a *App) getMessages(c *fiber.Ctx) error {
	conversationId := c.Params("conversationId")
	return c.JSON(fiber.Map{
		"message": fmt.Sprintf("get messages for conversation %s - to be implemented", conversationId),
	})
}

func (a *App) sendMessage(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"message": "send message - to be implemented",
	})
}

func (a *App) uploadFile(c *fiber.Ctx) error {
	return c.JSON(fiber.Map{
		"message": "upload file - to be implemented",
	})
}

func (a *App) downloadFile(c *fiber.Ctx) error {
	fileId := c.Params("fileId")
	return c.JSON(fiber.Map{
		"message": fmt.Sprintf("download file %s - to be implemented", fileId),
	})
}

func (a *App) deleteFile(c *fiber.Ctx) error {
	fileId := c.Params("fileId")
	return c.JSON(fiber.Map{
		"message": fmt.Sprintf("delete file %s - to be implemented", fileId),
	})
}

func (a *App) handleWebSocket(c *websocket.Conn) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("WebSocket panic recovered: %v", r)
		}
		c.Close()
	}()

	log.Printf("WebSocket connection established: %s", c.RemoteAddr())

	for {
		_, msg, err := c.ReadMessage()
		if err != nil {
			if websocket.IsCloseError(err, websocket.CloseGoingAway, websocket.CloseNormalClosure) {
				log.Printf("WebSocket connection closed: %s", c.RemoteAddr())
			} else {
				log.Printf("WebSocket read error: %v", err)
			}
			break
		}

		log.Printf("Received message: %s", string(msg))

		if err := c.WriteMessage(websocket.TextMessage, []byte("echo: "+string(msg))); err != nil {
			log.Printf("WebSocket write error: %v", err)
			break
		}
	}
}
