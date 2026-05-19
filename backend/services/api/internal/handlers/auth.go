package handlers

import (
	"errors"

	"yue_liao_api/internal/database"
	"yue_liao_api/internal/middleware"
	"yue_liao_api/internal/models"

	"github.com/gofiber/fiber/v2"
	"golang.org/x/crypto/bcrypt"
)

type AuthHandler struct {
	userRepo  *database.UserRepository
	jwtMgr    *middleware.JWTManager
}

func NewAuthHandler(userRepo *database.UserRepository, jwtMgr *middleware.JWTManager) *AuthHandler {
	return &AuthHandler{
		userRepo: userRepo,
		jwtMgr:   jwtMgr,
	}
}

func (h *AuthHandler) Register(c *fiber.Ctx) error {
	var req models.RegisterRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	if len(req.Username) < 3 || len(req.Username) > 50 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "username must be between 3 and 50 characters",
		})
	}

	if len(req.Password) < 6 {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "password must be at least 6 characters",
		})
	}

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to hash password",
		})
	}

	user := &models.User{
		Username:     req.Username,
		PasswordHash: string(hashedPassword),
		Email:        req.Email,
	}

	if err := h.userRepo.Create(c.Context(), user); err != nil {
		if errors.Is(err, database.ErrUserAlreadyExists) {
			return c.Status(fiber.StatusConflict).JSON(fiber.Map{
				"error": "username or email already exists",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to create user",
		})
	}

	token, err := h.jwtMgr.GenerateToken(user.ID, user.Username)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to generate token",
		})
	}

	return c.Status(fiber.StatusCreated).JSON(models.RegisterResponse{
		User:      user,
		Token:     token,
		ExpiresIn: h.jwtMgr.GetExpiration(),
	})
}

func (h *AuthHandler) Login(c *fiber.Ctx) error {
	var req models.LoginRequest
	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	user, err := h.userRepo.GetByUsername(c.Context(), req.Username)
	if err != nil {
		if errors.Is(err, database.ErrUserNotFound) {
			return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
				"error": "invalid username or password",
			})
		}
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to authenticate",
		})
	}

	if err := bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password)); err != nil {
		return c.Status(fiber.StatusUnauthorized).JSON(fiber.Map{
			"error": "invalid username or password",
		})
	}

	token, err := h.jwtMgr.GenerateToken(user.ID, user.Username)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to generate token",
		})
	}

	return c.JSON(models.LoginResponse{
		User:      user,
		Token:     token,
		ExpiresIn: h.jwtMgr.GetExpiration(),
	})
}

func (h *AuthHandler) GetCurrentUser(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)

	user, err := h.userRepo.GetByID(c.Context(), userID)
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

	return c.JSON(user.ToResponse())
}

func (h *AuthHandler) UpdatePublicKey(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)

	var req struct {
		PublicKey string `json:"public_key"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	if err := h.userRepo.UpdatePublicKey(c.Context(), userID, req.PublicKey); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to update public key",
		})
	}

	return c.JSON(fiber.Map{
		"message": "public key updated successfully",
	})
}

func (h *AuthHandler) SearchUsers(c *fiber.Ctx) error {
	query := c.Query("q", "")
	limit := c.QueryInt("limit", 20)

	if limit > 100 {
		limit = 100
	}

	users, err := h.userRepo.Search(c.Context(), query, limit)
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to search users",
		})
	}

	var response []*models.UserResponse
	for _, user := range users {
		response = append(response, user.ToResponse())
	}

	return c.JSON(fiber.Map{
		"users": response,
	})
}
