package handler

import (
	"net/http"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type AuthHandler struct {
	userSvc *service.UserService
}

func NewAuthHandler(userSvc *service.UserService) *AuthHandler {
	return &AuthHandler{userSvc: userSvc}
}

// POST /api/auth/register (public — no token needed)
func (h *AuthHandler) Register(w http.ResponseWriter, r *http.Request) {
	var req model.RegisterRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Email == "" || req.Password == "" {
		writeError(w, http.StatusBadRequest, "email and password are required")
		return
	}
	if len(req.Password) < 6 {
		writeError(w, http.StatusBadRequest, "password must be at least 6 characters")
		return
	}
	if req.DisplayName == "" {
		req.DisplayName = req.Email
	}

	resp, err := h.userSvc.Register(r.Context(), &req)
	if err != nil {
		if err.Error() == "email already registered" {
			writeError(w, http.StatusConflict, "email already registered")
			return
		}
		writeError(w, http.StatusInternalServerError, "registration failed")
		return
	}

	writeJSON(w, http.StatusCreated, resp)
}

// POST /api/auth/login (public — no token needed)
func (h *AuthHandler) Login(w http.ResponseWriter, r *http.Request) {
	var req model.LoginRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Email == "" || req.Password == "" {
		writeError(w, http.StatusBadRequest, "email and password are required")
		return
	}

	resp, err := h.userSvc.Login(r.Context(), req.Email, req.Password)
	if err != nil {
		writeError(w, http.StatusUnauthorized, "invalid email or password")
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

// GET /api/auth/profile (requires token)
func (h *AuthHandler) GetProfile(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	user, err := h.userSvc.GetProfile(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}

	writeJSON(w, http.StatusOK, user)
}

// PUT /api/auth/profile (requires token)
func (h *AuthHandler) UpdateProfile(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.UpdateProfileRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	user, err := h.userSvc.UpdateProfile(r.Context(), uid, &req)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to update profile")
		return
	}

	writeJSON(w, http.StatusOK, user)
}

// POST /api/auth/change-password (requires token)
func (h *AuthHandler) ChangePassword(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.ChangePasswordRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.CurrentPassword == "" || req.NewPassword == "" {
		writeError(w, http.StatusBadRequest, "current_password and new_password are required")
		return
	}

	if err := h.userSvc.ChangePassword(r.Context(), uid, req.CurrentPassword, req.NewPassword); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "password_updated"})
}

// POST /api/auth/change-email (requires token)
func (h *AuthHandler) ChangeEmail(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.ChangeEmailRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.NewEmail == "" || req.CurrentPassword == "" {
		writeError(w, http.StatusBadRequest, "new_email and current_password are required")
		return
	}

	user, err := h.userSvc.ChangeEmail(r.Context(), uid, req.NewEmail, req.CurrentPassword)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, user)
}

// GET /api/auth/delete-account/check (requires token)
func (h *AuthHandler) CheckDeleteAccount(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	data, err := h.userSvc.CheckDeleteAccount(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to check delete account")
		return
	}

	writeJSON(w, http.StatusOK, data)
}

// POST /api/auth/delete-account (requires token)
func (h *AuthHandler) DeleteAccount(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.DeleteAccountRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.CurrentPassword == "" {
		writeError(w, http.StatusBadRequest, "current_password is required")
		return
	}

	if err := h.userSvc.DeleteAccount(r.Context(), uid, req.CurrentPassword); err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"status": "account_deleted"})
}

// GET /api/auth/profile/{id} (requires token)
func (h *AuthHandler) GetProfileByID(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "user id required")
		return
	}

	user, err := h.userSvc.GetProfile(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusNotFound, "user not found")
		return
	}

	writeJSON(w, http.StatusOK, user)
}
