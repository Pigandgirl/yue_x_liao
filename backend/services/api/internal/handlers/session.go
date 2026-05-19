package handlers

import (
	"errors"

	"yue_liao_api/internal/database"
	"yue_liao_api/internal/middleware"
	"yue_liao_api/internal/models"

	"github.com/gofiber/fiber/v2"
)

type SessionHandler struct {
	sessionRepo *database.SessionRepository
	userRepo    *database.UserRepository
}

func NewSessionHandler(sessionRepo *database.SessionRepository, userRepo *database.UserRepository) *SessionHandler {
	return &SessionHandler{
		sessionRepo: sessionRepo,
		userRepo:    userRepo,
	}
}

func (h *SessionHandler) InitSession(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)

	var req models.InitSessionRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	if req.RecipientUsername == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "recipient_username is required",
		})
	}

	if req.EphemeralKey == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "ephemeral_key is required",
		})
	}

	receiver, err := h.userRepo.GetByUsername(c.Context(), req.RecipientUsername)
	if err != nil {
		if errors.Is(err, database.ErrUserNotFound) {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "recipient not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get recipient",
		})
	}

	if receiver.ID == userID {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "cannot create session with yourself",
		})
	}

	hasSession, err := h.sessionRepo.HasSession(c.Context(), userID, receiver.ID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to check existing session",
		})
	}

	if hasSession {
		existingSession, err := h.sessionRepo.GetByUsers(c.Context(), userID, receiver.ID)
		if err != nil {
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "failed to get existing session",
			})
		}

		return c.JSON(models.InitSessionResponse{
			SessionID:     existingSession.ID.String(),
			RecipientKey:  receiver.PublicKey,
			InitiatorKey:  existingSession.InitiatorKey,
		})
	}

	currentUser, err := h.userRepo.GetByID(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get current user",
		})
	}

	session := &models.Session{
		InitiatorID:  userID,
		ReceiverID:   receiver.ID,
		InitiatorKey: req.EphemeralKey,
	}

	if err := h.sessionRepo.Create(c.Context(), session); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to create session",
		})
	}

	return c.Status(fiber.StatusCreated).JSON(models.InitSessionResponse{
		SessionID:     session.ID.String(),
		RecipientKey:  receiver.PublicKey,
		InitiatorKey:  req.EphemeralKey,
	})
}

func (h *SessionHandler) CompleteSession(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)

	var req struct {
		SessionID    string `json:"session_id"`
		ResponseKey string `json:"response_key"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	session, err := h.sessionRepo.GetByID(c.Context(), mustParseUUID(req.SessionID))
	if err != nil {
		if errors.Is(err, database.ErrSessionNotFound) {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "session not found",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get session",
		})
	}

	if session.ReceiverID != userID {
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"error": "not authorized to complete this session",
		})
	}

	if session.ReceiverKey != "" {
		return c.JSON(fiber.Map{
			"message": "session already completed",
			"session_id": session.ID.String(),
		})
	}

	if err := h.sessionRepo.UpdateReceiverKey(c.Context(), session.ID, req.ResponseKey); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to complete session",
		})
	}

	return c.JSON(fiber.Map{
		"message":   "session completed successfully",
		"session_id": session.ID.String(),
	})
}

func (h *SessionHandler) GetSession(c *fiber.Ctx) error {
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

	session, err := h.sessionRepo.GetByUsers(c.Context(), userID, otherUser.ID)
	if err != nil {
		if errors.Is(err, database.ErrSessionNotFound) {
			return c.JSON(fiber.Map{
				"session_id":     nil,
				"is_established": false,
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get session",
		})
	}

	return c.JSON(models.SessionStatus{
		SessionID:     session.ID.String(),
		RecipientID:  otherUser.ID.String(),
		IsEstablished: session.ReceiverKey != "",
	})
}

func (h *SessionHandler) GetUserSessions(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)

	sessions, err := h.sessionRepo.GetUserSessions(c.Context(), userID)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to get sessions",
		})
	}

	var response []map[string]interface{}
	for _, session := range sessions {
		var otherUserID string
		var otherUsername string

		if session.InitiatorID == userID {
			otherUserID = session.ReceiverID.String()
			otherUser, err := h.userRepo.GetByID(c.Context(), session.ReceiverID)
			if err == nil {
				otherUsername = otherUser.Username
			}
		} else {
			otherUserID = session.InitiatorID.String()
			otherUser, err := h.userRepo.GetByID(c.Context(), session.InitiatorID)
			if err == nil {
				otherUsername = otherUser.Username
			}
		}

		response = append(response, map[string]interface{}{
			"session_id":     session.ID.String(),
			"other_user_id":   otherUserID,
			"other_username":   otherUsername,
			"is_established": session.ReceiverKey != "",
			"created_at":     session.CreatedAt,
		})
	}

	if response == nil {
		response = []map[string]interface{}{}
	}

	return c.JSON(fiber.Map{
		"sessions": response,
		"count":   len(response),
	})
}

func mustParseUUID(s string) (uuid [16]byte) {
	return uuid
}
