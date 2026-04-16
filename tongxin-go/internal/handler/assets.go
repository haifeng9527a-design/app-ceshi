package handler

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"tongxin-go/internal/middleware"
	"tongxin-go/internal/model"
	"tongxin-go/internal/service"
)

type AssetsHandler struct {
	svc *service.AssetsService
}

func NewAssetsHandler(svc *service.AssetsService) *AssetsHandler {
	return &AssetsHandler{svc: svc}
}

// GET /api/assets/icon-map?category=crypto&codes=BTC,ETH
func (h *AssetsHandler) GetAssetIconMap(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	category := r.URL.Query().Get("category")
	rawCodes := r.URL.Query().Get("codes")
	codes := make([]string, 0)
	for _, code := range strings.Split(rawCodes, ",") {
		code = strings.ToUpper(strings.TrimSpace(code))
		if code != "" {
			codes = append(codes, code)
		}
	}

	items, err := h.svc.GetAssetIconMap(r.Context(), category, codes)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get asset icon map")
		return
	}
	if items == nil {
		items = map[string]string{}
	}
	writeJSON(w, http.StatusOK, items)
}

// GET /api/assets/spot-holdings
func (h *AssetsHandler) GetSpotHoldings(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	category := r.URL.Query().Get("category")
	query := r.URL.Query().Get("query")
	ownedOnly := true
	hideDust := false
	if raw := r.URL.Query().Get("owned_only"); raw != "" {
		ownedOnly = raw != "false" && raw != "0"
	}
	if raw := r.URL.Query().Get("hide_dust"); raw != "" {
		hideDust = raw == "true" || raw == "1"
	}

	resp, err := h.svc.GetSpotHoldings(r.Context(), uid, category, query, ownedOnly, hideDust)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get spot holdings")
		return
	}
	if resp == nil {
		resp = &model.SpotHoldingsResponse{
			Items:        []model.SpotHoldingItem{},
			TotalCount:   0,
			VisibleCount: 0,
			OwnedCount:   0,
		}
	}
	if resp.Items == nil {
		resp.Items = []model.SpotHoldingItem{}
	}
	writeJSON(w, http.StatusOK, resp)
}

// GET /api/assets/deposit-options
func (h *AssetsHandler) GetDepositOptions(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	items, err := h.svc.GetDepositOptions(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get deposit options")
		return
	}
	if items == nil {
		items = []model.AssetDepositAssetOption{}
	}
	writeJSON(w, http.StatusOK, items)
}

// GET /api/assets/deposit-addresses
func (h *AssetsHandler) GetDepositAddresses(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	assetCode := r.URL.Query().Get("asset_code")
	network := r.URL.Query().Get("network")
	items, err := h.svc.GetDepositAddresses(r.Context(), uid, assetCode, network)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get deposit addresses")
		return
	}
	if items == nil {
		items = []model.AssetDepositAddress{}
	}
	writeJSON(w, http.StatusOK, items)
}

// GET /api/assets/deposits
func (h *AssetsHandler) GetDepositRecords(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	assetCode := r.URL.Query().Get("asset_code")
	limit := 10
	offset := 0
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}
	if o := r.URL.Query().Get("offset"); o != "" {
		if n, err := strconv.Atoi(o); err == nil && n >= 0 {
			offset = n
		}
	}

	items, err := h.svc.GetDepositRecords(r.Context(), uid, assetCode, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get deposit records")
		return
	}
	if items == nil {
		items = []model.AssetDepositRecord{}
	}
	writeJSON(w, http.StatusOK, items)
}

// POST /api/assets/deposit-addresses
func (h *AssetsHandler) CreateDepositAddress(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.AssetDepositAddressRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	item, err := h.svc.GetOrCreateDepositAddress(r.Context(), uid, req.AssetCode, req.Network)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, item)
}

// GET /api/assets/overview
func (h *AssetsHandler) GetOverview(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	changeDays := 7
	switch r.URL.Query().Get("range") {
	case "1d":
		changeDays = 1
	case "30d":
		changeDays = 30
	case "90d":
		changeDays = 90
	case "7d", "":
		changeDays = 7
	default:
		if raw := r.URL.Query().Get("days"); raw != "" {
			if n, err := strconv.Atoi(raw); err == nil && n > 0 {
				changeDays = n
			}
		}
	}

	resp, err := h.svc.GetOverview(r.Context(), uid, changeDays)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get assets overview")
		return
	}

	writeJSON(w, http.StatusOK, resp)
}

// GET /api/assets/pnl-calendar
func (h *AssetsHandler) GetPnlCalendar(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	now := time.Now()
	year := now.Year()
	month := int(now.Month())
	if raw := r.URL.Query().Get("year"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n > 0 {
			year = n
		}
	}
	if raw := r.URL.Query().Get("month"); raw != "" {
		if n, err := strconv.Atoi(raw); err == nil && n >= 1 && n <= 12 {
			month = n
		}
	}

	resp, err := h.svc.GetPnlCalendar(r.Context(), uid, year, month)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get pnl calendar")
		return
	}
	if resp == nil {
		resp = &model.AssetPnlCalendarResponse{
			Year:       year,
			Month:      month,
			MonthLabel: time.Date(year, time.Month(month), 1, 0, 0, 0, 0, now.Location()).Format("2006-01"),
			Days:       []model.AssetPnlCalendarDay{},
		}
	}
	if resp.Days == nil {
		resp.Days = []model.AssetPnlCalendarDay{}
	}
	writeJSON(w, http.StatusOK, resp)
}

// GET /api/assets/copy-summary
func (h *AssetsHandler) GetCopySummary(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	resp, err := h.svc.GetCopySummary(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get copy summary")
		return
	}
	if resp == nil {
		writeJSON(w, http.StatusOK, model.CopySummaryResponse{
			TotalAllocated:    0,
			TotalAvailable:    0,
			TotalFrozen:       0,
			ActiveTraderCount: 0,
			OpenPositionCount: 0,
			Items:             []model.CopySummaryItem{},
		})
		return
	}
	if resp.Items == nil {
		resp.Items = []model.CopySummaryItem{}
	}

	writeJSON(w, http.StatusOK, resp)
}

// GET /api/assets/copy-account/overview
func (h *AssetsHandler) GetCopyAccountOverview(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	resp, err := h.svc.GetCopyAccountOverview(r.Context(), uid)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get copy account overview")
		return
	}
	if resp == nil {
		resp = &model.CopyAccountOverviewResponse{}
	}
	writeJSON(w, http.StatusOK, resp)
}

// GET /api/assets/copy-account/pools
func (h *AssetsHandler) GetCopyAccountPools(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	status := r.URL.Query().Get("status")
	resp, err := h.svc.GetCopyAccountPools(r.Context(), uid, status)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get copy account pools")
		return
	}
	if resp == nil {
		resp = &model.CopyAccountPoolsResponse{Items: []model.CopyAccountPoolItem{}}
	}
	if resp.Items == nil {
		resp.Items = []model.CopyAccountPoolItem{}
	}
	writeJSON(w, http.StatusOK, resp)
}

// GET /api/assets/copy-account/open-positions
func (h *AssetsHandler) GetCopyAccountOpenPositions(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	traderUID := r.URL.Query().Get("trader_uid")
	resp, err := h.svc.GetCopyAccountOpenPositions(r.Context(), uid, traderUID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get copy account open positions")
		return
	}
	if resp == nil {
		resp = &model.CopyAccountOpenPositionsResponse{Items: []model.CopyAccountOpenPositionItem{}}
	}
	if resp.Items == nil {
		resp.Items = []model.CopyAccountOpenPositionItem{}
	}
	writeJSON(w, http.StatusOK, resp)
}

// GET /api/assets/copy-account/history
func (h *AssetsHandler) GetCopyAccountHistory(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	traderUID := r.URL.Query().Get("trader_uid")
	limit := 20
	offset := 0
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}
	if o := r.URL.Query().Get("offset"); o != "" {
		if n, err := strconv.Atoi(o); err == nil && n >= 0 {
			offset = n
		}
	}

	resp, err := h.svc.GetCopyAccountHistory(r.Context(), uid, traderUID, limit, offset)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get copy account history")
		return
	}
	if resp == nil {
		resp = &model.CopyAccountHistoryResponse{Items: []model.CopyAccountHistoryItem{}}
	}
	if resp.Items == nil {
		resp.Items = []model.CopyAccountHistoryItem{}
	}
	writeJSON(w, http.StatusOK, resp)
}

// GET /api/assets/transactions
func (h *AssetsHandler) GetTransactions(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	limit := 50
	offset := 0
	status := r.URL.Query().Get("status")
	if l := r.URL.Query().Get("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil && n > 0 {
			limit = n
		}
	}
	if o := r.URL.Query().Get("offset"); o != "" {
		if n, err := strconv.Atoi(o); err == nil && n >= 0 {
			offset = n
		}
	}

	items, err := h.svc.GetTransactionsByStatus(r.Context(), uid, limit, offset, status)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to get asset transactions")
		return
	}
	if items == nil {
		items = []model.AssetTransaction{}
	}
	writeJSON(w, http.StatusOK, items)
}

// POST /api/assets/deposit
func (h *AssetsHandler) Deposit(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.AssetDepositRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Amount <= 0 {
		writeError(w, http.StatusBadRequest, "amount must be positive")
		return
	}
	if req.Amount > 1000000 {
		writeError(w, http.StatusBadRequest, "amount too large")
		return
	}

	resp, err := h.svc.DepositToSpot(r.Context(), uid, req.Amount)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to deposit into spot account")
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// POST /api/assets/withdraw
func (h *AssetsHandler) Withdraw(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.AssetWithdrawRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Amount <= 0 || req.Address == "" || req.Network == "" {
		writeError(w, http.StatusBadRequest, "invalid withdrawal payload")
		return
	}

	resp, err := h.svc.WithdrawFromSpot(r.Context(), uid, req.Amount, req.Network, req.Address)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, resp)
}

// POST /api/assets/transfer
func (h *AssetsHandler) Transfer(w http.ResponseWriter, r *http.Request) {
	uid := middleware.GetUserUID(r.Context())
	if uid == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req model.AssetTransferRequest
	if err := decodeJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}
	if req.Amount <= 0 || req.FromAccount == "" || req.ToAccount == "" {
		writeError(w, http.StatusBadRequest, "invalid transfer payload")
		return
	}

	resp, err := h.svc.Transfer(r.Context(), uid, &req)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	writeJSON(w, http.StatusOK, resp)
}
