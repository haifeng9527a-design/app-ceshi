package config

import (
	"os"
	"strconv"
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

	// Udun
	UdunEnabled             bool
	UdunGatewayBaseURL      string
	UdunAPIKey              string
	UdunMerchantID          string
	UdunSignSecret          string
	UdunCallbackDepositURL  string
	UdunCallbackWithdrawURL string
	UdunRequestTimeoutMS    int
	UdunRetryMaxAttempts    int

	// Feature flags
	// ProfitShareEnabled 控制跟单分润链路是否开启：
	//   - off (默认)：FollowTrader 永远 snapshot 0，平仓走旧 SettleToBucket，零分润、零审计
	//   - on：FollowTrader 按 trader 的 default_profit_share_rate snapshot，平仓走 SettleToBucketWithCommission
	// 上线灰度时通过环境变量 PROFIT_SHARE_ENABLED=true 打开。
	ProfitShareEnabled bool

	// ReferralEnabled 控制邀请返佣 + 代理体系是否开启：
	//   - off (默认)：RecordCommissionEvent 直接返回（无 DB 写入）；
	//                scheduler 不启动；注册绑 inviter 路径跳过；交易链路无延迟
	//   - on：       完整跑邀请返佣 + 日结（UTC 00:00）+ 代理级差
	// 上线灰度时通过 REFERRAL_ENABLED=true 打开。回滚：置 false 即可，数据零影响。
	ReferralEnabled bool

	// PlatformUserDefaultRate 新注册用户默认 my_rebate_rate（migration 默认 0.10 对齐）
	PlatformUserDefaultRate float64
	// PlatformUserMaxRate    普通用户（is_agent=false）rate 硬上限
	PlatformUserMaxRate float64
	// PlatformAgentMaxRate   代理（is_agent=true）rate 硬上限
	PlatformAgentMaxRate float64
	// DailyCommissionCapUSD  单个 inviter 单日 commission 入账硬上限（0 或负数 = 无上限）
	DailyCommissionCapUSD float64
}

func Load() *Config {
	_ = godotenv.Load()

	c := &Config{
		Port:               getEnv("PORT", "3000"),
		DatabaseURL:        getEnv("DATABASE_URL", ""),
		RedisURL:           getEnv("REDIS_URL", ""),
		JWTSecret:          getEnv("JWT_SECRET", ""),
		PolygonAPIKey:      getEnv("POLYGON_API_KEY", ""),
		PolygonForexAPIKey: getEnv("POLYGON_FOREX_API_KEY", ""),
		AlpacaAPIKey:       getEnv("ALPACA_API_KEY", ""),
		AlpacaAPISecret:    getEnv("ALPACA_API_SECRET", ""),
		AlpacaBaseURL:      getEnv("ALPACA_BASE_URL", "https://paper-api.alpaca.markets"),
		StorageType:        getEnv("STORAGE_TYPE", "local"),
		StoragePath:        getEnv("STORAGE_PATH", "./uploads"),
		LiveKitURL:         getEnv("LIVEKIT_URL", ""),
		LiveKitAPIKey:      getEnv("LIVEKIT_API_KEY", ""),
		LiveKitAPISecret:   getEnv("LIVEKIT_API_SECRET", ""),

		UdunEnabled:             strings.EqualFold(getEnv("UDUN_ENABLED", "false"), "true"),
		UdunGatewayBaseURL:      getEnv("UDUN_GATEWAY_BASE_URL", ""),
		UdunAPIKey:              getEnv("UDUN_API_KEY", ""),
		UdunMerchantID:          getEnv("UDUN_MERCHANT_ID", ""),
		UdunSignSecret:          getEnv("UDUN_SIGN_SECRET", ""),
		UdunCallbackDepositURL:  getEnv("UDUN_CALLBACK_DEPOSIT_URL", ""),
		UdunCallbackWithdrawURL: getEnv("UDUN_CALLBACK_WITHDRAW_URL", ""),
		UdunRequestTimeoutMS:    getEnvInt("UDUN_REQUEST_TIMEOUT_MS", 10000),
		UdunRetryMaxAttempts:    getEnvInt("UDUN_RETRY_MAX_ATTEMPTS", 3),

		ProfitShareEnabled: strings.EqualFold(getEnv("PROFIT_SHARE_ENABLED", "false"), "true"),

		ReferralEnabled:         strings.EqualFold(getEnv("REFERRAL_ENABLED", "false"), "true"),
		PlatformUserDefaultRate: getEnvFloat("PLATFORM_USER_DEFAULT_RATE", 0.10),
		PlatformUserMaxRate:     getEnvFloat("PLATFORM_USER_MAX_RATE", 0.20),
		PlatformAgentMaxRate:    getEnvFloat("PLATFORM_AGENT_MAX_RATE", 1.00),
		DailyCommissionCapUSD:   getEnvFloat("DAILY_COMMISSION_CAP_USD", 10000),
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

func getEnvInt(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if parsed, err := strconv.Atoi(v); err == nil {
			return parsed
		}
	}
	return fallback
}

func getEnvFloat(key string, fallback float64) float64 {
	if v := os.Getenv(key); v != "" {
		if parsed, err := strconv.ParseFloat(v, 64); err == nil {
			return parsed
		}
	}
	return fallback
}
