package udun

import (
	"crypto/md5"
	"encoding/hex"
	"strings"
)

// BuildMD5Signature follows the signature pattern shown in Udun public docs:
// md5(body + key + nonce + timestamp).
// The final implementation must be re-validated against the merchant-specific docs.
func BuildMD5Signature(body, key, nonce, timestamp string) string {
	sum := md5.Sum([]byte(body + key + nonce + timestamp))
	return hex.EncodeToString(sum[:])
}

func VerifyMD5Signature(signature, body, key, nonce, timestamp string) bool {
	expected := BuildMD5Signature(body, key, nonce, timestamp)
	return strings.EqualFold(signature, expected)
}
