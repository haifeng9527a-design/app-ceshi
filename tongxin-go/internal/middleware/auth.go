package middleware

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type contextKey string

const UserUIDKey contextKey = "userUID"

// JWTSecret is the HMAC-SHA256 signing key
var JWTSecret []byte

type AuthMiddleware struct {
	secret []byte
}

func NewJWTAuthMiddleware(secret string) *AuthMiddleware {
	JWTSecret = []byte(secret)
	return &AuthMiddleware{secret: JWTSecret}
}

func (a *AuthMiddleware) Authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if header == "" {
			http.Error(w, `{"error":"missing authorization header"}`, http.StatusUnauthorized)
			return
		}

		token := strings.TrimPrefix(header, "Bearer ")
		if token == header {
			http.Error(w, `{"error":"invalid authorization format"}`, http.StatusUnauthorized)
			return
		}

		claims, err := VerifyJWT(token, a.secret)
		if err != nil {
			http.Error(w, `{"error":"invalid or expired token"}`, http.StatusUnauthorized)
			return
		}

		uid, _ := claims["uid"].(string)
		if uid == "" {
			http.Error(w, `{"error":"invalid token payload"}`, http.StatusUnauthorized)
			return
		}

		ctx := context.WithValue(r.Context(), UserUIDKey, uid)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

func (a *AuthMiddleware) OptionalAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		if header != "" {
			token := strings.TrimPrefix(header, "Bearer ")
			if token != header {
				if claims, err := VerifyJWT(token, a.secret); err == nil {
					if uid, _ := claims["uid"].(string); uid != "" {
						ctx := context.WithValue(r.Context(), UserUIDKey, uid)
						r = r.WithContext(ctx)
					}
				}
			}
		}
		next.ServeHTTP(w, r)
	})
}

func GetUserUID(ctx context.Context) string {
	uid, _ := ctx.Value(UserUIDKey).(string)
	return uid
}

// RequireAdmin wraps an authenticated handler and checks users.role = 'admin'.
func RequireAdmin(pool *pgxpool.Pool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			uid := GetUserUID(r.Context())
			if uid == "" {
				http.Error(w, `{"error":"authentication required"}`, http.StatusUnauthorized)
				return
			}
			var role string
			err := pool.QueryRow(r.Context(), `SELECT COALESCE(role,'user') FROM users WHERE uid = $1`, uid).Scan(&role)
			if err != nil || role != "admin" {
				http.Error(w, `{"error":"admin access required"}`, http.StatusForbidden)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// ── JWT helpers (HMAC-SHA256) ──

type jwtHeader struct {
	Alg string `json:"alg"`
	Typ string `json:"typ"`
}

func SignJWT(claims map[string]any, secret []byte, ttl time.Duration) (string, error) {
	header := jwtHeader{Alg: "HS256", Typ: "JWT"}
	headerJSON, _ := json.Marshal(header)

	claims["iat"] = time.Now().Unix()
	claims["exp"] = time.Now().Add(ttl).Unix()
	claimsJSON, _ := json.Marshal(claims)

	headerB64 := base64URLEncode(headerJSON)
	claimsB64 := base64URLEncode(claimsJSON)

	sigInput := headerB64 + "." + claimsB64
	sig := hmacSHA256([]byte(sigInput), secret)
	sigB64 := base64URLEncode(sig)

	return sigInput + "." + sigB64, nil
}

func VerifyJWT(tokenStr string, secret []byte) (map[string]any, error) {
	parts := strings.Split(tokenStr, ".")
	if len(parts) != 3 {
		return nil, errInvalidToken
	}

	// Verify signature
	sigInput := parts[0] + "." + parts[1]
	expectedSig := hmacSHA256([]byte(sigInput), secret)
	actualSig, err := base64URLDecode(parts[2])
	if err != nil {
		return nil, errInvalidToken
	}
	if !hmac.Equal(expectedSig, actualSig) {
		return nil, errInvalidToken
	}

	// Decode claims
	claimsJSON, err := base64URLDecode(parts[1])
	if err != nil {
		return nil, errInvalidToken
	}
	var claims map[string]any
	if err := json.Unmarshal(claimsJSON, &claims); err != nil {
		return nil, errInvalidToken
	}

	// Check expiry
	if exp, ok := claims["exp"].(float64); ok {
		if time.Now().Unix() > int64(exp) {
			return nil, errTokenExpired
		}
	}

	return claims, nil
}

func base64URLEncode(data []byte) string {
	return base64.RawURLEncoding.EncodeToString(data)
}

func base64URLDecode(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(s)
}

func hmacSHA256(data, key []byte) []byte {
	h := hmac.New(sha256.New, key)
	h.Write(data)
	return h.Sum(nil)
}

type jwtError string

func (e jwtError) Error() string { return string(e) }

const (
	errInvalidToken jwtError = "invalid token"
	errTokenExpired jwtError = "token expired"
)
