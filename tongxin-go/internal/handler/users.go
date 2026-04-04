package handler

import (
	"net/http"
	"strconv"
	"strings"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type UsersHandler struct {
	userSvc *service.UserService
}

func NewUsersHandler(userSvc *service.UserService) *UsersHandler {
	return &UsersHandler{userSvc: userSvc}
}

// GET /api/users/batch-profiles?uids=uid1,uid2,...
func (h *UsersHandler) BatchProfiles(w http.ResponseWriter, r *http.Request) {
	uidsParam := r.URL.Query().Get("uids")
	if uidsParam == "" {
		uidsParam = r.URL.Query().Get("ids")
	}
	if uidsParam == "" {
		writeJSON(w, http.StatusOK, []model.FriendProfile{})
		return
	}

	uids := strings.Split(uidsParam, ",")
	profiles, err := h.userSvc.BatchGetProfiles(r.Context(), uids)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to fetch profiles")
		return
	}
	if profiles == nil {
		profiles = []model.FriendProfile{}
	}

	writeJSON(w, http.StatusOK, profiles)
}

// GET /api/users?limit=20&offset=0 (admin)
func (h *UsersHandler) ListUsers(w http.ResponseWriter, r *http.Request) {
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

	users, total, err := h.userSvc.ListAll(r.Context(), limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list users")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"users": users,
		"total": total,
	})
}

// GET /api/friends/search?q=xxx
func (h *UsersHandler) SearchUsers(w http.ResponseWriter, r *http.Request) {
	query := r.URL.Query().Get("q")
	if query == "" {
		writeJSON(w, http.StatusOK, []model.FriendProfile{})
		return
	}

	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit <= 0 {
		limit = 20
	}

	results, err := h.userSvc.Search(r.Context(), query, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "search failed")
		return
	}

	writeJSON(w, http.StatusOK, results)
}
