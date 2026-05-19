package database

import (
	"context"
	"errors"
	"time"

	"yue_liao_api/internal/models"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var (
	ErrUserNotFound      = errors.New("user not found")
	ErrUserAlreadyExists = errors.New("user already exists")
)

type UserRepository struct {
	pool *pgxpool.Pool
}

func NewUserRepository(db *PostgresDB) *UserRepository {
	return &UserRepository{pool: db.Pool}
}

func (r *UserRepository) Create(ctx context.Context, user *models.User) error {
	query := `
		INSERT INTO users (id, username, password_hash, public_key, email, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`

	user.ID = uuid.New()
	user.CreatedAt = time.Now()
	user.UpdatedAt = time.Now()

	_, err := r.pool.Exec(ctx, query,
		user.ID,
		user.Username,
		user.PasswordHash,
		user.PublicKey,
		user.Email,
		user.CreatedAt,
		user.UpdatedAt,
	)

	if err != nil {
		if isUniqueViolation(err) {
			return ErrUserAlreadyExists
		}
		return err
	}

	return nil
}

func (r *UserRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.User, error) {
	query := `
		SELECT id, username, password_hash, public_key, email, created_at, updated_at
		FROM users
		WHERE id = $1
	`

	user := &models.User{}
	err := r.pool.QueryRow(ctx, query, id).Scan(
		&user.ID,
		&user.Username,
		&user.PasswordHash,
		&user.PublicKey,
		&user.Email,
		&user.CreatedAt,
		&user.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}

	return user, nil
}

func (r *UserRepository) GetByUsername(ctx context.Context, username string) (*models.User, error) {
	query := `
		SELECT id, username, password_hash, public_key, email, created_at, updated_at
		FROM users
		WHERE username = $1
	`

	user := &models.User{}
	err := r.pool.QueryRow(ctx, query, username).Scan(
		&user.ID,
		&user.Username,
		&user.PasswordHash,
		&user.PublicKey,
		&user.Email,
		&user.CreatedAt,
		&user.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}

	return user, nil
}

func (r *UserRepository) GetByEmail(ctx context.Context, email string) (*models.User, error) {
	query := `
		SELECT id, username, password_hash, public_key, email, created_at, updated_at
		FROM users
		WHERE email = $1
	`

	user := &models.User{}
	err := r.pool.QueryRow(ctx, query, email).Scan(
		&user.ID,
		&user.Username,
		&user.PasswordHash,
		&user.PublicKey,
		&user.Email,
		&user.CreatedAt,
		&user.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}

	return user, nil
}

func (r *UserRepository) UpdatePublicKey(ctx context.Context, userID uuid.UUID, publicKey string) error {
	query := `
		UPDATE users
		SET public_key = $1, updated_at = $2
		WHERE id = $3
	`

	_, err := r.pool.Exec(ctx, query, publicKey, time.Now(), userID)
	return err
}

func (r *UserRepository) Update(ctx context.Context, user *models.User) error {
	query := `
		UPDATE users
		SET username = $1, public_key = $2, updated_at = $3
		WHERE id = $4
	`

	user.UpdatedAt = time.Now()
	_, err := r.pool.Exec(ctx, query, user.Username, user.PublicKey, user.UpdatedAt, user.ID)
	return err
}

func (r *UserRepository) Search(ctx context.Context, query string, limit int) ([]*models.User, error) {
	sql := `
		SELECT id, username, password_hash, public_key, email, created_at, updated_at
		FROM users
		WHERE username ILIKE $1
		LIMIT $2
	`

	rows, err := r.pool.Query(ctx, sql, "%"+query+"%", limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []*models.User
	for rows.Next() {
		user := &models.User{}
		err := rows.Scan(
			&user.ID,
			&user.Username,
			&user.PasswordHash,
			&user.PublicKey,
			&user.Email,
			&user.CreatedAt,
			&user.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		users = append(users, user)
	}

	return users, rows.Err()
}

func isUniqueViolation(err error) bool {
	return err != nil && (contains(err.Error(), "unique") || contains(err.Error(), "duplicate"))
}

func contains(s, substr string) bool {
	return len(s) >= len(substr) && (s == substr || len(s) > 0 && containsHelper(s, substr))
}

func containsHelper(s, substr string) bool {
	for i := 0; i <= len(s)-len(substr); i++ {
		if s[i:i+len(substr)] == substr {
			return true
		}
	}
	return false
}
