package handler

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"tongxin-go/internal/middleware"
)

type UploadHandler struct {
	storagePath string
}

func NewUploadHandler(storagePath string) *UploadHandler {
	os.MkdirAll(storagePath, 0755)
	return &UploadHandler{storagePath: storagePath}
}

// POST /api/upload
func (h *UploadHandler) Upload(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	r.ParseMultipartForm(10 << 20) // 10 MB max

	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "file is required")
		return
	}
	defer file.Close()

	ext := filepath.Ext(header.Filename)
	allowed := map[string]bool{".jpg": true, ".jpeg": true, ".png": true, ".gif": true, ".webp": true, ".mp4": true, ".mp3": true}
	if !allowed[strings.ToLower(ext)] {
		writeError(w, http.StatusBadRequest, "unsupported file type")
		return
	}

	filename := fmt.Sprintf("%d_%s%s", time.Now().UnixMilli(), uid[:8], ext)
	destPath := filepath.Join(h.storagePath, filename)

	dst, err := os.Create(destPath)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save file")
		return
	}
	defer dst.Close()

	if _, err := io.Copy(dst, file); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to save file")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{
		"url":      "/uploads/" + filename,
		"filename": filename,
	})
}
