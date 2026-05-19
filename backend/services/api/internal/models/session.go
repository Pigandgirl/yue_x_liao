package models

import (
	"time"

	"github.com/google/uuid"
)

type Session struct {
	ID              uuid.UUID `json:"id"`
	InitiatorID     uuid.UUID `json:"initiator_id"`
	ReceiverID      uuid.UUID `json:"receiver_id"`
	InitiatorKey    string    `json:"initiator_key"`
	ReceiverKey     string    `json:"receiver_key,omitempty"`
	SharedSecret    string    `json:"-"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}

type InitSessionRequest struct {
	RecipientUsername string `json:"recipient_username" validate:"required"`
	EphemeralKey     string `json:"ephemeral_key" validate:"required"`
}

type InitSessionResponse struct {
	SessionID      string `json:"session_id"`
	RecipientKey   string `json:"recipient_key"`
	InitiatorKey   string `json:"initiator_key"`
}

type SessionStatus struct {
	SessionID   string `json:"session_id"`
	RecipientID string `json:"recipient_id"`
	IsEstablished bool  `json:"is_established"`
}

type EncryptedPayload struct {
	Nonce      string `json:"nonce"`
	Ciphertext string `json:"ciphertext"`
	Tag        string `json:"tag"`
}
