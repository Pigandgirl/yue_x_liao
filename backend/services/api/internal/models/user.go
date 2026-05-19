package models

import (
	"time"

	"github.com/google/uuid"
)

type User struct {
	ID           uuid.UUID `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"`
	PublicKey    *string   `json:"public_key,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type RegisterRequest struct {
	Username string `json:"username" validate:"required,min=3,max=50"`
	Password string `json:"password" validate:"required,min=6"`
	Email    string `json:"email" validate:"required,email"`
}

type LoginRequest struct {
	Username string `json:"username" validate:"required"`
	Password string `json:"password" validate:"required"`
}

type RegisterResponse struct {
	User      *User  `json:"user"`
	Token     string `json:"token"`
	ExpiresIn int64  `json:"expires_in"`
}

type LoginResponse struct {
	User      *User  `json:"user"`
	Token     string `json:"token"`
	ExpiresIn int64  `json:"expires_in"`
}

type UserResponse struct {
	ID        uuid.UUID `json:"id"`
	Username  string    `json:"username"`
	PublicKey *string    `json:"public_key,omitempty"`
	CreatedAt time.Time `json:"created_at"`
}

func (u *User) ToResponse() *UserResponse {
	return &UserResponse{
		ID:        u.ID,
		Username:  u.Username,
		PublicKey: u.PublicKey,
		CreatedAt: u.CreatedAt,
	}
}
