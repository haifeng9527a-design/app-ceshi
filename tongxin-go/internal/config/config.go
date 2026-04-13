package config

import (
	"os"
	"strings"

	"github.com/joho/godotenv"
)

type Config struct {
	Port        string
	DatabaseURL string
	CORSOrigins []string

	// Redis (optional): chat WebSocket cross-instance fan-out via Pub/Sub.
	// Messages are still persisted only in Postgres; Redis is not a source of truth.
	RedisURL string

	// JWT Auth
	JWTSecret string

	// Polygon
	PolygonAPIKey      string
	PolygonForexAPIKey string // optional second key for forex WS (separate connection quota)

	// Alpaca
	AlpacaAPIKey    string
	AlpacaAPISecret string
	AlpacaBaseURL   string

	// Storage
	StorageType string
	StoragePath string

	// LiveKit
	LiveKitURL       string
	LiveKitAPIKey    string
	LiveKitAPISecret string
}

func Load() *Config {
	_ = godotenv.Load()

	c := &Config{
		Port:             getEnv("PORT", "3000"),
		DatabaseURL:      getEnv("DATABASE_URL", ""),
		RedisURL:         getEnv("REDIS_URL", ""),
		JWTSecret:        getEnv("JWT_SECRET", ""),
		PolygonAPIKey:    getEnv("POLYGON_API_KEY", ""),
		PolygonForexAPIKey: getEnv("POLYGON_FOREX_API_KEY", ""),
		AlpacaAPIKey:     getEnv("ALPACA_API_KEY", ""),
		AlpacaAPISecret:  getEnv("ALPACA_API_SECRET", ""),
		AlpacaBaseURL:    getEnv("ALPACA_BASE_URL", "https://paper-api.alpaca.markets"),
		StorageType:      getEnv("STORAGE_TYPE", "local"),
		StoragePath:      getEnv("STORAGE_PATH", "./uploads"),
		LiveKitURL:       getEnv("LIVEKIT_URL", ""),
		LiveKitAPIKey:    getEnv("LIVEKIT_API_KEY", ""),
		LiveKitAPISecret: getEnv("LIVEKIT_API_SECRET", ""),
	}

	origins := getEnv("CORS_ORIGINS", "http://localhost:8081,http://localhost:19006")
	c.CORSOrigins = strings.Split(origins, ",")
	for i := range c.CORSOrigins {
		c.CORSOrigins[i] = strings.TrimSpace(c.CORSOrigins[i])
	}

	return c
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
