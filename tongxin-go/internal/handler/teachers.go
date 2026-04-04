package handler

import (
	"net/http"
	"strconv"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type TeachersHandler struct {
	teacherSvc *service.TeacherService
}

func NewTeachersHandler(teacherSvc *service.TeacherService) *TeachersHandler {
	return &TeachersHandler{teacherSvc: teacherSvc}
}

// GET /api/teachers
func (h *TeachersHandler) List(w http.ResponseWriter, r *http.Request) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 20
	}

	teachers, err := h.teacherSvc.List(r.Context(), limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list teachers")
		return
	}
	if teachers == nil {
		teachers = []model.Teacher{}
	}

	writeJSON(w, http.StatusOK, teachers)
}

// GET /api/teachers/featured
func (h *TeachersHandler) Featured(w http.ResponseWriter, r *http.Request) {
	teachers, err := h.teacherSvc.List(r.Context(), 6, 0)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list teachers")
		return
	}
	if teachers == nil {
		teachers = []model.Teacher{}
	}
	writeJSON(w, http.StatusOK, teachers)
}

// GET /api/teachers/{id}
func (h *TeachersHandler) GetByID(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	t, err := h.teacherSvc.GetByUserID(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusNotFound, "teacher not found")
		return
	}
	writeJSON(w, http.StatusOK, t)
}

// POST /api/teachers/apply
func (h *TeachersHandler) Apply(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.ApplyTeacherRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.teacherSvc.Apply(r.Context(), uid, &req); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to apply")
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{"status": "pending"})
}

// GET /api/teachers/my
func (h *TeachersHandler) GetMy(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	t, err := h.teacherSvc.GetByUserID(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusNotFound, "not a teacher")
		return
	}
	writeJSON(w, http.StatusOK, t)
}

// PUT /api/teachers/my
func (h *TeachersHandler) UpdateMy(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var body struct {
		Bio         string   `json:"bio"`
		Specialties []string `json:"specialties"`
	}
	if err := decodeJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if err := h.teacherSvc.Update(r.Context(), uid, body.Bio, body.Specialties); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "updated"})
}

// POST /api/teachers/strategies
func (h *TeachersHandler) CreateStrategy(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.CreateStrategyRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	s, err := h.teacherSvc.CreateStrategy(r.Context(), uid, &req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create strategy")
		return
	}

	writeJSON(w, http.StatusCreated, s)
}

// GET /api/teachers/{id}/strategies
func (h *TeachersHandler) ListStrategies(w http.ResponseWriter, r *http.Request) {
	teacherID := r.PathValue("id")
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	offset, _ := strconv.Atoi(r.URL.Query().Get("offset"))
	if limit <= 0 {
		limit = 20
	}

	strategies, err := h.teacherSvc.ListStrategies(r.Context(), teacherID, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list strategies")
		return
	}
	if strategies == nil {
		strategies = []model.Strategy{}
	}

	writeJSON(w, http.StatusOK, strategies)
}

// DELETE /api/teachers/strategies/{id}
func (h *TeachersHandler) DeleteStrategy(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	strategyID := r.PathValue("id")
	if err := h.teacherSvc.DeleteStrategy(r.Context(), strategyID, uid); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to delete strategy")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// POST /api/teachers/{id}/follow
func (h *TeachersHandler) Follow(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	teacherID := r.PathValue("id")
	if err := h.teacherSvc.Follow(r.Context(), teacherID, uid); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to follow")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "followed"})
}

// DELETE /api/teachers/{id}/follow
func (h *TeachersHandler) Unfollow(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	teacherID := r.PathValue("id")
	if err := h.teacherSvc.Unfollow(r.Context(), teacherID, uid); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to unfollow")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "unfollowed"})
}

// POST /api/teachers/strategies/{id}/like
func (h *TeachersHandler) LikeStrategy(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	strategyID := r.PathValue("id")
	if err := h.teacherSvc.LikeStrategy(r.Context(), strategyID, uid); err != nil {
		writeError(w, http.StatusInternalServerError, "failed to like")
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "liked"})
}
