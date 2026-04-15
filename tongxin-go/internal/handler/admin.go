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
	traderSvc  *service.TraderService
}

func NewAdminHandler(userSvc *service.UserService, teacherSvc *service.TeacherService, traderSvc *service.TraderService) *AdminHandler {
	return &AdminHandler{userSvc: userSvc, teacherSvc: teacherSvc, traderSvc: traderSvc}
}

// GET /api/admin/users
func (h *AdminHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
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

// POST /api/admin/users/{uid}/role
func (h *AdminHandler) UpdateUserRole(w http.ResponseWriter, r *http.Request) {
	targetUID := r.PathValue("uid")
	var req struct {
		Role string `json:"role"`
	}
	if err := decodeJSON(r, &req); err != nil || req.Role == "" {
		writeError(w, http.StatusBadRequest, "role is required")
		return
	}
	if err := h.userSvc.UpdateRole(r.Context(), targetUID, req.Role); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update role")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// POST /api/admin/users/{uid}/status
func (h *AdminHandler) UpdateUserStatus(w http.ResponseWriter, r *http.Request) {
	targetUID := r.PathValue("uid")
	var req struct {
		Status string `json:"status"`
	}
	if err := decodeJSON(r, &req); err != nil || req.Status == "" {
		writeError(w, http.StatusBadRequest, "status is required")
		return
	}
	if err := h.userSvc.UpdateStatus(r.Context(), targetUID, req.Status); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update status")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// POST /api/admin/users/{uid}/password
func (h *AdminHandler) ResetUserPassword(w http.ResponseWriter, r *http.Request) {
	targetUID := r.PathValue("uid")
	var req struct {
		Password string `json:"password"`
	}
	if err := decodeJSON(r, &req); err != nil || req.Password == "" {
		writeError(w, http.StatusBadRequest, "password is required")
		return
	}
	if err := h.userSvc.ResetPassword(r.Context(), targetUID, req.Password); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// POST /api/admin/users/{uid}/support-agent
func (h *AdminHandler) SetSupportAgent(w http.ResponseWriter, r *http.Request) {
	targetUID := r.PathValue("uid")
	var req struct {
		IsSupportAgent bool `json:"is_support_agent"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	user, err := h.userSvc.SetSupportAgent(r.Context(), targetUID, req.IsSupportAgent)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, user)
}

// GET /api/admin/teachers/pending
func (h *AdminHandler) PendingTeachers(w http.ResponseWriter, r *http.Request) {
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
	teacherID := r.PathValue("id")
	if err := h.teacherSvc.Approve(r.Context(), teacherID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to approve")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "approved"})
}

// POST /api/admin/teachers/{id}/reject
func (h *AdminHandler) RejectTeacher(w http.ResponseWriter, r *http.Request) {
	teacherID := r.PathValue("id")
	if err := h.teacherSvc.Reject(r.Context(), teacherID); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to reject")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "rejected"})
}

// GET /api/admin/stats
func (h *AdminHandler) Stats(w http.ResponseWriter, r *http.Request) {
	stats, err := h.userSvc.GetAdminStats(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get stats")
		return
	}
	writeJSON(w, http.StatusOK, stats)
}

// GET /api/admin/users/search?q=xxx
func (h *AdminHandler) SearchUsers(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	if query == "" {
		writeError(w, http.StatusBadRequest, "query parameter 'q' is required")
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 20
	}
	users, err := h.userSvc.SearchAll(r.Context(), query, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to search users")
		return
	}
	if users == nil {
		users = []model.User{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": users})
}

// GET /api/admin/admins
func (h *AdminHandler) ListAdmins(w http.ResponseWriter, r *http.Request) {
	admins, err := h.userSvc.ListByRole(r.Context(), "admin")
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list admins")
		return
	}
	if admins == nil {
		admins = []model.User{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"admins": admins})
}

// POST /api/admin/admins
func (h *AdminHandler) AddAdmin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Email string `json:"email"`
	}
	if err := decodeJSON(r, &req); err != nil || req.Email == "" {
		writeError(w, http.StatusBadRequest, "email is required")
		return
	}
	user, err := h.userSvc.AddAdmin(r.Context(), req.Email)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, user)
}

// DELETE /api/admin/admins/{uid}
func (h *AdminHandler) RemoveAdmin(w http.ResponseWriter, r *http.Request) {
	targetUID := r.PathValue("uid")
	currentUID := r.Context().Value(middleware.UserUIDKey).(string)
	if err := h.userSvc.RemoveAdmin(r.Context(), targetUID, currentUID); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "removed"})
}

// POST /api/admin/users/{uid}/trader
func (h *AdminHandler) SetTrader(w http.ResponseWriter, r *http.Request) {
	targetUID := r.PathValue("uid")
	var req struct {
		IsTrader bool `json:"is_trader"`
	}
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if err := h.traderSvc.SetTraderStatus(r.Context(), targetUID, req.IsTrader); err != nil {
		writeError(w, http.StatusInternalServerError, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// GET /api/announcements (public)
func (h *AdminHandler) ListAnnouncements(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, []any{})
}

// POST /api/admin/announcements
func (h *AdminHandler) CreateAnnouncement(w http.ResponseWriter, r *http.Request) {
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
	writeJSON(w, http.StatusOK, []any{})
}
