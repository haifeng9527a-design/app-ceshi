package udun

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	appconfig "tongxin-go/internal/config"
)

var ErrUdunDisabled = errors.New("udun integration disabled")
var ErrUdunWithdrawCallbackUnavailable = errors.New("udun withdraw callback URL must be publicly reachable")

func ValidateConfig(cfg Config) error {
	if !cfg.Enabled {
		return ErrUdunDisabled
	}

	missing := make([]string, 0, 3)
	if strings.TrimSpace(cfg.BaseURL) == "" {
		missing = append(missing, "UDUN_GATEWAY_BASE_URL")
	}
	if strings.TrimSpace(cfg.APIKey) == "" {
		missing = append(missing, "UDUN_API_KEY")
	}
	if strings.TrimSpace(cfg.MerchantID) == "" {
		missing = append(missing, "UDUN_MERCHANT_ID")
	}
	if len(missing) > 0 {
		return fmt.Errorf("missing udun configuration: %s", strings.Join(missing, ", "))
	}
	return nil
}

type Client struct {
	cfg        Config
	httpClient *http.Client
}

type gatewayResponse struct {
	Code    int
	Message string
	Data    json.RawMessage
	Raw     []byte
}

func NewFromAppConfig(cfg *appconfig.Config) (*Client, error) {
	if cfg == nil {
		return nil, errors.New("nil app config")
	}
	return NewClient(Config{
		Enabled:             cfg.UdunEnabled,
		BaseURL:             cfg.UdunGatewayBaseURL,
		APIKey:              cfg.UdunAPIKey,
		MerchantID:          cfg.UdunMerchantID,
		SignSecret:          cfg.UdunSignSecret,
		CallbackDepositURL:  cfg.UdunCallbackDepositURL,
		CallbackWithdrawURL: cfg.UdunCallbackWithdrawURL,
		RequestTimeoutMS:    cfg.UdunRequestTimeoutMS,
		RetryMaxAttempts:    cfg.UdunRetryMaxAttempts,
	})
}

func NewClient(cfg Config) (*Client, error) {
	if err := ValidateConfig(cfg); err != nil {
		return nil, err
	}
	if cfg.RequestTimeoutMS <= 0 {
		cfg.RequestTimeoutMS = 10000
	}
	if cfg.RetryMaxAttempts <= 0 {
		cfg.RetryMaxAttempts = 3
	}
	if strings.TrimSpace(cfg.SignSecret) == "" {
		cfg.SignSecret = cfg.APIKey
	}
	return &Client{
		cfg: cfg,
		httpClient: &http.Client{
			Timeout: time.Duration(cfg.RequestTimeoutMS) * time.Millisecond,
		},
	}, nil
}

func (c *Client) CreateAddress(ctx context.Context, input CreateAddressInput) (*CreateAddressResult, error) {
	mainCoinType, _, _, err := c.resolveCoinMapping(ctx, input.AssetCode, input.Network)
	if err != nil {
		return nil, err
	}

	callbackURL := strings.TrimSpace(c.cfg.CallbackDepositURL)
	if callbackURL == "" {
		callbackURL = "http://localhost:3001/api/integrations/udun/callback/deposit"
	}

	payload := []map[string]any{
		{
			"merchantId":   c.cfg.MerchantID,
			"mainCoinType": mainCoinType,
			"callUrl":      callbackURL,
			"alias":        sanitizeAlias(input.UserID, input.AssetCode, input.Network),
		},
	}

	resp, err := c.postGateway(ctx, "/mch/address/create", payload)
	if err != nil {
		return nil, err
	}
	result := &CreateAddressResult{
		Address:           extractStringFromJSON(resp.Data, "address", "depositAddress"),
		Memo:              extractStringFromJSON(resp.Data, "memo", "tag"),
		ProviderAddressID: extractStringFromJSON(resp.Data, "addressId", "address_id"),
		ProviderWalletID:  extractStringFromJSON(resp.Data, "walletId", "wallet_id"),
		RawResponse:       resp.Raw,
	}
	if strings.TrimSpace(result.Address) == "" {
		return nil, fmt.Errorf("udun provider returned success without address: %s", string(resp.Raw))
	}
	return result, nil
}

func (c *Client) Withdraw(ctx context.Context, input WithdrawInput) (*WithdrawResult, error) {
	mainCoinType, coinType, _, err := c.resolveCoinMapping(ctx, input.AssetCode, input.Network)
	if err != nil {
		return nil, err
	}

	callbackURL := strings.TrimSpace(c.cfg.CallbackWithdrawURL)
	if err := validateProviderCallbackURL(callbackURL); err != nil {
		return nil, fmt.Errorf("%w: %s", ErrUdunWithdrawCallbackUnavailable, err.Error())
	}

	payload := []map[string]any{
		{
			"address":      input.Address,
			"amount":       strconv.FormatFloat(input.Amount, 'f', -1, 64),
			"merchantId":   c.cfg.MerchantID,
			"mainCoinType": mainCoinType,
			"coinType":     coinType,
			"callUrl":      callbackURL,
			"businessId":   input.RequestID,
			"memo":         input.Memo,
		},
	}

	resp, err := c.postGateway(ctx, "/mch/withdraw", payload)
	if err != nil {
		return nil, err
	}
	return &WithdrawResult{
		ProviderTradeID: extractStringFromJSON(resp.Data, "tradeId", "trade_id", "orderId", "order_id"),
		ProviderStatus:  extractStringFromJSON(resp.Data, "status"),
		RawResponse:     resp.Raw,
	}, nil
}

func validateProviderCallbackURL(raw string) error {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return fmt.Errorf("configure UDUN_CALLBACK_WITHDRAW_URL to a public https callback URL")
	}
	parsed, err := url.Parse(raw)
	if err != nil {
		return fmt.Errorf("invalid callback URL")
	}
	if !strings.EqualFold(parsed.Scheme, "https") {
		return fmt.Errorf("callback URL must use https")
	}
	host := strings.TrimSpace(parsed.Hostname())
	if host == "" {
		return fmt.Errorf("callback URL host is missing")
	}
	if strings.EqualFold(host, "localhost") || strings.HasSuffix(strings.ToLower(host), ".local") {
		return fmt.Errorf("callback host %q is not publicly reachable", host)
	}
	if ip := net.ParseIP(host); ip != nil {
		if ip.IsLoopback() || ip.IsPrivate() || ip.IsUnspecified() {
			return fmt.Errorf("callback host %q is not publicly reachable", host)
		}
	}
	return nil
}

func (c *Client) CheckAddress(ctx context.Context, assetCode, network, address string) error {
	mainCoinType, _, _, err := c.resolveCoinMapping(ctx, assetCode, network)
	if err != nil {
		return err
	}
	payload := []map[string]any{
		{
			"merchantId":   c.cfg.MerchantID,
			"mainCoinType": mainCoinType,
			"address":      address,
		},
	}
	_, err = c.postGateway(ctx, "/mch/check/address", payload)
	return err
}

func (c *Client) ListSupportedCoins(ctx context.Context, showBalance bool) ([]SupportedCoin, error) {
	resp, err := c.postGateway(ctx, "/mch/support-coins", map[string]any{
		"merchantId":  c.cfg.MerchantID,
		"showBalance": showBalance,
	})
	if err != nil {
		return nil, err
	}

	items := make([]SupportedCoin, 0)
	if len(resp.Data) == 0 || string(resp.Data) == "null" {
		return items, nil
	}
	if err := json.Unmarshal(resp.Data, &items); err != nil {
		return nil, fmt.Errorf("failed to parse udun supported coins: %w", err)
	}
	return items, nil
}

func (c *Client) postGateway(ctx context.Context, path string, payload any) (*gatewayResponse, error) {
	body, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	timestamp := fmt.Sprintf("%d", time.Now().Unix())
	nonce := fmt.Sprintf("%d", time.Now().UnixNano())
	signature := BuildMD5Signature(string(body), c.cfg.SignSecret, nonce, timestamp)

	envelope, err := json.Marshal(map[string]any{
		"timestamp": timestamp,
		"nonce":     nonce,
		"sign":      signature,
		"body":      string(body),
	})
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(c.cfg.BaseURL, "/")+path, bytes.NewReader(envelope))
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("udun request failed: status=%d body=%s", resp.StatusCode, string(raw))
	}

	parsed, err := parseGatewayResponse(raw)
	if err != nil {
		return nil, err
	}
	return parsed, nil
}

func extractStringFromJSON(raw []byte, keys ...string) string {
	if len(raw) == 0 {
		return ""
	}
	var payload any
	if err := json.Unmarshal(raw, &payload); err != nil {
		return ""
	}
	return walkJSONForString(payload, keys...)
}

func walkJSONForString(node any, keys ...string) string {
	switch value := node.(type) {
	case map[string]any:
		for _, key := range keys {
			if field, ok := value[key]; ok {
				if str, ok := field.(string); ok && strings.TrimSpace(str) != "" {
					return str
				}
			}
		}
		for _, child := range value {
			if result := walkJSONForString(child, keys...); result != "" {
				return result
			}
		}
	case []any:
		for _, child := range value {
			if result := walkJSONForString(child, keys...); result != "" {
				return result
			}
		}
	}
	return ""
}

func parseGatewayResponse(raw []byte) (*gatewayResponse, error) {
	var payload map[string]any
	if err := json.Unmarshal(raw, &payload); err != nil {
		return nil, fmt.Errorf("failed to parse udun response: %w", err)
	}

	code := normalizeGatewayCode(payload["code"])
	message := stringifyGatewayValue(payload["message"])

	var data json.RawMessage
	if payload["data"] != nil {
		marshaled, err := json.Marshal(payload["data"])
		if err != nil {
			return nil, fmt.Errorf("failed to normalize udun response data: %w", err)
		}
		data = marshaled
	}

	if code != 200 {
		if message == "" {
			message = "provider returned a non-success code"
		}
		return nil, fmt.Errorf("udun provider error: code=%d message=%s", code, message)
	}

	return &gatewayResponse{
		Code:    code,
		Message: message,
		Data:    data,
		Raw:     raw,
	}, nil
}

func normalizeGatewayCode(value any) int {
	switch v := value.(type) {
	case float64:
		return int(v)
	case int:
		return v
	case int64:
		return int(v)
	case string:
		n, _ := strconv.Atoi(strings.TrimSpace(v))
		return n
	default:
		return 0
	}
}

func stringifyGatewayValue(value any) string {
	switch v := value.(type) {
	case string:
		return strings.TrimSpace(v)
	default:
		if value == nil {
			return ""
		}
		return strings.TrimSpace(fmt.Sprintf("%v", value))
	}
}

func sanitizeAlias(parts ...string) string {
	raw := strings.ToLower(strings.Join(parts, "-"))
	re := regexp.MustCompile(`[^a-z0-9_-]+`)
	cleaned := re.ReplaceAllString(raw, "-")
	cleaned = strings.Trim(cleaned, "-")
	if cleaned == "" {
		return "deposit-address"
	}
	if len(cleaned) > 48 {
		return cleaned[:48]
	}
	return cleaned
}

func (c *Client) resolveMainCoinType(ctx context.Context, assetCode, network string) (string, error) {
	mainCoinType, _, _, err := c.resolveCoinMapping(ctx, assetCode, network)
	return mainCoinType, err
}

func (c *Client) resolveCoinMapping(ctx context.Context, assetCode, network string) (string, string, SupportedCoin, error) {
	coins, err := c.ListSupportedCoins(ctx, false)
	if err != nil {
		return "", "", SupportedCoin{}, err
	}

	assetNorm := normalizeToken(assetCode)
	networkAliases := resolveNetworkAliases(network)
	best := ""
	bestCoinType := ""
	bestScore := -1
	var bestCoin SupportedCoin

	for _, coin := range coins {
		score := scoreSupportedCoinMatch(coin, assetNorm, networkAliases)
		mainCoinType := strings.TrimSpace(string(coin.MainCoinType))
		coinType := strings.TrimSpace(string(coin.CoinType))
		if score > bestScore && mainCoinType != "" {
			best = mainCoinType
			if coinType == "" {
				coinType = mainCoinType
			}
			bestCoinType = coinType
			bestScore = score
			bestCoin = coin
		}
	}

	if bestScore < 0 || best == "" {
		return "", "", SupportedCoin{}, fmt.Errorf("udun does not expose a supported coin mapping for %s/%s", strings.ToUpper(assetNorm), strings.ToUpper(normalizeToken(network)))
	}

	return best, bestCoinType, bestCoin, nil
}

func scoreSupportedCoinMatch(coin SupportedCoin, assetNorm string, networkAliases []string) int {
	symbol := normalizeToken(string(coin.Symbol))
	name := normalizeToken(string(coin.Name))
	coinName := normalizeToken(string(coin.CoinName))
	mainSymbol := normalizeToken(string(coin.MainSymbol))

	matchesAsset := assetNorm != "" && (symbol == assetNorm || name == assetNorm || strings.Contains(coinName, assetNorm))
	if !matchesAsset {
		return -1
	}

	score := 10
	if symbol == assetNorm {
		score += 10
	}
	if name == assetNorm {
		score += 5
	}

	if len(networkAliases) == 0 {
		return score
	}

	for _, alias := range networkAliases {
		if alias == mainSymbol {
			return score + 20
		}
		if strings.Contains(coinName, alias) {
			return score + 10
		}
		if strings.Contains(name, alias) {
			return score + 8
		}
	}

	if len(networkAliases) > 0 && mainSymbol == assetNorm {
		return score
	}

	return -1
}

func normalizeToken(value string) string {
	value = strings.TrimSpace(strings.ToUpper(value))
	value = strings.ReplaceAll(value, "-", "")
	value = strings.ReplaceAll(value, "_", "")
	value = strings.ReplaceAll(value, " ", "")
	return value
}

func resolveNetworkAliases(network string) []string {
	switch normalizeToken(network) {
	case "", "DEFAULT":
		return nil
	case "TRC20", "TRON", "TRX":
		return []string{"TRX", "TRON", "TRC20"}
	case "ERC20", "ETH", "ETHEREUM":
		return []string{"ETH", "ETHEREUM", "ERC20"}
	case "BEP20", "BSC", "BNB":
		return []string{"BNB", "BSC", "BEP20", "BINANCESMARTCHAIN"}
	case "POL", "MATIC", "POLYGON":
		return []string{"POL", "MATIC", "POLYGON"}
	case "TON":
		return []string{"TON"}
	case "BTC", "BITCOIN":
		return []string{"BTC", "BITCOIN"}
	default:
		return []string{normalizeToken(network)}
	}
}
