package handler

import (
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type FeedbackHandler struct {
	repo *repository.FeedbackRepo
}

func NewFeedbackHandler(repo *repository.FeedbackRepo) *FeedbackHandler {
	return &FeedbackHandler{repo: repo}
}

// POST /api/feedbacks — 用户提交投诉建议
func (h *FeedbackHandler) Create(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	var req model.CreateFeedbackRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if strings.TrimSpace(req.Content) == "" {
		writeError(w, http.StatusBadRequest, "content is required")
		return
	}
	if req.Category == "" {
		req.Category = "suggestion"
	}
	if req.ImageURLs == nil {
		req.ImageURLs = []string{}
	}

	fb := &model.Feedback{
		UserID:    uid,
		Content:   req.Content,
		ImageURLs: req.ImageURLs,
		Category:  req.Category,
	}
	if err := h.repo.Create(r.Context(), fb); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create feedback")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"status": "ok"})
}

// GET /api/feedbacks — 用户查看自己的投诉建议
func (h *FeedbackHandler) ListMy(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 20
	}

	list, total, err := h.repo.ListByUser(r.Context(), uid, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list feedbacks")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"feedbacks": list, "total": total})
}

// GET /api/feedbacks/unread-count — 用户的未读回复数量（给 Profile 红点用）
func (h *FeedbackHandler) UnreadCount(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	n, err := h.repo.CountUserUnread(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to count unread")
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"count": n})
}

// GET /api/feedbacks/{id} — 用户查看自己一条反馈详情
func (h *FeedbackHandler) GetOne(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing feedback id")
		return
	}
	fb, err := h.repo.GetByIDForUser(r.Context(), id, uid)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "feedback not found")
			return
		}
		writeError(w, http.StatusInternalServerError, "failed to load feedback")
		return
	}
	writeJSON(w, http.StatusOK, fb)
}

// POST /api/feedbacks/{id}/read — 用户把某条反馈标记为已读，清掉未读红点
func (h *FeedbackHandler) MarkRead(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "unauthorized")
		return
	}
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing feedback id")
		return
	}
	if err := h.repo.MarkRead(r.Context(), id, uid); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to mark read")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// GET /api/admin/feedbacks — 管理员查看所有投诉建议
func (h *FeedbackHandler) AdminList(w http.ResponseWriter, r *http.Request) {
	status := r.URL.Query().Get("status")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 20
	}

	list, total, err := h.repo.ListAll(r.Context(), status, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list feedbacks")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"feedbacks": list, "total": total})
}

// PUT /api/admin/feedbacks/{id} — 管理员回复投诉建议
func (h *FeedbackHandler) AdminReply(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "missing feedback id")
		return
	}

	uid := middleware.GetUserUID(r.Context())

	var req model.AdminReplyRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Status == "" {
		req.Status = "resolved"
	}

	if err := h.repo.AdminReply(r.Context(), id, req.Reply, uid, req.Status); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to reply")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
