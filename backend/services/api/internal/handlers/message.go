package handlers

import (
	"encoding/json"
	"errors"
	"time"

	"yue_liao_api/internal/database"
	"yue_liao_api/internal/middleware"
	"yue_liao_api/internal/models"

	"github.com/gofiber/fiber/v2"
)

type MessageHandler struct {
	messageRepo *database.MessageRepository
	userRepo    *database.UserRepository
}

func NewMessageHandler(messageRepo *database.MessageRepository, userRepo *database.UserRepository) *MessageHandler {
	return &MessageHandler{
		messageRepo: messageRepo,
		userRepo:    userRepo,
	}
}

func (h *MessageHandler) GetMessages(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	username := c.Query("with")

	if username == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "query parameter 'with' is required",
		})
	}

	otherUser, err := h.userRepo.GetByUsername(c.Context(), username)
	if err != nil {
		if errors.Is(err, database.ErrUserNotFound) {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "user not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get user",
		})
	}

	limit := c.QueryInt("limit", 50)
	if limit > 100 {
		limit = 100
	}

	var after *time.Time
	afterStr := c.Query("after")
	if afterStr != "" {
		t, err := time.Parse(time.RFC3339, afterStr)
		if err == nil {
			after = &t
		}
	}

	messages, err := h.messageRepo.GetConversation(c.Context(), userID, otherUser.ID, limit, after)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get messages",
		})
	}

	var response []map[string]interface{}
	for _, msg := range messages {
		item := map[string]interface{}{
			"id":                msg.ID,
			"sender_id":         msg.Sender,
			"sender_username":   msg.SenderUsername,
			"receiver_id":       msg.Receiver,
			"receiver_username": msg.ReceiverUsername,
			"encrypted_payload": msg.EncryptedPayload,
			"is_read":          msg.IsRead,
			"created_at":       msg.CreatedAt,
		}

		if msg.Payload != "" {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(msg.EncryptedPayload), &payload); err == nil {
				item["payload"] = payload
			}
		}

		response = append(response, item)
	}

	if response == nil {
		response = []map[string]interface{}{}
	}

	return c.JSON(fiber.Map{
		"messages": response,
		"count":   len(response),
	})
}

func (h *MessageHandler) GetConversations(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)

	conversations, err := h.messageRepo.GetConversations(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get conversations",
		})
	}

	var response []map[string]interface{}
	for _, conv := range conversations {
		item := map[string]interface{}{
			"user_id":        conv.UserID,
			"username":       conv.Username,
			"unread_count":   conv.UnreadCount,
			"last_message_at": conv.LastMessageAt,
		}

		if conv.LastMessage != nil {
			lastMsg := map[string]interface{}{
				"id":                conv.LastMessage.ID,
				"sender_id":         conv.LastMessage.Sender,
				"encrypted_payload": conv.LastMessage.EncryptedPayload,
				"created_at":       conv.LastMessage.CreatedAt,
			}

			if conv.LastMessage.Payload != "" {
				var payload map[string]interface{}
				if err := json.Unmarshal([]byte(conv.LastMessage.EncryptedPayload), &payload); err == nil {
					lastMsg["payload"] = payload
				}
			}

			item["last_message"] = lastMsg
		}

		response = append(response, item)
	}

	if response == nil {
		response = []map[string]interface{}{}
	}

	return c.JSON(fiber.Map{
		"conversations": response,
		"count":         len(response),
	})
}

func (h *MessageHandler) MarkAsRead(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)

	var req struct {
		MessageID string `json:"message_id"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	if req.MessageID == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "message_id is required",
		})
	}

	if err := h.messageRepo.MarkAsRead(c.Context(), userID, mustParseUUID(req.MessageID)); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to mark message as read",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
	})
}

func (h *MessageHandler) MarkConversationAsRead(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	username := c.Params("username")

	if username == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "username is required",
		})
	}

	otherUser, err := h.userRepo.GetByUsername(c.Context(), username)
	if err != nil {
		if errors.Is(err, database.ErrUserNotFound) {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "user not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get user",
		})
	}

	if err := h.messageRepo.MarkConversationAsRead(c.Context(), userID, otherUser.ID); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to mark conversation as read",
		})
	}

	return c.JSON(fiber.Map{
		"success": true,
	})
}

func (h *MessageHandler) GetUnreadCount(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	username := c.Query("with")

	if username != "" {
		otherUser, err := h.userRepo.GetByUsername(c.Context(), username)
		if err != nil {
			if errors.Is(err, database.ErrUserNotFound) {
				return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
					"error": "user not found",
				})
			}
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "failed to get user",
			})
		}

		count, err := h.messageRepo.CountUnread(c.Context(), userID, otherUser.ID)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "failed to get unread count",
			})
		}

		return c.JSON(fiber.Map{
			"username":    username,
			"unread_count": count,
		})
	}

	messages, err := h.messageRepo.GetUnreadByReceiver(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get unread messages",
		})
	}

	unreadByUser := make(map[string]int)
	for _, msg := range messages {
		unreadByUser[msg.SenderUsername]++
	}

	return c.JSON(fiber.Map{
		"total_unread": len(messages),
		"unread_by_user": unreadByUser,
	})
}

func mustParseUUID(s string) (uuid [16]byte) {
	return uuid{}
}
