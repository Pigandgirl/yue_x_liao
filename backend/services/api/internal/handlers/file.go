package handlers

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"time"

	"yue_liao_api/internal/database"
	"yue_liao_api/internal/middleware"
	"yue_liao_api/internal/models"

	"github.com/gofiber/fiber/v2"
	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

const (
	ChunkSize       = 16 * 1024 * 1024
	MaxChunkSize    = 100 * 1024 * 1024
	MaxUploadSize   = 5 * 1024 * 1024 * 1024
)

type FileHandler struct {
	minioClient *minio.Client
	bucketName  string
	uploads     map[string]*UploadState
	userRepo    *database.UserRepository
	messageRepo *database.MessageRepository
}

type UploadState struct {
	UploadID    string
	UserID     uuid.UUID
	Filename   string
	FileSize   int64
	MimeType   string
	ChunkCount int
	Chunks     map[int]bool
	CreatedAt  time.Time
}

func NewFileHandler(endpoint, accessKey, secretKey, bucket string, useSSL bool, userRepo *database.UserRepository, messageRepo *database.MessageRepository) (*FileHandler, error) {
	client, err := minio.New(endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(accessKey, secretKey, ""),
		Secure: useSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to create minio client: %w", err)
	}

	h := &FileHandler{
		minioClient: client,
		bucketName:  bucket,
		uploads:    make(map[string]*UploadState),
		userRepo:    userRepo,
		messageRepo: messageRepo,
	}

	go h.cleanupExpiredUploads()

	return h, nil
}

func (h *FileHandler) cleanupExpiredUploads() {
	ticker := time.NewTicker(30 * time.Minute)
	for range ticker.C {
		now := time.Now()
		for id, state := range h.uploads {
			if now.Sub(state.CreatedAt) > 24*time.Hour {
				delete(h.uploads, id)
			}
		}
	}
}

func (h *FileHandler) InitUpload(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)

	var req struct {
		Filename   string `json:"filename"`
		FileSize   int64  `json:"file_size"`
		MimeType   string `json:"mime_type"`
		ChunkCount int    `json:"chunk_count"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	if req.Filename == "" {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "filename is required",
		})
	}

	if req.FileSize <= 0 || req.FileSize > MaxUploadSize {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": fmt.Sprintf("file size must be between 1 and %d bytes", MaxUploadSize),
		})
	}

	if req.ChunkCount <= 0 {
		calculatedChunks := int(req.FileSize/ChunkSize) + 1
		if int64(calculatedChunks) != (req.FileSize+int64(ChunkSize)-1)/int64(ChunkSize) {
			calculatedChunks++
		}
		req.ChunkCount = calculatedChunks
	}

	uploadID := uuid.New().String()

	state := &UploadState{
		UploadID:    uploadID,
		UserID:      userID,
		Filename:    req.Filename,
		FileSize:    req.FileSize,
		MimeType:    req.MimeType,
		ChunkCount: req.ChunkCount,
		Chunks:     make(map[int]bool),
		CreatedAt:  time.Now(),
	}

	h.uploads[uploadID] = state

	return c.JSON(fiber.Map{
		"upload_id":    uploadID,
		"chunk_size":   ChunkSize,
		"chunk_count":  req.ChunkCount,
		"expires_in":   86400,
	})
}

func (h *FileHandler) UploadChunk(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	uploadID := c.Params("uploadId")
	chunkIndex := c.Params("chunkIndex")

	var index int
	if _, err := fmt.Sscanf(chunkIndex, "%d", &index); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid chunk index",
		})
	}

	state, exists := h.uploads[uploadID]
	if !exists {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "upload not found",
		})
	}

	if state.UserID != userID {
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"error": "not authorized",
		})
	}

	if index < 0 || index >= state.ChunkCount {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "chunk index out of range",
		})
	}

	chunkData, err := io.ReadAll(c.Request().Body())
	if err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "failed to read chunk",
		})
	}

	if len(chunkData) > MaxChunkSize {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "chunk too large",
		})
	}

	objectPath := fmt.Sprintf("%s/%s/chunk_%d.enc", userID.String(), uploadID, index)
	reader := bytes.NewReader(chunkData)

	_, err = h.minioClient.PutObject(context.Background(), h.bucketName, objectPath, reader, int64(len(chunkData)), minio.PutObjectOptions{
		ContentType: "application/octet-stream",
	})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": fmt.Sprintf("failed to upload chunk: %v", err),
		})
	}

	state.Chunks[index] = true

	uploadedChunks := len(state.Chunks)
	return c.JSON(fiber.Map{
		"chunk_index":    index,
		"uploaded_chunks": uploadedChunks,
		"total_chunks":   state.ChunkCount,
		"complete":       uploadedChunks == state.ChunkCount,
	})
}

func (h *FileHandler) CompleteUpload(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	uploadID := c.Params("uploadId")
	recipientUsername := c.Query("to")

	var req struct {
		ChunkCount int    `json:"chunk_count"`
		Filename   string `json:"filename"`
		FileSize   int64  `json:"file_size"`
		MimeType   string `json:"mime_type"`
	}

	if err := c.BodyParser(&req); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid request body",
		})
	}

	state, exists := h.uploads[uploadID]
	if !exists {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "upload not found",
		})
	}

	if state.UserID != userID {
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"error": "not authorized",
		})
	}

	if len(state.Chunks) != state.ChunkCount {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error":           "not all chunks uploaded",
			"uploaded_chunks":  len(state.Chunks),
			"required_chunks": state.ChunkCount,
		})
	}

	var recipientID uuid.UUID
	if recipientUsername != "" {
		recipient, err := h.userRepo.GetByUsername(c.Context(), recipientUsername)
		if err != nil {
			return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
				"error": "recipient not found",
			})
		}
		recipientID = recipient.ID
	}

	filename := req.Filename
	if filename == "" {
		filename = state.Filename
	}

	mimeType := req.MimeType
	if mimeType == "" {
		mimeType = state.MimeType
	}

	fileSize := req.FileSize
	if fileSize == 0 {
		fileSize = state.FileSize
	}

	metadata := map[string]string{
		"upload_id":    uploadID,
		"filename":     filename,
		"file_size":    fmt.Sprintf("%d", fileSize),
		"mime_type":    mimeType,
		"chunk_count": fmt.Sprintf("%d", state.ChunkCount),
	}

	message := &models.Message{
		Sender:           userID,
		Receiver:         recipientID,
		EncryptedPayload: fmt.Sprintf(`{"type":"file","upload_id":"%s","filename":"%s","size":%d,"mime_type":"%s","chunk_count":%d}`, uploadID, filename, fileSize, mimeType, state.ChunkCount),
	}

	if err := h.messageRepo.Create(c.Context(), message); err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to create message",
		})
	}

	delete(h.uploads, uploadID)

	return c.JSON(fiber.Map{
		"message_id":    message.ID,
		"upload_id":    uploadID,
		"filename":     filename,
		"file_size":    fileSize,
		"chunk_count": state.ChunkCount,
	})
}

func (h *FileHandler) DownloadChunk(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	uploadID := c.Params("uploadId")
	chunkIndex := c.Params("chunkIndex")

	var index int
	if _, err := fmt.Sscanf(chunkIndex, "%d", &index); err != nil {
		return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
			"error": "invalid chunk index",
		})
	}

	objectPath := fmt.Sprintf("%s/%s/chunk_%d.enc", userID.String(), uploadID, index)

	stat, err := h.minioClient.StatObject(context.Background(), h.bucketName, objectPath, minio.StatObjectOptions{})
	if err != nil {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "chunk not found",
		})
	}

	reader, err := h.minioClient.GetObject(context.Background(), h.bucketName, objectPath, minio.GetObjectOptions{})
	if err != nil {
		return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
			"error": "failed to download chunk",
		})
	}
	defer reader.Close()

	c.Set("Content-Type", "application/octet-stream")
	c.Set("Content-Length", fmt.Sprintf("%d", stat.Size))
	c.Set("Content-Disposition", fmt.Sprintf("attachment; filename=chunk_%d.enc", index))

	return c.SendStream(reader)
}

func (h *FileHandler) GetUploadStatus(c *fiber.Ctx) error {
	uploadID := c.Params("uploadId")

	state, exists := h.uploads[uploadID]
	if !exists {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "upload not found or expired",
		})
	}

	return c.JSON(fiber.Map{
		"upload_id":      state.UploadID,
		"filename":       state.Filename,
		"file_size":     state.FileSize,
		"mime_type":     state.MimeType,
		"chunk_count":   state.ChunkCount,
		"uploaded_chunks": len(state.Chunks),
		"chunks":        state.Chunks,
		"created_at":    state.CreatedAt,
		"expires_in":    86400 - int(time.Since(state.CreatedAt).Seconds()),
	})
}

func (h *FileHandler) AbortUpload(c *fiber.Ctx) error {
	userID := middleware.GetUserID(c)
	uploadID := c.Params("uploadId")

	state, exists := h.uploads[uploadID]
	if !exists {
		return c.Status(fiber.StatusNotFound).JSON(fiber.Map{
			"error": "upload not found",
		})
	}

	if state.UserID != userID {
		return c.Status(fiber.StatusForbidden).JSON(fiber.Map{
			"error": "not authorized",
		})
	}

	for i := 0; i < state.ChunkCount; i++ {
		objectPath := fmt.Sprintf("%s/%s/chunk_%d.enc", userID.String(), uploadID, i)
		h.minioClient.RemoveObject(context.Background(), h.bucketName, objectPath, minio.RemoveObjectOptions{})
	}

	delete(h.uploads, uploadID)

	return c.JSON(fiber.Map{
		"message": "upload aborted",
	})
}
