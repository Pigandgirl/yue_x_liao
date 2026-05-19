package handlers

import (
	"context"
	"encoding/json"
	"log"

	"yue_liao_api/internal/middleware"
	"yue_liao_api/internal/models"
	"yue_liao_api/internal/websocket"

	"github.com/gofiber/fiber/v2"
	ws "github.com/gofiber/contrib/websocket"
	"github.com/google/uuid"
)

type WebSocketHandler struct {
	hub    *websocket.Hub
	jwtMgr *middleware.JWTManager
}

func NewWebSocketHandler(hub *websocket.Hub, jwtMgr *middleware.JWTManager) *WebSocketHandler {
	return &WebSocketHandler{
		hub:    hub,
		jwtMgr: jwtMgr,
	}
}

func (h *WebSocketHandler) UpgradeCheck(c *fiber.Ctx) bool {
	if ws.IsWebSocketUpgrade(c) {
		token := c.Query("token")
		if token == "" {
			return false
		}

		claims, err := h.jwtMgr.ValidateToken(token)
		if err != nil {
			return false
		}

		c.Locals("user_id", claims.UserID)
		c.Locals("username", claims.Username)
		return true
	}
	return false
}

func (h *WebSocketHandler) HandleWebSocket(c *ws.Conn) {
	userID, ok := c.Locals("user_id").(uuid.UUID)
	if !ok {
		log.Println("Invalid user ID in WebSocket connection")
		c.Close()
		return
	}

	username, ok := c.Locals("username").(string)
	if !ok {
		log.Println("Invalid username in WebSocket connection")
		c.Close()
		return
	}

	client := &websocket.Client{
		hub:      h.hub,
		conn:     c,
		send:     make(chan []byte, 256),
		userID:   userID,
		username: username,
	}

	h.hub.Register(client)

	go client.WritePump()
	go func() {
		if err := h.sendOfflineMessages(context.Background(), client); err != nil {
			log.Printf("Failed to send offline messages: %v", err)
		}
	}()
	client.ReadPump()
}

func (h *WebSocketHandler) sendOfflineMessages(ctx context.Context, client *websocket.Client) error {
	messages, err := h.hub.GetUnreadMessages(ctx, client.userID)
	if err != nil {
		return err
	}

	if len(messages) == 0 {
		return nil
	}

	for _, msg := range messages {
		sender, err := h.hub.messageRepo.GetByID(ctx, msg.Sender)
		if err != nil {
			continue
		}

		wsMsg := &models.WebSocketMessage{
			Type: "offline_message",
			From: sender.Username,
			Message: &models.Message{
				ID:               msg.ID,
				Sender:           msg.Sender,
				Receiver:         msg.Receiver,
				EncryptedPayload: msg.EncryptedPayload,
				IsRead:          msg.IsRead,
				CreatedAt:       msg.CreatedAt,
			},
		}

		if msg.Payload != "" {
			var payload map[string]interface{}
			if err := json.Unmarshal([]byte(msg.EncryptedPayload), &payload); err == nil {
				wsMsg.Payload = payload
			}
		}

		responseBytes, err := json.Marshal(wsMsg)
		if err != nil {
			continue
		}

		select {
		case client.send <- responseBytes:
		default:
			return nil
		}
	}

	return nil
}

func (h *WebSocketHandler) GetOnlineUsers(c *fiber.Ctx) error {
	users := h.hub.GetOnlineUsers()
	return c.JSON(fiber.Map{
		"online_users": users,
		"count":       len(users),
	})
}

func (h *WebSocketHandler) CheckUserOnline(c *fiber.Ctx) error {
	username := c.Params("username")
	if username == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "username is required",
		})
	}

	isOnline := h.hub.IsUserOnline(username)
	return c.JSON(fiber.Map{
		"username":  username,
		"is_online": isOnline,
	})
}
