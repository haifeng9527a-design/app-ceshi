package udun

import (
	"encoding/json"
	"fmt"
	"net/url"
	"strings"
)

type Config struct {
	Enabled             bool
	BaseURL             string
	APIKey              string
	MerchantID          string
	SignSecret          string
	CallbackDepositURL  string
	CallbackWithdrawURL string
	RequestTimeoutMS    int
	RetryMaxAttempts    int
}

type CreateAddressInput struct {
	UserID    string
	AssetCode string
	Network   string
}

type CreateAddressResult struct {
	Address           string
	Memo              string
	ProviderAddressID string
	ProviderWalletID  string
	RawResponse       []byte
}

type Stringish string

func (s *Stringish) UnmarshalJSON(data []byte) error {
	if s == nil {
		return nil
	}
	trimmed := strings.TrimSpace(string(data))
	if trimmed == "" || trimmed == "null" {
		*s = ""
		return nil
	}

	var asString string
	if err := json.Unmarshal(data, &asString); err == nil {
		*s = Stringish(asString)
		return nil
	}

	var asNumber json.Number
	if err := json.Unmarshal(data, &asNumber); err == nil {
		*s = Stringish(asNumber.String())
		return nil
	}

	var asBool bool
	if err := json.Unmarshal(data, &asBool); err == nil {
		*s = Stringish(fmt.Sprintf("%t", asBool))
		return nil
	}

	return fmt.Errorf("unsupported stringish json value: %s", trimmed)
}

type SupportedCoin struct {
	Name         Stringish `json:"name"`
	CoinName     Stringish `json:"coinName"`
	Symbol       Stringish `json:"symbol"`
	MainCoinType Stringish `json:"mainCoinType"`
	CoinType     Stringish `json:"coinType"`
	Decimals     Stringish `json:"decimals"`
	TokenStatus  Stringish `json:"tokenStatus"`
	MainSymbol   Stringish `json:"mainSymbol"`
	Balance      Stringish `json:"balance"`
	Logo         Stringish `json:"logo"`
}

type WithdrawInput struct {
	RequestID string
	AssetCode string
	Network   string
	Address   string
	Memo      string
	Amount    float64
}

type WithdrawResult struct {
	ProviderTradeID string
	ProviderStatus  string
	RawResponse     []byte
}

type DepositCallback struct {
	ProviderTradeID string
	TxHash          string
	AssetCode       string
	Network         string
	Address         string
	Memo            string
	Status          string
	Amount          float64
	Confirmations   int
	RawValues       url.Values
}

type WithdrawCallback struct {
	ProviderTradeID string
	BusinessID      string
	TxHash          string
	Status          string
	TradeType       int
	Amount          float64
	Fee             float64
	AssetCode       string
	Network         string
	MainCoinType    string
	CoinType        string
	Address         string
	Memo            string
	ErrorMessage    string
	RawValues       url.Values
}
