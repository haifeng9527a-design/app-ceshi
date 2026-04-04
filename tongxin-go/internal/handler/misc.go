package handler

import (
	"net/http"
	"time"
)

var startTime = time.Now()

// GET /api/health
func HealthCheck(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ok",
		"uptime": time.Since(startTime).String(),
	})
}

// GET /api/version
func Version(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"version": "2.0.0",
		"engine":  "go",
	})
}
