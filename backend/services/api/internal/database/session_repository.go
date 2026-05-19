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
	ErrSessionNotFound = errors.New("session not found")
	ErrSessionExists   = errors.New("session already exists")
)

type SessionRepository struct {
	pool *pgxpool.Pool
}

func NewSessionRepository(db *PostgresDB) *SessionRepository {
	return &SessionRepository{pool: db.Pool}
}

func (r *SessionRepository) Create(ctx context.Context, session *models.Session) error {
	query := `
		INSERT INTO sessions (id, initiator_id, receiver_id, initiator_key, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6)
	`

	session.ID = uuid.New()
	session.CreatedAt = time.Now()
	session.UpdatedAt = time.Now()

	_, err := r.pool.Exec(ctx, query,
		session.ID,
		session.InitiatorID,
		session.ReceiverID,
		session.InitiatorKey,
		session.CreatedAt,
		session.UpdatedAt,
	)

	return err
}

func (r *SessionRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.Session, error) {
	query := `
		SELECT id, initiator_id, receiver_id, initiator_key, receiver_key, created_at, updated_at
		FROM sessions
		WHERE id = $1
	`

	session := &models.Session{}
	err := r.pool.QueryRow(ctx, query, id).Scan(
		&session.ID,
		&session.InitiatorID,
		&session.ReceiverID,
		&session.InitiatorKey,
		&session.ReceiverKey,
		&session.CreatedAt,
		&session.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSessionNotFound
		}
		return nil, err
	}

	return session, nil
}

func (r *SessionRepository) GetByUsers(ctx context.Context, user1, user2 uuid.UUID) (*models.Session, error) {
	query := `
		SELECT id, initiator_id, receiver_id, initiator_key, receiver_key, created_at, updated_at
		FROM sessions
		WHERE (initiator_id = $1 AND receiver_id = $2) OR (initiator_id = $2 AND receiver_id = $1)
		ORDER BY created_at DESC
		LIMIT 1
	`

	session := &models.Session{}
	err := r.pool.QueryRow(ctx, query, user1, user2).Scan(
		&session.ID,
		&session.InitiatorID,
		&session.ReceiverID,
		&session.InitiatorKey,
		&session.ReceiverKey,
		&session.CreatedAt,
		&session.UpdatedAt,
	)

	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrSessionNotFound
		}
		return nil, err
	}

	return session, nil
}

func (r *SessionRepository) GetUserSessions(ctx context.Context, userID uuid.UUID) ([]*models.Session, error) {
	query := `
		SELECT id, initiator_id, receiver_id, initiator_key, receiver_key, created_at, updated_at
		FROM sessions
		WHERE initiator_id = $1 OR receiver_id = $1
		ORDER BY updated_at DESC
	`

	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var sessions []*models.Session
	for rows.Next() {
		session := &models.Session{}
		err := rows.Scan(
			&session.ID,
			&session.InitiatorID,
			&session.ReceiverID,
			&session.InitiatorKey,
			&session.ReceiverKey,
			&session.CreatedAt,
			&session.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		sessions = append(sessions, session)
	}

	return sessions, rows.Err()
}

func (r *SessionRepository) UpdateReceiverKey(ctx context.Context, sessionID uuid.UUID, receiverKey string) error {
	query := `
		UPDATE sessions
		SET receiver_key = $1, updated_at = $2
		WHERE id = $3
	`

	_, err := r.pool.Exec(ctx, query, receiverKey, time.Now(), sessionID)
	return err
}

func (r *SessionRepository) Delete(ctx context.Context, sessionID uuid.UUID) error {
	query := `DELETE FROM sessions WHERE id = $1`
	_, err := r.pool.Exec(ctx, query, sessionID)
	return err
}

func (r *SessionRepository) HasSession(ctx context.Context, user1, user2 uuid.UUID) (bool, error) {
	query := `
		SELECT EXISTS(
			SELECT 1 FROM sessions
			WHERE (initiator_id = $1 AND receiver_id = $2) OR (initiator_id = $2 AND receiver_id = $1)
		)
	`

	var exists bool
	err := r.pool.QueryRow(ctx, query, user1, user2).Scan(&exists)
	return exists, err
}
