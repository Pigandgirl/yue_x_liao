package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresDB struct {
	Pool *pgxpool.Pool
}

func NewPostgresDB(ctx context.Context, host, port, user, password, dbname string) (*PostgresDB, error) {
	dsn := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable",
		user, password, host, port, dbname)

	poolConfig, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("failed to parse database config: %w", err)
	}

	poolConfig.MaxConns = 25
	poolConfig.MinConns = 5
	poolConfig.MaxConnLifetime = time.Hour
	poolConfig.MaxConnIdleTime = 30 * time.Minute
	poolConfig.HealthCheckPeriod = time.Minute

	pool, err := pgxpool.NewWithConfig(ctx, poolConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return &PostgresDB{Pool: pool}, nil
}

func (db *PostgresDB) Close() {
	if db.Pool != nil {
		db.Pool.Close()
	}
}

func (db *PostgresDB) Ping(ctx context.Context) error {
	return db.Pool.Ping(ctx)
}

func (db *PostgresDB) RunMigrations(ctx context.Context) error {
	migration := `
	CREATE TABLE IF NOT EXISTS users (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		username VARCHAR(50) UNIQUE NOT NULL,
		password_hash VARCHAR(255) NOT NULL,
		public_key TEXT,
		email VARCHAR(255) UNIQUE NOT NULL,
		created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
		updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
	CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);

	CREATE TABLE IF NOT EXISTS messages (
		id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
		sender UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		receiver UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
		encrypted_payload TEXT NOT NULL,
		is_read BOOLEAN DEFAULT FALSE,
		created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender);
	CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver);
	CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(sender, receiver);
	CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);
	`

	_, err := db.Pool.Exec(ctx, migration)
	if err != nil {
		return fmt.Errorf("failed to run migrations: %w", err)
	}

	return nil
}
