package websocket

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"sync"
	"time"

	"yue_liao_api/internal/database"
	"yue_liao_api/internal/models"

	"github.com/google/uuid"
	"github.com/gorilla/websocket"
)

const (
	writeWait      = 10 * time.Second
	pongWait       = 60 * time.Second
	pingPeriod     = (pongWait * 9) / 10
	maxMessageSize = 512 * 1024
)

type Client struct {
	hub      *Hub
	conn     *websocket.Conn
	send     chan []byte
	userID   uuid.UUID
	username string
}

type Hub struct {
	clients      map[uuid.UUID]*Client
	userClients  map[string]*Client
	register     chan *Client
	unregister   chan *Client
	broadcast    chan *BroadcastMessage
	mutex        sync.RWMutex
	userRepo     *database.UserRepository
	messageRepo  *database.MessageRepository
	redisDB      *database.RedisDB
}

type BroadcastMessage struct {
	To      uuid.UUID
	From    uuid.UUID
	Message []byte
}

func NewHub(userRepo *database.UserRepository, messageRepo *database.MessageRepository, redisDB *database.RedisDB) *Hub {
	return &Hub{
		clients:     make(map[uuid.UUID]*Client),
		userClients: make(map[string]*Client),
		register:    make(chan *Client),
		unregister:  make(chan *Client),
		broadcast:   make(chan *BroadcastMessage, 256),
		userRepo:    userRepo,
		messageRepo: messageRepo,
		redisDB:     redisDB,
	}
}

func (h *Hub) Run(ctx context.Context) {
	for {
		select {
		case client := <-h.register:
			h.mutex.Lock()
			h.clients[client.userID] = client
			h.userClients[client.username] = client
			h.mutex.Unlock()

			if h.redisDB != nil {
				if err := h.redisDB.SetUserOnline(ctx, client.userID.String(), client.userID.String()); err != nil {
					log.Printf("Failed to set user online in Redis: %v", err)
				}
			}

			log.Printf("Client connected: user=%s, id=%s", client.username, client.userID)

		case client := <-h.unregister:
			h.mutex.Lock()
			if _, ok := h.clients[client.userID]; ok {
				delete(h.clients, client.userID)
				delete(h.userClients, client.username)
				close(client.send)

				if h.redisDB != nil {
					if err := h.redisDB.SetUserOffline(ctx, client.userID.String()); err != nil {
						log.Printf("Failed to set user offline in Redis: %v", err)
					}
				}

				log.Printf("Client disconnected: user=%s, id=%s", client.username, client.userID)
			}
			h.mutex.Unlock()

		case message := <-h.broadcast:
			h.mutex.RLock()
			if client, ok := h.clients[message.To]; ok {
				select {
				case client.send <- message.Message:
				default:
					close(client.send)
					delete(h.clients, message.To)
					delete(h.userClients, client.username)
				}
			}
			h.mutex.RUnlock()

		case <-ctx.Done():
			return
		}
	}
}

func (h *Hub) Register(client *Client) {
	h.register <- client
}

func (h *Hub) Unregister(client *Client) {
	h.unregister <- client
}

func (h *Hub) SendToUser(username string, message []byte) bool {
	h.mutex.RLock()
	defer h.mutex.RUnlock()

	if client, ok := h.userClients[username]; ok {
		select {
		case client.send <- message:
			return true
		default:
			return false
		}
	}
	return false
}

func (h *Hub) IsUserOnline(username string) bool {
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	_, ok := h.userClients[username]
	return ok
}

func (h *Hub) GetOnlineUsers() []string {
	h.mutex.RLock()
	defer h.mutex.RUnlock()

	users := make([]string, 0, len(h.userClients))
	for username := range h.userClients {
		users = append(users, username)
	}
	return users
}

func (h *Hub) SendMessage(ctx context.Context, from uuid.UUID, toUsername string, wsMsg *models.WebSocketMessage) error {
	toUser, err := h.userRepo.GetByUsername(ctx, toUsername)
	if err != nil {
		return errors.New("recipient not found")
	}

	payloadBytes, err := json.Marshal(wsMsg.Payload)
	if err != nil {
		return errors.New("failed to marshal payload")
	}

	msg := &models.Message{
		Sender:           from,
		Receiver:         toUser.ID,
		EncryptedPayload: string(payloadBytes),
		IsRead:          false,
	}

	if err := h.messageRepo.Create(ctx, msg); err != nil {
		return errors.New("failed to store message")
	}

	msg.SenderUsername = wsMsg.From

	responseMsg := &models.WebSocketMessage{
		Type:    wsMsg.Type,
		From:    wsMsg.From,
		Payload: wsMsg.Payload,
		Message: msg,
	}

	responseBytes, err := json.Marshal(responseMsg)
	if err != nil {
		return errors.New("failed to marshal response")
	}

	delivered := h.SendToUser(toUsername, responseBytes)

	if !delivered {
		log.Printf("User %s is offline, message queued", toUsername)
	}

	return nil
}

func (h *Hub) GetUnreadMessages(ctx context.Context, userID uuid.UUID) ([]*models.Message, error) {
	messages, err := h.messageRepo.GetUnreadByReceiver(ctx, userID)
	if err != nil {
		return nil, err
	}

	if err := h.messageRepo.MarkConversationAsRead(ctx, userID, messages[0].Sender); err != nil {
		log.Printf("Failed to mark messages as read: %v", err)
	}

	return messages, nil
}

func (c *Client) ReadPump() {
	defer func() {
		c.hub.Unregister(c)
		c.conn.Close()
	}()

	c.conn.SetReadLimit(maxMessageSize)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})

	for {
		_, message, err := c.conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				log.Printf("WebSocket error: %v", err)
			}
			break
		}

		c.handleMessage(message)
	}
}

func (c *Client) WritePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.conn.Close()
	}()

	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}

			w, err := c.conn.NextWriter(websocket.TextMessage)
			if err != nil {
				return
			}
			w.Write(message)

			n := len(c.send)
			for i := 0; i < n; i++ {
				w.Write([]byte{'\n'})
				w.Write(<-c.send)
			}

			if err := w.Close(); err != nil {
				return
			}

		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}

func (c *Client) handleMessage(message []byte) {
	var wsMsg models.WebSocketMessage
	if err := json.Unmarshal(message, &wsMsg); err != nil {
		c.sendError("invalid message format")
		return
	}

	ctx := context.Background()

	switch wsMsg.Type {
	case "chat":
		if wsMsg.To == "" {
			c.sendError("missing recipient")
			return
		}
		if err := c.hub.SendMessage(ctx, c.userID, wsMsg.To, &wsMsg); err != nil {
			c.sendError(err.Error())
			return
		}

		response := &models.WebSocketMessage{
			Type:    "message_sent",
			Message: wsMsg.Message,
		}
		responseBytes, _ := json.Marshal(response)
		c.send <- responseBytes

	case "typing":
		if wsMsg.To != "" {
			wsMsg.From = c.username
			typingBytes, _ := json.Marshal(wsMsg)
			c.hub.SendToUser(wsMsg.To, typingBytes)
		}

	case "read":
		if wsMsg.Message != nil {
			if err := c.hub.messageRepo.MarkAsRead(ctx, c.userID, wsMsg.Message.ID); err != nil {
				log.Printf("Failed to mark message as read: %v", err)
			}
		}

	case "ping":
		response := &models.WebSocketMessage{Type: "pong"}
		responseBytes, _ := json.Marshal(response)
		c.send <- responseBytes

	default:
		c.sendError("unknown message type")
	}
}

func (c *Client) sendError(message string) {
	response := &models.WebSocketMessage{
		Type:  "error",
		Error: message,
	}
	responseBytes, _ := json.Marshal(response)
	c.send <- responseBytes
}
