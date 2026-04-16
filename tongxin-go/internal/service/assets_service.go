package service

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"tongxin-go/internal/integrations/udun"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

type AssetsService struct {
	repo       *repository.AssetsRepo
	walletRepo *repository.WalletRepo
	tradingSvc *TradingService
	spotSvc    *SpotService
	udunClient *udun.Client
	udunReady  string
}

type assetDescriptor struct {
	AssetCode   string
	AssetName   string
	Category    string
	Price       float64
	DailyChange float64
	CanDeposit  bool
}

func NewAssetsService(repo *repository.AssetsRepo, walletRepo *repository.WalletRepo, tradingSvc *TradingService, spotSvc *SpotService, udunClient *udun.Client, udunReady string) *AssetsService {
	return &AssetsService{
		repo:       repo,
		walletRepo: walletRepo,
		tradingSvc: tradingSvc,
		spotSvc:    spotSvc,
		udunClient: udunClient,
		udunReady:  udunReady,
	}
}

func (s *AssetsService) GetAssetIconMap(ctx context.Context, category string, assetCodes []string) (map[string]string, error) {
	if s.repo == nil {
		return map[string]string{}, nil
	}
	items, err := s.repo.GetAssetIconsByCategory(ctx, category, assetCodes)
	if err != nil {
		return nil, err
	}
	out := make(map[string]string, len(items))
	for code, item := range items {
		url := strings.TrimSpace(item.LocalPath)
		if url == "" {
			url = strings.TrimSpace(item.RemoteURL)
		}
		if url != "" {
			out[code] = url
		}
	}
	return out, nil
}

func (s *AssetsService) GetCopySummary(ctx context.Context, userID string) (*model.CopySummaryResponse, error) {
	return s.repo.GetCopySummary(ctx, userID)
}

func (s *AssetsService) GetCopyAccountOverview(ctx context.Context, userID string) (*model.CopyAccountOverviewResponse, error) {
	resp, err := s.repo.GetCopyAccountOverview(ctx, userID)
	if err != nil || resp == nil {
		return resp, err
	}

	// 把跟单未实现盈亏计入跟单账户总权益（原先错误地计入合约账户）。
	if s.tradingSvc != nil {
		if _, copyUnrealized, splitErr := s.tradingSvc.GetAccountInfoSplit(ctx, userID); splitErr == nil {
			resp.UnrealizedPnl = copyUnrealized
			resp.TotalEquity = resp.TotalAvailable + resp.TotalFrozen + copyUnrealized
		}
	}
	return resp, nil
}

func (s *AssetsService) GetCopyAccountPools(ctx context.Context, userID, status string) (*model.CopyAccountPoolsResponse, error) {
	return s.repo.ListCopyAccountPools(ctx, userID, status)
}

func (s *AssetsService) GetCopyAccountOpenPositions(ctx context.Context, userID, traderUID string) (*model.CopyAccountOpenPositionsResponse, error) {
	resp, err := s.repo.ListCopyAccountOpenPositions(ctx, userID, traderUID)
	if err != nil || resp == nil || len(resp.Items) == 0 {
		return resp, err
	}

	if s.tradingSvc == nil {
		return resp, nil
	}

	livePositions, liveErr := s.tradingSvc.ListPositionsWithPnL(ctx, userID)
	if liveErr != nil {
		return resp, nil
	}

	liveByID := make(map[string]model.Position, len(livePositions))
	for _, pos := range livePositions {
		if pos.IsCopyTrade {
			liveByID[pos.ID] = pos
		}
	}

	for i := range resp.Items {
		if live, ok := liveByID[resp.Items[i].PositionID]; ok {
			resp.Items[i].CurrentPrice = live.CurrentPrice
			resp.Items[i].UnrealizedPnl = live.UnrealizedPnl
			resp.Items[i].ROE = live.ROE
		}
	}

	return resp, nil
}

func (s *AssetsService) GetCopyAccountHistory(ctx context.Context, userID, traderUID string, limit, offset int) (*model.CopyAccountHistoryResponse, error) {
	return s.repo.ListCopyAccountHistory(ctx, userID, traderUID, limit, offset)
}

func (s *AssetsService) GetOverview(ctx context.Context, userID string, changeDays int) (*model.AssetsOverviewResponse, error) {
	resp := &model.AssetsOverviewResponse{
		Currency:           "USDT",
		Accounts:           []model.AssetOverviewAccount{},
		PendingWithdrawals: []model.AssetPendingWithdrawal{},
		RecentTransactions: []model.AssetTransaction{},
		ChangeSeries:       []model.AssetChangePoint{},
	}

	if s.repo != nil {
		_ = s.repo.EnsureBaseAccounts(ctx, userID)
	}

	todayPnl, err := s.repo.GetTodayPnl(ctx, userID)
	if err == nil {
		resp.TodayPnl = todayPnl
	}

	if s.repo != nil {
		if mainAvailable, mainFrozen, err := s.repo.GetMainBalance(ctx, userID); err == nil {
			resp.Accounts = append(resp.Accounts, model.AssetOverviewAccount{
				AccountType: "spot",
				DisplayName: "现货账户",
				Equity:      mainAvailable + mainFrozen,
				Available:   mainAvailable,
				Frozen:      mainFrozen,
			})
			resp.TotalEquity += mainAvailable + mainFrozen
		}
	}

	// 合约账户使用"自交易口径"：仅包含 is_copy_trade=false 的仓位浮盈 / 保证金。
	// 跟单仓位的未实现盈亏独立返回，后文累加到 CopySummary 与 TotalEquity。
	var copyUnrealized float64
	if s.tradingSvc != nil {
		if futures, copyPnl, err := s.tradingSvc.GetAccountInfoSplit(ctx, userID); err == nil && futures != nil {
			resp.Accounts = append(resp.Accounts, model.AssetOverviewAccount{
				AccountType:   "futures",
				DisplayName:   "合约账户",
				Equity:        futures.Equity,
				Available:     futures.Available,
				Frozen:        futures.Frozen,
				UnrealizedPnl: futures.UnrealizedPnl,
				MarginUsed:    futures.MarginUsed,
			})
			resp.TotalEquity += futures.Equity
			copyUnrealized = copyPnl
		}
	}

	if copySummary, err := s.GetCopySummary(ctx, userID); err == nil && copySummary != nil {
		copySummary.TotalUnrealizedPnl = copyUnrealized
		resp.CopySummary = copySummary
		resp.TotalEquity += copySummary.TotalAvailable + copySummary.TotalFrozen + copyUnrealized
	}

	if s.repo != nil {
		if txs, err := s.repo.GetTransactions(ctx, userID, 10, 0, ""); err == nil && txs != nil {
			resp.RecentTransactions = txs
		}
		if pending, count, amount, err := s.repo.GetPendingWithdrawals(ctx, userID, 3); err == nil {
			resp.PendingWithdrawals = pending
			resp.PendingWithdrawalCount = count
			resp.PendingWithdrawalAmount = amount
		}
		if points, err := s.repo.GetChangeSeries(ctx, userID, changeDays); err == nil && points != nil {
			totalNet := 0.0
			for _, item := range points {
				totalNet += item.NetChange
			}
			running := resp.TotalEquity - totalNet
			for i := range points {
				running += points[i].NetChange
				points[i].Equity = running
			}
			resp.ChangeSeries = points
		}
	}

	base := resp.TotalEquity - resp.TodayPnl
	if base > 0 {
		resp.TodayPnlRate = resp.TodayPnl / math.Abs(base)
	}

	return resp, nil
}

func (s *AssetsService) GetPnlCalendar(ctx context.Context, userID string, year, month int) (*model.AssetPnlCalendarResponse, error) {
	return s.repo.GetPnlCalendar(ctx, userID, year, month)
}

func (s *AssetsService) GetSpotHoldings(ctx context.Context, userID, category, query string, ownedOnly, hideDust bool) (*model.SpotHoldingsResponse, error) {
	options, err := s.GetDepositOptions(ctx)
	if err != nil {
		options = []model.AssetDepositAssetOption{}
	}

	balances := map[string]struct {
		Available float64
		Frozen    float64
	}{}
	if s.repo != nil {
		if rows, rowErr := s.repo.ListSpotBalances(ctx, userID); rowErr == nil && rows != nil {
			balances = rows
		}
	}

	snapshots := map[string]model.SpotAssetSnapshot{}
	if s.spotSvc != nil {
		if liveSnapshots, snapshotErr := s.spotSvc.GetAssetSnapshots(ctx); snapshotErr == nil && liveSnapshots != nil {
			snapshots = liveSnapshots
		}
	}

	fills := []model.SpotTradeFill{}
	if s.repo != nil {
		if history, historyErr := s.repo.ListSpotTradeFills(ctx, userID); historyErr == nil && history != nil {
			fills = history
		}
	}

	assetMap := map[string]*assetDescriptor{}
	upsertAsset := func(code string, update func(item *assetDescriptor)) {
		code = strings.ToUpper(strings.TrimSpace(code))
		if code == "" {
			return
		}
		item, ok := assetMap[code]
		if !ok {
			item = &assetDescriptor{
				AssetCode:  code,
				AssetName:  code,
				Category:   "crypto",
				CanDeposit: false,
			}
			assetMap[code] = item
		}
		update(item)
	}

	// 现货资产页至少保留一个默认的 USDT 入口：
	// - 新用户没有任何资产时，不至于出现完全空白的资产列表
	// - 作为充值/划转/提现的默认资金入口，保持在列表第一位
	upsertAsset("USDT", func(item *assetDescriptor) {
		item.AssetName = "USDT"
		item.Category = "crypto"
		item.Price = 1
		item.CanDeposit = true
	})

	for _, option := range options {
		assetCode := strings.ToUpper(strings.TrimSpace(option.AssetCode))
		upsertAsset(assetCode, func(item *assetDescriptor) {
			item.AssetName = strings.TrimSpace(option.Label)
			if item.AssetName == "" {
				item.AssetName = assetCode
			}
			item.Category = "crypto"
			item.CanDeposit = true
			if item.Price == 0 {
				switch assetCode {
				case "USDT", "USDC", "USD":
					item.Price = 1
				}
			}
		})
	}

	for assetCode, snapshot := range snapshots {
		assetCode := strings.ToUpper(strings.TrimSpace(assetCode))
		snapshot := snapshot
		upsertAsset(assetCode, func(item *assetDescriptor) {
			if strings.TrimSpace(snapshot.AssetName) != "" {
				item.AssetName = snapshot.AssetName
			}
			if strings.TrimSpace(snapshot.Category) != "" {
				item.Category = snapshot.Category
			}
			if snapshot.Price > 0 {
				item.Price = snapshot.Price
			}
			item.DailyChange = snapshot.DailyChangeRate
		})
	}

	for assetCode := range balances {
		assetCode := strings.ToUpper(strings.TrimSpace(assetCode))
		upsertAsset(assetCode, func(item *assetDescriptor) {
			if item.Price == 0 {
				switch assetCode {
				case "USDT", "USDC", "USD":
					item.Price = 1
				}
			}
		})
	}

	now := time.Now()
	analyticsByAsset := computeSpotHoldingAnalytics(fills, balances, assetMap, now)

	allItems := make([]model.SpotHoldingItem, 0, len(assetMap))
	ownedCount := 0
	normalizedCategory := strings.ToLower(strings.TrimSpace(category))
	searchQuery := strings.ToLower(strings.TrimSpace(query))

	for assetCode, descriptor := range assetMap {
		balance := balances[assetCode]
		analytics := analyticsByAsset[assetCode]
		total := balance.Available + balance.Frozen
		price := descriptor.Price
		valuation := total * price
		isDust := valuation > 0 && valuation < 1
		if total > 0 || valuation > 0 {
			ownedCount++
		}

		item := model.SpotHoldingItem{
			Key:                 descriptor.Category + ":" + assetCode,
			Category:            descriptor.Category,
			AssetCode:           assetCode,
			AssetName:           descriptor.AssetName,
			BalanceTotal:        total,
			BalanceAvailable:    balance.Available,
			BalanceFrozen:       balance.Frozen,
			Price:               price,
			AvgCost:             analytics.AvgCost,
			CostEstimated:       analytics.CostEstimated,
			Valuation:           valuation,
			DailyChangeRate:     descriptor.DailyChange,
			UnrealizedPnl:       analytics.UnrealizedPnl,
			UnrealizedPnlRate:   analytics.UnrealizedPnlRate,
			TodayRealizedPnl:    analytics.TodayRealizedPnl,
			LifetimeRealizedPnl: analytics.LifetimeRealizedPnl,
			CurrentTotalPnl:     analytics.CurrentTotalPnl,
			IsDust:              isDust,
			CanDeposit:          descriptor.CanDeposit,
			CanWithdraw:         total > 0,
			CanTransfer:         total > 0,
		}
		allItems = append(allItems, item)
	}

	if s.repo != nil && len(allItems) > 0 {
		cryptoCodes := make([]string, 0)
		stockCodes := make([]string, 0)
		for _, item := range allItems {
			switch item.Category {
			case "stock":
				stockCodes = append(stockCodes, item.AssetCode)
			default:
				cryptoCodes = append(cryptoCodes, item.AssetCode)
			}
		}

		iconByKey := make(map[string]model.AssetIcon)
		if len(cryptoCodes) > 0 {
			if icons, iconErr := s.repo.GetAssetIconsByCategory(ctx, "crypto", cryptoCodes); iconErr == nil {
				for code, icon := range icons {
					iconByKey["crypto:"+code] = icon
				}
			}
		}
		if len(stockCodes) > 0 {
			if icons, iconErr := s.repo.GetAssetIconsByCategory(ctx, "stock", stockCodes); iconErr == nil {
				for code, icon := range icons {
					iconByKey["stock:"+code] = icon
				}
			}
		}

		for i := range allItems {
			key := allItems[i].Category + ":" + strings.ToUpper(strings.TrimSpace(allItems[i].AssetCode))
			if icon, ok := iconByKey[key]; ok {
				if strings.TrimSpace(icon.LocalPath) != "" {
					allItems[i].IconURL = icon.LocalPath
				} else if strings.TrimSpace(icon.RemoteURL) != "" {
					allItems[i].IconURL = icon.RemoteURL
				}
			}
		}
	}

	filtered := make([]model.SpotHoldingItem, 0, len(allItems))
	for _, item := range allItems {
		isDefaultUSDT := strings.EqualFold(item.AssetCode, "USDT") && item.Category == "crypto"
		if normalizedCategory != "" && normalizedCategory != "all" && item.Category != normalizedCategory {
			continue
		}
		if ownedOnly && !isDefaultUSDT && item.BalanceTotal <= 0 && item.BalanceFrozen <= 0 && item.Valuation <= 0 {
			continue
		}
		if hideDust && !isDefaultUSDT && item.IsDust {
			continue
		}
		if searchQuery != "" {
			haystack := strings.ToLower(item.AssetCode + " " + item.AssetName)
			if !strings.Contains(haystack, searchQuery) {
				continue
			}
		}
		filtered = append(filtered, item)
	}

	sort.Slice(filtered, func(i, j int) bool {
		if strings.EqualFold(filtered[i].AssetCode, "USDT") && filtered[i].Category == "crypto" {
			return true
		}
		if strings.EqualFold(filtered[j].AssetCode, "USDT") && filtered[j].Category == "crypto" {
			return false
		}
		if filtered[i].Valuation == filtered[j].Valuation {
			return filtered[i].AssetCode < filtered[j].AssetCode
		}
		return filtered[i].Valuation > filtered[j].Valuation
	})

	return &model.SpotHoldingsResponse{
		Items:        filtered,
		TotalCount:   len(allItems),
		VisibleCount: len(filtered),
		OwnedCount:   ownedCount,
	}, nil
}

type spotHoldingAnalytics struct {
	AvgCost             float64
	CostEstimated       bool
	TodayRealizedPnl    float64
	LifetimeRealizedPnl float64
	UnrealizedPnl       float64
	UnrealizedPnlRate   float64
	CurrentTotalPnl     float64
}

func computeSpotHoldingAnalytics(
	fills []model.SpotTradeFill,
	balances map[string]struct {
		Available float64
		Frozen    float64
	},
	assets map[string]*assetDescriptor,
	now time.Time,
) map[string]spotHoldingAnalytics {
	type state struct {
		qty              float64
		carryingCost     float64
		todayRealized    float64
		lifetimeRealized float64
		costEstimated    bool
	}

	states := make(map[string]*state)
	getState := func(assetCode string) *state {
		assetCode = strings.ToUpper(strings.TrimSpace(assetCode))
		item, ok := states[assetCode]
		if !ok {
			item = &state{}
			states[assetCode] = item
		}
		return item
	}

	sameDay := func(a, b time.Time) bool {
		y1, m1, d1 := a.Date()
		y2, m2, d2 := b.Date()
		return y1 == y2 && m1 == m2 && d1 == d2
	}

	for _, fill := range fills {
		assetCode := strings.ToUpper(strings.TrimSpace(fill.AssetCode))
		if assetCode == "" {
			continue
		}
		state := getState(assetCode)

		baseQty := math.Max(fill.BaseQty, 0)
		quoteQty := math.Max(fill.QuoteQty, 0)
		fee := math.Max(fill.Fee, 0)
		feeAsset := strings.ToUpper(strings.TrimSpace(fill.FeeAsset))
		quoteAsset := strings.ToUpper(strings.TrimSpace(fill.QuoteAsset))

		switch strings.ToLower(strings.TrimSpace(fill.Side)) {
		case model.SpotSideBuy:
			state.qty += baseQty
			state.carryingCost += quoteQty
			if feeAsset == quoteAsset || feeAsset == "USDT" || feeAsset == "USD" {
				state.carryingCost += fee
			} else if feeAsset == assetCode {
				state.qty = math.Max(state.qty-fee, 0)
			}
		case model.SpotSideSell:
			if state.qty <= 0 {
				continue
			}
			avgCost := 0.0
			if state.qty > 0 {
				avgCost = state.carryingCost / state.qty
			}

			disposedQty := baseQty
			if feeAsset == assetCode {
				disposedQty += fee
			}
			if disposedQty > state.qty {
				disposedQty = state.qty
			}
			costOut := avgCost * disposedQty

			netProceeds := quoteQty
			if feeAsset == quoteAsset || feeAsset == "USDT" || feeAsset == "USD" {
				netProceeds -= fee
			}

			realized := netProceeds - costOut
			state.lifetimeRealized += realized
			if sameDay(fill.FilledAt.In(now.Location()), now) {
				state.todayRealized += realized
			}

			state.qty = math.Max(state.qty-disposedQty, 0)
			state.carryingCost = math.Max(state.carryingCost-costOut, 0)
			if state.qty == 0 {
				state.carryingCost = 0
			}
		}
	}

	results := make(map[string]spotHoldingAnalytics)
	for assetCode, descriptor := range assets {
		balance := balances[assetCode]
		state := getState(assetCode)
		totalBalance := math.Max(balance.Available+balance.Frozen, 0)
		price := 0.0
		if descriptor != nil {
			price = math.Max(descriptor.Price, 0)
		}

		if totalBalance > state.qty+1e-8 {
			extraQty := totalBalance - state.qty
			state.qty = totalBalance
			state.carryingCost += extraQty * price
			state.costEstimated = true
		} else if state.qty > totalBalance+1e-8 {
			if state.qty > 0 {
				scale := totalBalance / state.qty
				if scale < 0 {
					scale = 0
				}
				state.carryingCost *= scale
			}
			state.qty = totalBalance
		}

		avgCost := 0.0
		if state.qty > 1e-8 {
			avgCost = state.carryingCost / state.qty
		}
		unrealized := (price - avgCost) * totalBalance
		unrealizedRate := 0.0
		costBasis := avgCost * totalBalance
		if costBasis > 1e-8 {
			unrealizedRate = unrealized / costBasis
		}

		results[assetCode] = spotHoldingAnalytics{
			AvgCost:             avgCost,
			CostEstimated:       state.costEstimated,
			TodayRealizedPnl:    state.todayRealized,
			LifetimeRealizedPnl: state.lifetimeRealized,
			UnrealizedPnl:       unrealized,
			UnrealizedPnlRate:   unrealizedRate,
			CurrentTotalPnl:     state.lifetimeRealized + unrealized,
		}
	}

	return results
}

func (s *AssetsService) GetTransactions(ctx context.Context, userID string, limit, offset int) ([]model.AssetTransaction, error) {
	return s.repo.GetTransactions(ctx, userID, limit, offset, "")
}

func (s *AssetsService) GetTransactionsByStatus(ctx context.Context, userID string, limit, offset int, status string) ([]model.AssetTransaction, error) {
	return s.repo.GetTransactions(ctx, userID, limit, offset, status)
}

func (s *AssetsService) GetDepositAddresses(ctx context.Context, userID, assetCode, network string) ([]model.AssetDepositAddress, error) {
	if assetCode != "" && network != "" {
		item, err := s.GetOrCreateDepositAddress(ctx, userID, assetCode, network)
		if err != nil {
			return nil, err
		}
		if item != nil {
			return []model.AssetDepositAddress{*item}, nil
		}
	}
	return s.repo.GetDepositAddresses(ctx, userID, assetCode, network)
}

func (s *AssetsService) GetDepositOptions(ctx context.Context) ([]model.AssetDepositAssetOption, error) {
	fallback := []model.AssetDepositAssetOption{
		{
			AssetCode: "USDT",
			Label:     "USDT",
			Networks: []model.AssetDepositNetworkOption{
				{Value: "TRC20", Label: "TRC20"},
				{Value: "ERC20", Label: "ERC20"},
			},
		},
		{
			AssetCode: "USDC",
			Label:     "USDC",
			Networks: []model.AssetDepositNetworkOption{
				{Value: "ERC20", Label: "ERC20"},
			},
		},
		{
			AssetCode: "ETH",
			Label:     "ETH",
			Networks: []model.AssetDepositNetworkOption{
				{Value: "ERC20", Label: "ERC20"},
			},
		},
		{
			AssetCode: "TRX",
			Label:     "TRX",
			Networks: []model.AssetDepositNetworkOption{
				{Value: "TRC20", Label: "TRC20"},
			},
		},
	}

	if s.udunClient == nil {
		return fallback, nil
	}

	coins, err := s.udunClient.ListSupportedCoins(ctx, false)
	if err != nil {
		return fallback, nil
	}

	type assetDef struct {
		label    string
		networks map[string]string
	}
	assets := map[string]*assetDef{}
	addOption := func(assetCode, network, label string) {
		assetCode = strings.TrimSpace(strings.ToUpper(assetCode))
		network = strings.TrimSpace(strings.ToUpper(network))
		if assetCode == "" || network == "" {
			return
		}
		entry, ok := assets[assetCode]
		if !ok {
			entry = &assetDef{label: assetCode, networks: map[string]string{}}
			assets[assetCode] = entry
		}
		entry.networks[network] = network
		if label != "" {
			entry.label = label
		}
	}

	for _, coin := range coins {
		symbol := strings.ToUpper(string(coin.Symbol))
		name := strings.ToUpper(string(coin.Name))
		coinName := strings.ToUpper(string(coin.CoinName))
		mainSymbol := strings.ToUpper(string(coin.MainSymbol))

		switch {
		case strings.Contains(symbol, "TRCUSDT") || strings.Contains(name, "USDT-TRC20") || strings.Contains(coinName, "USDT-TRC20"):
			addOption("USDT", "TRC20", "USDT")
		case symbol == "USDT" && mainSymbol == "ETH":
			addOption("USDT", "ERC20", "USDT")
		case strings.Contains(symbol, "USDCBEP20") || strings.Contains(coinName, "USDC-BEP20"):
			addOption("USDC", "BEP20", "USDC")
		case symbol == "USDC" && mainSymbol == "ETH":
			addOption("USDC", "ERC20", "USDC")
		case symbol == "ETH":
			addOption("ETH", "ERC20", "ETH")
		case symbol == "TRX" || name == "TRX":
			addOption("TRX", "TRC20", "TRX")
		case symbol == "BSC" || strings.Contains(coinName, "BINANCESMARTCHAIN"):
			addOption("BNB", "BEP20", "BNB")
		}
	}

	if len(assets) == 0 {
		return fallback, nil
	}

	order := map[string]int{
		"USDT": 0,
		"USDC": 1,
		"BTC":  2,
		"ETH":  3,
		"BNB":  4,
		"TRX":  5,
	}
	keys := make([]string, 0, len(assets))
	for key := range assets {
		keys = append(keys, key)
	}
	sort.Slice(keys, func(i, j int) bool {
		oi, iok := order[keys[i]]
		oj, jok := order[keys[j]]
		switch {
		case iok && jok:
			return oi < oj
		case iok:
			return true
		case jok:
			return false
		default:
			return keys[i] < keys[j]
		}
	})

	options := make([]model.AssetDepositAssetOption, 0, len(keys))
	for _, key := range keys {
		entry := assets[key]
		networkKeys := make([]string, 0, len(entry.networks))
		for network := range entry.networks {
			networkKeys = append(networkKeys, network)
		}
		sort.Slice(networkKeys, func(i, j int) bool {
			netOrder := map[string]int{"TRC20": 0, "ERC20": 1, "BEP20": 2, "BTC": 3, "TON": 4}
			oi, iok := netOrder[networkKeys[i]]
			oj, jok := netOrder[networkKeys[j]]
			switch {
			case iok && jok:
				return oi < oj
			case iok:
				return true
			case jok:
				return false
			default:
				return networkKeys[i] < networkKeys[j]
			}
		})
		networks := make([]model.AssetDepositNetworkOption, 0, len(networkKeys))
		for _, network := range networkKeys {
			networks = append(networks, model.AssetDepositNetworkOption{
				Value: network,
				Label: network,
			})
		}
		options = append(options, model.AssetDepositAssetOption{
			AssetCode: key,
			Label:     entry.label,
			Networks:  networks,
		})
	}

	return options, nil
}

func (s *AssetsService) GetDepositRecords(ctx context.Context, userID, assetCode string, limit, offset int) ([]model.AssetDepositRecord, error) {
	return s.repo.GetDepositRecords(ctx, userID, assetCode, limit, offset)
}

func (s *AssetsService) GetOrCreateDepositAddress(ctx context.Context, userID, assetCode, network string) (*model.AssetDepositAddress, error) {
	if assetCode == "" {
		return nil, fmt.Errorf("asset code is required")
	}
	if network == "" {
		return nil, fmt.Errorf("network is required")
	}

	if existing, err := s.repo.GetActiveDepositAddress(ctx, userID, assetCode, network); err == nil && existing != nil {
		return existing, nil
	}

	if s.udunClient == nil {
		if strings.TrimSpace(s.udunReady) != "" {
			return nil, fmt.Errorf("udun deposit address service not ready: %s", s.udunReady)
		}
		return nil, fmt.Errorf("udun deposit address service not configured")
	}

	result, err := s.udunClient.CreateAddress(ctx, udun.CreateAddressInput{
		UserID:    userID,
		AssetCode: assetCode,
		Network:   network,
	})
	if err != nil {
		return nil, err
	}
	if result == nil || result.Address == "" {
		return nil, fmt.Errorf("provider did not return a deposit address")
	}

	return s.repo.CreateDepositAddress(
		ctx,
		userID,
		assetCode,
		network,
		result.Address,
		result.Memo,
		"udun",
		result.ProviderAddressID,
		result.ProviderWalletID,
		string(result.RawResponse),
	)
}

func udunExternalID(cb *udun.DepositCallback) string {
	if cb == nil {
		return ""
	}
	if strings.TrimSpace(cb.ProviderTradeID) != "" {
		return cb.ProviderTradeID
	}
	return strings.TrimSpace(cb.TxHash)
}

func (s *AssetsService) HandleUdunDepositCallback(ctx context.Context, cb *udun.DepositCallback) (*model.AssetDepositCallbackResult, error) {
	if cb == nil {
		return nil, fmt.Errorf("deposit callback is required")
	}

	result, err := s.repo.ProcessUdunDepositCallback(ctx, cb)
	eventStatus := "processed"
	errorMessage := ""
	if err != nil {
		eventStatus = "failed"
		errorMessage = err.Error()
	} else if result != nil {
		switch result.Status {
		case "ignored":
			eventStatus = "ignored"
		case "credited":
			eventStatus = "credited"
		case "pending_confirm", "detected":
			eventStatus = "pending_confirm"
		case "failed":
			eventStatus = "failed"
		}
	}
	if logErr := s.repo.LogIntegrationEvent(ctx, "udun", "deposit_callback", udunExternalID(cb), eventStatus, cb.RawValues, errorMessage); logErr != nil {
		// Logging should not prevent the business result from returning.
		_ = logErr
	}
	if err != nil {
		return nil, err
	}
	return result, nil
}

func (s *AssetsService) ValidateWithdrawAddress(ctx context.Context, assetCode, network, address string) error {
	if strings.TrimSpace(address) == "" {
		return fmt.Errorf("withdraw address is required")
	}
	if s.udunClient == nil {
		if strings.TrimSpace(s.udunReady) != "" {
			return fmt.Errorf("udun withdraw service not ready: %s", s.udunReady)
		}
		return fmt.Errorf("udun withdraw service not configured")
	}
	return s.udunClient.CheckAddress(ctx, assetCode, network, address)
}

func (s *AssetsService) ApproveWithdrawal(ctx context.Context, withdrawalID, adminUID string) (*model.AdminAssetWithdrawal, error) {
	if s.udunClient == nil {
		if strings.TrimSpace(s.udunReady) != "" {
			return nil, fmt.Errorf("udun withdraw service not ready: %s", s.udunReady)
		}
		return nil, fmt.Errorf("udun withdraw service not configured")
	}

	target, err := s.repo.GetWithdrawalForProviderSubmission(ctx, withdrawalID)
	if err != nil {
		return nil, err
	}
	if target.Status != "pending_review" {
		return nil, fmt.Errorf("withdrawal is not pending review")
	}

	result, err := s.udunClient.Withdraw(ctx, udun.WithdrawInput{
		RequestID: withdrawalID,
		AssetCode: target.AssetCode,
		Network:   target.Network,
		Address:   target.Address,
		Memo:      target.Memo,
		Amount:    target.Amount,
	})
	if err != nil {
		return nil, err
	}

	providerStatus := strings.TrimSpace(result.ProviderStatus)
	if providerStatus == "" {
		providerStatus = "0"
	}
	return s.repo.MarkWithdrawalSubmittedToProvider(ctx, withdrawalID, adminUID, result.ProviderTradeID, providerStatus, result.RawResponse)
}

func (s *AssetsService) HandleUdunWithdrawCallback(ctx context.Context, cb *udun.WithdrawCallback) (*model.AdminAssetWithdrawal, error) {
	if cb == nil {
		return nil, fmt.Errorf("withdraw callback is required")
	}
	result, err := s.repo.ProcessUdunWithdrawCallback(ctx, cb)
	eventStatus := "processed"
	errorMessage := ""
	if err != nil {
		eventStatus = "failed"
		errorMessage = err.Error()
	} else if result != nil {
		eventStatus = result.Status
	}
	if logErr := s.repo.LogIntegrationEvent(ctx, "udun", "withdraw_callback", strings.TrimSpace(cb.BusinessID), eventStatus, cb.RawValues, errorMessage); logErr != nil {
		_ = logErr
	}
	if err != nil {
		return nil, err
	}
	return result, nil
}

func (s *AssetsService) DepositToSpot(ctx context.Context, userID string, amount float64) (*model.AssetDepositResponse, error) {
	return s.repo.DepositToSpot(ctx, userID, amount)
}

func (s *AssetsService) WithdrawFromSpot(ctx context.Context, userID string, amount float64, network, address string) (*model.AssetWithdrawResponse, error) {
	if err := s.ValidateWithdrawAddress(ctx, "USDT", network, address); err != nil {
		return nil, err
	}
	return s.repo.WithdrawFromSpot(ctx, userID, amount, network, address)
}

func (s *AssetsService) Transfer(ctx context.Context, userID string, req *model.AssetTransferRequest) (*model.AssetTransferResponse, error) {
	return s.repo.TransferBetweenAccounts(ctx, userID, req.FromAccount, req.ToAccount, req.Amount)
}
