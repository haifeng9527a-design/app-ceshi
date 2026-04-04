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
	PolygonAPIKey string

	// Alpaca
	AlpacaAPIKey    string
	AlpacaAPISecret string
	AlpacaBaseURL   string

	// Storage
	StorageType string
	StoragePath string
}

func Load() *Config {
	_ = godotenv.Load()

	c := &Config{
		Port:        getEnv("PORT", "3000"),
		DatabaseURL: getEnv("DATABASE_URL", ""),
		RedisURL:    getEnv("REDIS_URL", ""),
		JWTSecret:   getEnv("JWT_SECRET", ""),
		PolygonAPIKey:           getEnv("POLYGON_API_KEY", ""),
		AlpacaAPIKey:            getEnv("ALPACA_API_KEY", ""),
		AlpacaAPISecret:         getEnv("ALPACA_API_SECRET", ""),
		AlpacaBaseURL:           getEnv("ALPACA_BASE_URL", "https://paper-api.alpaca.markets"),
		StorageType:             getEnv("STORAGE_TYPE", "local"),
		StoragePath:             getEnv("STORAGE_PATH", "./uploads"),
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
