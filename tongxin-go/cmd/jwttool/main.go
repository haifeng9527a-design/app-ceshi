package main

import (
	"fmt"
	"os"
	"time"

	"tongxin-go/internal/middleware"
)

func main() {
	secret := []byte(os.Getenv("JWT_SECRET"))
	uid := os.Getenv("UID")
	if uid == "" {
		uid = "7959932303"
	}
	claims := map[string]any{"uid": uid, "is_agent": true, "email": "arron@aivora.com"}
	t, err := middleware.SignJWT(claims, secret, 2*time.Hour)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println(t)
}
