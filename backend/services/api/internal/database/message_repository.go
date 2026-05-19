package database

import (
	"context"
	"time"

	"yue_liao_api/internal/models"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

type MessageRepository struct {
	pool *pgxpool.Pool
}

func NewMessageRepository(db *PostgresDB) *MessageRepository {
	return &MessageRepository{pool: db.Pool}
}

func (r *MessageRepository) Create(ctx context.Context, msg *models.Message) error {
	return r.CreateWithSession(ctx, msg, nil)
}

func (r *MessageRepository) CreateWithSession(ctx context.Context, msg *models.Message, sessionID *uuid.UUID) error {
	query := `
		INSERT INTO messages (id, sender, receiver, session_id, encrypted_payload, is_read, created_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
	`

	msg.ID = uuid.New()
	msg.CreatedAt = time.Now()

	_, err := r.pool.Exec(ctx, query,
		msg.ID,
		msg.Sender,
		msg.Receiver,
		sessionID,
		msg.EncryptedPayload,
		msg.IsRead,
		msg.CreatedAt,
	)

	return err
}

func (r *MessageRepository) GetByID(ctx context.Context, id uuid.UUID) (*models.Message, error) {
	query := `
		SELECT m.id, m.sender, m.receiver, m.encrypted_payload, m.is_read, m.created_at,
			   s.username, r.username
		FROM messages m
		JOIN users s ON m.sender = s.id
		JOIN users r ON m.receiver = r.id
		WHERE m.id = $1
	`

	msg := &models.Message{}
	err := r.pool.QueryRow(ctx, query, id).Scan(
		&msg.ID,
		&msg.Sender,
		&msg.Receiver,
		&msg.EncryptedPayload,
		&msg.IsRead,
		&msg.CreatedAt,
		&msg.SenderUsername,
		&msg.ReceiverUsername,
	)

	if err != nil {
		return nil, err
	}

	return msg, nil
}

func (r *MessageRepository) GetConversation(ctx context.Context, userID, otherUserID uuid.UUID, limit int, after *time.Time) ([]*models.Message, error) {
	query := `
		SELECT m.id, m.sender, m.receiver, m.encrypted_payload, m.is_read, m.created_at,
			   s.username, r.username
		FROM messages m
		JOIN users s ON m.sender = s.id
		JOIN users r ON m.receiver = r.id
		WHERE (m.sender = $1 AND m.receiver = $2) OR (m.sender = $2 AND m.receiver = $1)
	`

	args := []interface{}{userID, otherUserID}

	if after != nil {
		query += " AND m.created_at < $3"
		args = append(args, *after)
	}

	query += " ORDER BY m.created_at DESC LIMIT $" + string(rune('0'+len(args)+1))
	
	switch len(args) {
	case 2:
		query += " 2"
	case 3:
		query += " 3"
	}

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []*models.Message
	for rows.Next() {
		msg := &models.Message{}
		err := rows.Scan(
			&msg.ID,
			&msg.Sender,
			&msg.Receiver,
			&msg.EncryptedPayload,
			&msg.IsRead,
			&msg.CreatedAt,
			&msg.SenderUsername,
			&msg.ReceiverUsername,
		)
		if err != nil {
			return nil, err
		}
		messages = append(messages, msg)
	}

	return messages, rows.Err()
}

func (r *MessageRepository) GetUnreadByReceiver(ctx context.Context, receiverID uuid.UUID) ([]*models.Message, error) {
	query := `
		SELECT m.id, m.sender, m.receiver, m.encrypted_payload, m.is_read, m.created_at,
			   s.username, r.username
		FROM messages m
		JOIN users s ON m.sender = s.id
		JOIN users r ON m.receiver = r.id
		WHERE m.receiver = $1 AND m.is_read = FALSE
		ORDER BY m.created_at ASC
	`

	rows, err := r.pool.Query(ctx, query, receiverID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var messages []*models.Message
	for rows.Next() {
		msg := &models.Message{}
		err := rows.Scan(
			&msg.ID,
			&msg.Sender,
			&msg.Receiver,
			&msg.EncryptedPayload,
			&msg.IsRead,
			&msg.CreatedAt,
			&msg.SenderUsername,
			&msg.ReceiverUsername,
		)
		if err != nil {
			return nil, err
		}
		messages = append(messages, msg)
	}

	return messages, rows.Err()
}

func (r *MessageRepository) MarkAsRead(ctx context.Context, receiverID, messageID uuid.UUID) error {
	query := `
		UPDATE messages
		SET is_read = TRUE
		WHERE id = $1 AND receiver = $2
	`

	_, err := r.pool.Exec(ctx, query, messageID, receiverID)
	return err
}

func (r *MessageRepository) MarkConversationAsRead(ctx context.Context, userID, otherUserID uuid.UUID) error {
	query := `
		UPDATE messages
		SET is_read = TRUE
		WHERE sender = $1 AND receiver = $2 AND is_read = FALSE
	`

	_, err := r.pool.Exec(ctx, query, otherUserID, userID)
	return err
}

func (r *MessageRepository) GetConversations(ctx context.Context, userID uuid.UUID) ([]*models.Conversation, error) {
	query := `
		WITH latest_messages AS (
			SELECT DISTINCT ON (LEAST(sender, receiver), GREATEST(sender, receiver))
				id, sender, receiver, encrypted_payload, is_read, created_at,
				CASE WHEN sender = $1 THEN receiver ELSE sender END as other_user,
				CASE WHEN is_read = FALSE AND receiver = $1 THEN 1 ELSE 0 END as unread
			FROM messages
			WHERE sender = $1 OR receiver = $1
			ORDER BY LEAST(sender, receiver), GREATEST(sender, receiver), created_at DESC
		)
		SELECT 
			u.id, u.username,
			lm.id, lm.sender, lm.receiver, lm.encrypted_payload, lm.is_read, lm.created_at,
			COALESCE(SUM(lm2.unread), 0)::int as unread_count
		FROM latest_messages lm
		JOIN users u ON lm.other_user = u.id
		LEFT JOIN (
			SELECT DISTINCT ON (LEAST(sender, receiver), GREATEST(sender, receiver))
				*
			FROM messages
			WHERE sender = $1 OR receiver = $1
			ORDER BY LEAST(sender, receiver), GREATEST(sender, receiver), created_at DESC
		) lm2 ON lm.id = lm2.id AND lm2.is_read = FALSE AND lm2.receiver = $1
		GROUP BY u.id, u.username, lm.id, lm.sender, lm.receiver, lm.encrypted_payload, lm.is_read, lm.created_at
		ORDER BY lm.created_at DESC
	`

	rows, err := r.pool.Query(ctx, query, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var conversations []*models.Conversation
	for rows.Next() {
		conv := &models.Conversation{UserID: userID}
		msg := &models.Message{}

		err := rows.Scan(
			&conv.UserID,
			&conv.Username,
			&msg.ID,
			&msg.Sender,
			&msg.Receiver,
			&msg.EncryptedPayload,
			&msg.IsRead,
			&msg.CreatedAt,
			&conv.UnreadCount,
		)
		if err != nil {
			return nil, err
		}

		conv.UserID = userID
		conv.LastMessage = msg
		conv.LastMessageAt = msg.CreatedAt
		conversations = append(conversations, conv)
	}

	return conversations, rows.Err()
}

func (r *MessageRepository) CountUnread(ctx context.Context, userID, otherUserID uuid.UUID) (int, error) {
	query := `
		SELECT COUNT(*) FROM messages
		WHERE sender = $1 AND receiver = $2 AND is_read = FALSE
	`

	var count int
	err := r.pool.QueryRow(ctx, query, otherUserID, userID).Scan(&count)
	return count, err
}
