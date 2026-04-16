package udun

import (
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/url"
	"strconv"
	"strings"
)

func ParseFormCallback(r *http.Request) (url.Values, error) {
	if err := r.ParseForm(); err != nil {
		return nil, err
	}
	if len(r.PostForm) == 0 {
		return nil, errors.New("empty callback payload")
	}
	return r.PostForm, nil
}

func ParseDepositCallback(values url.Values) (*DepositCallback, error) {
	if values == nil {
		return nil, errors.New("nil callback payload")
	}
	body := firstNonEmpty(values, "body")
	if body == "" {
		return nil, errors.New("deposit callback body is required")
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		return nil, err
	}

	amount := parseUdunAmount(payload)
	confirmations, _ := strconv.Atoi(firstNonEmpty(values, "confirmations", "confirm_num", "confirm"))
	if confirmations == 0 {
		confirmations = int(getFloatValue(payload["blockHigh"]))
	}
	return &DepositCallback{
		ProviderTradeID: firstNonEmpty(values, "tradeId", "trade_id", "orderId", "order_id", "businessId"),
		TxHash:          stringifyPayload(payload, "txId", "txid", "txHash", "hash"),
		AssetCode:       strings.ToUpper(stringifyPayload(payload, "symbol", "coinSymbol", "coin", "asset_code")),
		Network:         strings.ToUpper(stringifyPayload(payload, "chain", "network", "mainSymbol")),
		Address:         stringifyPayload(payload, "address", "toAddress", "to_address"),
		Memo:            stringifyPayload(payload, "memo", "tag"),
		Status:          stringifyPayload(payload, "status"),
		Amount:          amount,
		Confirmations:   confirmations,
		RawValues:       values,
	}, nil
}

func ParseWithdrawCallback(values url.Values) (*WithdrawCallback, error) {
	if values == nil {
		return nil, errors.New("nil callback payload")
	}
	body := firstNonEmpty(values, "body")
	if body == "" {
		return nil, errors.New("withdraw callback body is required")
	}
	payload := map[string]any{}
	if err := json.Unmarshal([]byte(body), &payload); err != nil {
		return nil, err
	}
	tradeType, _ := strconv.Atoi(stringifyPayload(payload, "tradeType", "trade_type"))
	return &WithdrawCallback{
		ProviderTradeID: stringifyPayload(payload, "tradeId", "trade_id", "orderId", "order_id", "businessId"),
		BusinessID:      stringifyPayload(payload, "businessId", "business_id"),
		TxHash:          stringifyPayload(payload, "txId", "txid", "txHash", "hash"),
		Status:          stringifyPayload(payload, "status"),
		TradeType:       tradeType,
		Amount:          parseUdunAmount(payload),
		Fee:             parseUdunFee(payload),
		AssetCode:       strings.ToUpper(stringifyPayload(payload, "symbol", "coinSymbol", "coin", "asset_code")),
		Network:         strings.ToUpper(stringifyPayload(payload, "chain", "network", "mainSymbol")),
		MainCoinType:    stringifyPayload(payload, "mainCoinType", "main_coin_type"),
		CoinType:        stringifyPayload(payload, "coinType", "coin_type"),
		Address:         stringifyPayload(payload, "address", "toAddress", "to_address"),
		Memo:            stringifyPayload(payload, "memo", "tag"),
		ErrorMessage:    stringifyPayload(payload, "errorMsg", "error_message", "message"),
		RawValues:       values,
	}, nil
}

func firstNonEmpty(values url.Values, keys ...string) string {
	for _, key := range keys {
		if v := values.Get(key); v != "" {
			return v
		}
	}
	return ""
}

func VerifyFormCallbackSignature(values url.Values, secret string) bool {
	if values == nil || secret == "" {
		return false
	}
	signature := firstNonEmpty(values, "sign", "signature")
	nonce := firstNonEmpty(values, "nonce")
	timestamp := firstNonEmpty(values, "timestamp", "ts")
	body := firstNonEmpty(values, "body")
	if signature == "" || nonce == "" || timestamp == "" {
		return false
	}
	return VerifyMD5Signature(signature, body, secret, nonce, timestamp)
}

func stringifyPayload(payload map[string]any, keys ...string) string {
	for _, key := range keys {
		if payload == nil {
			continue
		}
		if value, ok := payload[key]; ok {
			switch typed := value.(type) {
			case string:
				if strings.TrimSpace(typed) != "" {
					return strings.TrimSpace(typed)
				}
			case float64:
				return strconv.FormatFloat(typed, 'f', -1, 64)
			case int:
				return strconv.Itoa(typed)
			}
		}
	}
	return ""
}

func parseUdunAmount(payload map[string]any) float64 {
	rawAmount := getFloatValue(payload["amount"])
	decimals := getFloatValue(payload["decimals"])
	if rawAmount <= 0 {
		return 0
	}
	if decimals <= 0 {
		return rawAmount
	}
	return rawAmount / math.Pow10(int(decimals))
}

func parseUdunFee(payload map[string]any) float64 {
	rawFee := getFloatValue(payload["fee"])
	decimals := getFloatValue(payload["decimals"])
	if rawFee <= 0 {
		return 0
	}
	if decimals <= 0 {
		return rawFee
	}
	return rawFee / math.Pow10(int(decimals))
}

func getFloatValue(value any) float64 {
	switch typed := value.(type) {
	case float64:
		return typed
	case string:
		parsed, _ := strconv.ParseFloat(strings.TrimSpace(typed), 64)
		return parsed
	case int:
		return float64(typed)
	case int64:
		return float64(typed)
	default:
		return 0
	}
}
