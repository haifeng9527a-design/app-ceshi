package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type AdminHandler struct {
	userSvc    *service.UserService
	teacherSvc *service.TeacherService
}

func NewAdminHandler(userSvc *service.UserService, teacherSvc *service.TeacherService) *AdminHandler {
	return &AdminHandler{userSvc: userSvc, teacherSvc: teacherSvc}
}

// GET /api/admin/users
func (h *AdminHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	// TODO: verify admin role

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 20
	}

	users, total, err := h.userSvc.ListAll(r.Context(), limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list users")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"users": users, "total": total})
}

// GET /api/admin/teachers/pending
func (h *AdminHandler) PendingTeachers(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 20
	}

	teachers, err := h.teacherSvc.ListPending(r.Context(), limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list pending teachers")
		return
	}
	if teachers == nil {
		teachers = []model.Teacher{}
	}

	writeJSON(w, http.StatusOK, teachers)
}

// POST /api/admin/teachers/{id}/approve
func (h *AdminHandler) ApproveTeacher(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	teacherID := r.PathValue("id")
	if err := h.teacherSvc.Approve(r.Context(), teacherID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to approve")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "approved"})
}

// POST /api/admin/teachers/{id}/reject
func (h *AdminHandler) RejectTeacher(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	teacherID := r.PathValue("id")
	if err := h.teacherSvc.Reject(r.Context(), teacherID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to reject")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "rejected"})
}

// GET /api/admin/stats
func (h *AdminHandler) Stats(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	// Return basic stats placeholder
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ok",
	})
}

// GET /api/announcements
func (h *AdminHandler) ListAnnouncements(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, []any{})
}

// POST /api/admin/announcements
func (h *AdminHandler) CreateAnnouncement(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body struct {
		Title   string `json:"title"`
		Content string `json:"content"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"status": "created"})
}

// GET /api/admin/reports
func (h *AdminHandler) ListReports(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	writeJSON(w, http.StatusOK, []any{})
}
