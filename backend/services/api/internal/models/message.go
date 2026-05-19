package models

import (
	"time"

	"github.com/google/uuid"
)

type Message struct {
	ID               uuid.UUID `json:"id"`
	Sender           uuid.UUID `json:"sender_id"`
	SenderUsername   string    `json:"sender_username,omitempty"`
	Receiver         uuid.UUID `json:"receiver_id"`
	ReceiverUsername string    `json:"receiver_username,omitempty"`
	EncryptedPayload string    `json:"encrypted_payload"`
	Payload          string    `json:"payload,omitempty"`
	IsRead           bool      `json:"is_read"`
	CreatedAt        time.Time `json:"created_at"`
}

type Conversation struct {
	UserID           uuid.UUID `json:"user_id"`
	Username         string    `json:"username"`
	LastMessage      *Message  `json:"last_message,omitempty"`
	UnreadCount      int       `json:"unread_count"`
	LastMessageAt    time.Time `json:"last_message_at"`
}

type WebSocketMessage struct {
	Type    string                 `json:"type"`
	To      string                 `json:"to,omitempty"`
	From    string                 `json:"from,omitempty"`
	Payload map[string]interface{} `json:"payload,omitempty"`
	Message *Message               `json:"message,omitempty"`
	Error   string                 `json:"error,omitempty"`
}

type ChatPayload struct {
	Text string `json:"text"`
}

type SendMessageRequest struct {
	To      string                 `json:"to" validate:"required"`
	Type    string                 `json:"type" validate:"required,oneof=chat file image voice video"`
	Payload map[string]interface{} `json:"payload" validate:"required"`
}

type SendMessageResponse struct {
	Message   *Message `json:"message"`
	Delivered bool     `json:"delivered"`
}

type GetMessagesRequest struct {
	With string `query:"with" validate:"required"`
	Limit int    `query:"limit" validate:"min=1,max=100"`
	After string `query:"after"`
}

type GetConversationsResponse struct {
	Conversations []*Conversation `json:"conversations"`
}

type TypingStatus struct {
	From    string `json:"from"`
	To      string `json:"to"`
	Typing  bool   `json:"typing"`
}
