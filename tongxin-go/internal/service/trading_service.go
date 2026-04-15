package service

import (
	"context"
	"fmt"
	"log"
	"math"
	"strings"
	"sync"
	"time"

	"tongxin-go/internal/market"
	"tongxin-go/internal/model"
	"tongxin-go/internal/repository"
)

// TradingPusher is an interface for pushing trading events to users via WebSocket.
// This avoids an import cycle between service and ws packages.
type TradingPusher interface {
	PushToUser(userID string, payload any)
}

// cachedPosition holds minimal position data for real-time PnL calculation.
type cachedPosition struct {
	UserID        string
	PositionID    string
	Symbol        string
	Side          string
	Qty           float64
	EntryPrice    float64
	Leverage      int
	MarginAmount  float64
	MarginMode    string
	LiqPrice      *float64
	TpPrice       *float64
	SlPrice       *float64
	IsCopyTrade   bool
	CopyTradingID *string // 跟单仓位对应的 copy_trading 订阅 id，结算走 bucket 需要
	OpenFee       float64
	CloseFee      float64
	RealizedPnl   float64
}

type TradingService struct {
	walletRepo   *repository.WalletRepo
	orderRepo    *repository.OrderRepo
	positionRepo *repository.PositionRepo
	userRepo     *repository.UserRepo
	traderRepo   *repository.TraderRepo
	feeRepo      *repository.FeeRepo
	binance      *market.BinanceIngestor
	polygon      *market.PolygonClient
	pusher       TradingPusher

	// ProfitShareEnabled 控制平仓时走 SettleToBucket（旧路径，无分润、无审计）
	// 还是 SettleToBucketWithCommission（新路径，HWM 算法 + 分润 + 审计）。
	// 受 env PROFIT_SHARE_ENABLED 控制；与 TraderService.ProfitShareEnabled 必须保持一致。
	// 关闭时跟单平仓行为与本 commit 之前完全等价，便于灰度回滚。
	ProfitShareEnabled bool

	// In-memory pending limit orders cache for instant trigger
	pendingMu       sync.RWMutex
	pendingBySymbol map[string][]model.Order

	// In-memory open positions cache for real-time PnL push
	posMu        sync.RWMutex
	openBySymbol map[string][]cachedPosition

	// In-memory fee schedule cache (loaded from DB)
	feeMu    sync.RWMutex
	feeCache []model.VipFeeRate

	// In-memory latest price cache (updated by market WS pushQuote → OnPriceUpdate)
	priceMu    sync.RWMutex
	priceCache map[string]float64
}

// Default VIP fee schedule (fallback when DB is unavailable)
var defaultFeeSchedule = []model.VipFeeRate{
	{Level: 0, MakerFee: 0.00020, TakerFee: 0.00050},
	{Level: 1, MakerFee: 0.00016, TakerFee: 0.00040},
	{Level: 2, MakerFee: 0.00014, TakerFee: 0.00035},
	{Level: 3, MakerFee: 0.00012, TakerFee: 0.00030},
	{Level: 4, MakerFee: 0.00010, TakerFee: 0.00025},
	{Level: 5, MakerFee: 0.00008, TakerFee: 0.00020},
}

// LoadFeeSchedule loads fee schedule from DB into memory. Falls back to defaults.
func (s *TradingService) LoadFeeSchedule(ctx context.Context) {
	if s.feeRepo == nil {
		s.feeMu.Lock()
		s.feeCache = defaultFeeSchedule
		s.feeMu.Unlock()
		return
	}
	tiers, err := s.feeRepo.ListAll(ctx)
	if err != nil || len(tiers) == 0 {
		log.Printf("[trading] fee schedule from DB unavailable, using defaults: %v", err)
		s.feeMu.Lock()
		s.feeCache = defaultFeeSchedule
		s.feeMu.Unlock()
		return
	}
	schedule := make([]model.VipFeeRate, len(tiers))
	for i, t := range tiers {
		schedule[i] = model.VipFeeRate{Level: t.VipLevel, MakerFee: t.MakerFee, TakerFee: t.TakerFee}
	}
	s.feeMu.Lock()
	s.feeCache = schedule
	s.feeMu.Unlock()
	log.Printf("[trading] fee schedule loaded from DB (%d tiers)", len(schedule))
}

// ReloadFeeSchedule reloads fees from DB (called after admin modifies tiers).
func (s *TradingService) ReloadFeeSchedule(ctx context.Context) {
	s.LoadFeeSchedule(ctx)
}

func (s *TradingService) getVipFeeRates(vipLevel int) (makerFee, takerFee float64) {
	s.feeMu.RLock()
	schedule := s.feeCache
	s.feeMu.RUnlock()

	if len(schedule) == 0 {
		schedule = defaultFeeSchedule
	}
	for _, r := range schedule {
		if r.Level == vipLevel {
			return r.MakerFee, r.TakerFee
		}
	}
	// fallback to level 0
	if len(schedule) > 0 {
		return schedule[0].MakerFee, schedule[0].TakerFee
	}
	return 0.00020, 0.00050
}

// GetFeeSchedule returns the full VIP fee schedule.
func (s *TradingService) GetFeeSchedule() []model.VipFeeRate {
	s.feeMu.RLock()
	defer s.feeMu.RUnlock()
	if len(s.feeCache) == 0 {
		return defaultFeeSchedule
	}
	out := make([]model.VipFeeRate, len(s.feeCache))
	copy(out, s.feeCache)
	return out
}

// GetVipInfo returns the user's VIP level and fee rates.
func (s *TradingService) GetVipInfo(ctx context.Context, userID string) (*model.VipInfo, error) {
	level, err := s.userRepo.GetVipLevel(ctx, userID)
	if err != nil {
		level = 0
	}
	maker, taker := s.getVipFeeRates(level)
	return &model.VipInfo{VipLevel: level, MakerFee: maker, TakerFee: taker}, nil
}

func NewTradingService(
	wr *repository.WalletRepo,
	or *repository.OrderRepo,
	pr *repository.PositionRepo,
	ur *repository.UserRepo,
	tr *repository.TraderRepo,
	fr *repository.FeeRepo,
	bi *market.BinanceIngestor,
	pg *market.PolygonClient,
	pusher TradingPusher,
) *TradingService {
	return &TradingService{
		walletRepo:      wr,
		orderRepo:       or,
		positionRepo:    pr,
		userRepo:        ur,
		traderRepo:      tr,
		feeRepo:         fr,
		binance:         bi,
		polygon:         pg,
		pusher:          pusher,
		pendingBySymbol: make(map[string][]model.Order),
		openBySymbol:    make(map[string][]cachedPosition),
		feeCache:        defaultFeeSchedule,
		priceCache:      make(map[string]float64),
	}
}

// LoadPendingOrders loads all pending limit orders from DB into memory cache on startup.
func (s *TradingService) LoadPendingOrders(ctx context.Context) {
	orders, err := s.orderRepo.ListPending(ctx)
	if err != nil {
		log.Printf("[trading] failed to load pending orders: %v", err)
		return
	}
	s.pendingMu.Lock()
	defer s.pendingMu.Unlock()
	for _, o := range orders {
		s.pendingBySymbol[o.Symbol] = append(s.pendingBySymbol[o.Symbol], o)
	}
	log.Printf("[trading] loaded %d pending limit orders into cache", len(orders))
}

// LoadOpenPositions loads all open positions from DB into memory cache on startup.
func (s *TradingService) LoadOpenPositions(ctx context.Context) {
	positions, err := s.positionRepo.ListAllOpen(ctx)
	if err != nil {
		log.Printf("[trading] failed to load open positions: %v", err)
		return
	}
	s.posMu.Lock()
	defer s.posMu.Unlock()
	for _, p := range positions {
		// For isolated margin, ensure liq_price is correct in DB
		if p.MarginMode == "isolated" {
			newLiq := calcLiqPrice(p.EntryPrice, p.Side, p.Qty, p.MarginAmount, "isolated", 0)
			p.LiqPrice = &newLiq
			_ = s.positionRepo.UpdateLiqPrice(ctx, p.ID, newLiq)
		}
		// For cross margin, liq_price is calculated in real-time (not stored)

		cp := cachedPosition{
			UserID:        p.UserID,
			PositionID:    p.ID,
			Symbol:        p.Symbol,
			Side:          p.Side,
			Qty:           p.Qty,
			EntryPrice:    p.EntryPrice,
			Leverage:      p.Leverage,
			MarginAmount:  p.MarginAmount,
			MarginMode:    p.MarginMode,
			LiqPrice:      p.LiqPrice,
			TpPrice:       p.TpPrice,
			SlPrice:       p.SlPrice,
			IsCopyTrade:   p.IsCopyTrade,
			CopyTradingID: p.CopyTradingID,
			OpenFee:       p.OpenFee,
			CloseFee:      p.CloseFee,
			RealizedPnl:   p.RealizedPnl,
		}
		s.openBySymbol[p.Symbol] = append(s.openBySymbol[p.Symbol], cp)
	}
	log.Printf("[trading] loaded %d open positions into cache", len(positions))
}

// addPositionToCache adds or updates a position in the in-memory cache.
func (s *TradingService) addPositionToCache(p *model.Position) {
	cp := cachedPosition{
		UserID:        p.UserID,
		PositionID:    p.ID,
		Symbol:        p.Symbol,
		Side:          p.Side,
		Qty:           p.Qty,
		EntryPrice:    p.EntryPrice,
		Leverage:      p.Leverage,
		MarginAmount:  p.MarginAmount,
		MarginMode:    p.MarginMode,
		LiqPrice:      p.LiqPrice,
		TpPrice:       p.TpPrice,
		SlPrice:       p.SlPrice,
		IsCopyTrade:   p.IsCopyTrade,
		CopyTradingID: p.CopyTradingID,
		OpenFee:       p.OpenFee,
		CloseFee:      p.CloseFee,
		RealizedPnl:   p.RealizedPnl,
	}
	s.posMu.Lock()
	defer s.posMu.Unlock()
	// Replace existing or append
	existing := s.openBySymbol[p.Symbol]
	for i, c := range existing {
		if c.PositionID == p.ID {
			existing[i] = cp
			return
		}
	}
	s.openBySymbol[p.Symbol] = append(existing, cp)
}

// removePositionFromCache removes a position from the in-memory cache.
func (s *TradingService) removePositionFromCache(symbol, positionID string) {
	s.posMu.Lock()
	defer s.posMu.Unlock()
	positions := s.openBySymbol[symbol]
	for i, c := range positions {
		if c.PositionID == positionID {
			s.openBySymbol[symbol] = append(positions[:i], positions[i+1:]...)
			return
		}
	}
}

// OnPriceUpdate is called by MarketHub on every price tick.
// It checks if any pending limit orders for this symbol should be filled,
// then pushes real-time PnL updates for all open positions of this symbol.
func (s *TradingService) OnPriceUpdate(symbol string, price float64) {
	// Update in-memory price cache
	s.priceMu.Lock()
	s.priceCache[symbol] = price
	s.priceMu.Unlock()

	// Check and fill pending limit orders
	s.pendingMu.RLock()
	pending, ok := s.pendingBySymbol[symbol]
	s.pendingMu.RUnlock()

	if ok && len(pending) > 0 {
		var toFill []model.Order
		s.pendingMu.Lock()
		remaining := pending[:0]
		for _, o := range pending {
			shouldFill := false
			if o.Side == "long" && o.Price != nil && price <= *o.Price {
				shouldFill = true
			} else if o.Side == "short" && o.Price != nil && price >= *o.Price {
				shouldFill = true
			}
			if shouldFill {
				toFill = append(toFill, o)
			} else {
				remaining = append(remaining, o)
			}
		}
		s.pendingBySymbol[symbol] = remaining
		s.pendingMu.Unlock()

		ctx := context.Background()
		for _, o := range toFill {
			fillPrice := *o.Price
			if err := s.fillLimitOrder(ctx, &o, fillPrice); err != nil {
				log.Printf("[trading] failed to fill limit order %s: %v", o.ID, err)
				s.pendingMu.Lock()
				s.pendingBySymbol[o.Symbol] = append(s.pendingBySymbol[o.Symbol], o)
				s.pendingMu.Unlock()
			}
		}
	}

	// Push real-time PnL updates for all open positions of this symbol
	s.posMu.RLock()
	openPositions := make([]cachedPosition, len(s.openBySymbol[symbol]))
	copy(openPositions, s.openBySymbol[symbol])

	// For cross margin: pre-compute total equity per user
	// totalEquity = balance + frozen + all unrealized PnL from ALL cross positions (all symbols)
	type userEquityInfo struct {
		totalEquity float64
		allCross    []cachedPosition
	}
	equityCache := make(map[string]*userEquityInfo)
	mmr := 0.005

	// Collect users with cross positions in current symbol
	crossUsers := make(map[string]bool)
	for _, cp := range openPositions {
		if cp.MarginMode == "cross" {
			crossUsers[cp.UserID] = true
		}
	}

	// For each user with cross positions, gather ALL their cross positions across all symbols
	for uid := range crossUsers {
		info := &userEquityInfo{}
		for sym, positions := range s.openBySymbol {
			for _, p := range positions {
				if p.UserID != uid || p.MarginMode != "cross" {
					continue
				}
				var symPrice float64
				if sym == symbol {
					symPrice = price
				} else {
					symPrice, _ = s.getPrice(sym)
				}
				var pnl float64
				if symPrice > 0 {
					if p.Side == "long" {
						pnl = (symPrice - p.EntryPrice) * p.Qty
					} else {
						pnl = (p.EntryPrice - symPrice) * p.Qty
					}
				}
				info.totalEquity += pnl
				info.allCross = append(info.allCross, p)
			}
		}
		equityCache[uid] = info
	}
	s.posMu.RUnlock()

	var toLiquidate []cachedPosition
	var toTPSL []cachedPosition
	ctx := context.Background()

	// Now fetch wallet balances (outside of posMu lock to avoid deadlock)
	for uid, info := range equityCache {
		if w, wErr := s.walletRepo.GetWallet(ctx, uid); wErr == nil {
			info.totalEquity += w.Balance + w.Frozen
		}
	}

	for _, cp := range openPositions {
		// For cross margin, recalculate liq price using total equity
		if cp.MarginMode == "cross" {
			if info, ok := equityCache[cp.UserID]; ok {
				// Available for this position = totalEquity - other positions' maintenance margin
				var otherMM float64
				for _, other := range info.allCross {
					if other.PositionID == cp.PositionID {
						continue
					}
					// Use correct price for each symbol
					var otherPrice float64
					if other.Symbol == symbol {
						otherPrice = price
					} else {
						otherPrice, _ = s.getPrice(other.Symbol)
					}
					if otherPrice > 0 {
						otherMM += otherPrice * other.Qty * mmr
					}
				}
				equity := info.totalEquity - otherMM
				liq := calcLiqPrice(cp.EntryPrice, cp.Side, cp.Qty, cp.MarginAmount, "cross", equity)
				cp.LiqPrice = &liq
			}
		}

		// Check if price hit liquidation level
		if cp.LiqPrice != nil {
			liq := *cp.LiqPrice
			if (cp.Side == "long" && price <= liq) || (cp.Side == "short" && price >= liq) {
				toLiquidate = append(toLiquidate, cp)
				continue
			}
		}

		// Check TP/SL triggers
		tpHit := cp.TpPrice != nil && ((cp.Side == "long" && price >= *cp.TpPrice) || (cp.Side == "short" && price <= *cp.TpPrice))
		slHit := cp.SlPrice != nil && ((cp.Side == "long" && price <= *cp.SlPrice) || (cp.Side == "short" && price >= *cp.SlPrice))
		if tpHit || slHit {
			toTPSL = append(toTPSL, cp)
			continue
		}

		var pnl float64
		if cp.Side == "long" {
			pnl = (price - cp.EntryPrice) * cp.Qty
		} else {
			pnl = (cp.EntryPrice - price) * cp.Qty
		}
		var roe float64
		if cp.MarginAmount > 0 {
			roe = (pnl / cp.MarginAmount) * 100
		}

		pos := &model.Position{
			ID:            cp.PositionID,
			UserID:        cp.UserID,
			Symbol:        cp.Symbol,
			Side:          cp.Side,
			Qty:           cp.Qty,
			EntryPrice:    cp.EntryPrice,
			Leverage:      cp.Leverage,
			MarginMode:    cp.MarginMode,
			MarginAmount:  cp.MarginAmount,
			LiqPrice:      cp.LiqPrice,
			TpPrice:       cp.TpPrice,
			SlPrice:       cp.SlPrice,
			Status:        "open",
			CurrentPrice:  price,
			UnrealizedPnl: pnl,
			ROE:           roe,
			IsCopyTrade:   cp.IsCopyTrade,
			OpenFee:       cp.OpenFee,
			CloseFee:      cp.CloseFee,
			RealizedPnl:   cp.RealizedPnl,
		}
		s.pushPositionUpdate(cp.UserID, pos)
	}

	// Auto-liquidate positions that hit liquidation price
	if len(toLiquidate) > 0 {
		ctx := context.Background()
		for _, cp := range toLiquidate {
			log.Printf("[trading] LIQUIDATION triggered: user=%s pos=%s %s %s @ %.4f (liq=%.4f)",
				cp.UserID, cp.PositionID, cp.Side, cp.Symbol, price, *cp.LiqPrice)
			s.liquidatePosition(ctx, cp, price)
		}
	}

	// Auto-close positions that hit TP/SL
	if len(toTPSL) > 0 {
		ctx := context.Background()
		for _, cp := range toTPSL {
			reason := "TP"
			if cp.SlPrice != nil && ((cp.Side == "long" && price <= *cp.SlPrice) || (cp.Side == "short" && price >= *cp.SlPrice)) {
				reason = "SL"
			}
			log.Printf("[trading] %s triggered: user=%s pos=%s %s %s @ %.4f", reason,
				cp.UserID, cp.PositionID, cp.Side, cp.Symbol, price)
			s.closePositionByTPSL(ctx, cp, price)
		}
	}
}

// PlaceOrder handles both market and limit orders.
func (s *TradingService) PlaceOrder(ctx context.Context, userID string, req *model.PlaceOrderRequest) (*model.Order, error) {
	if req.Qty <= 0 {
		return nil, fmt.Errorf("quantity must be positive")
	}
	if req.Side != "long" && req.Side != "short" {
		return nil, fmt.Errorf("side must be 'long' or 'short'")
	}
	if req.Leverage <= 0 {
		req.Leverage = 1
	}
	if req.MarginMode == "" {
		req.MarginMode = "cross"
	}

	// Ensure wallet exists
	_, err := s.walletRepo.EnsureWallet(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("wallet error: %w", err)
	}

	switch req.Type {
	case "market":
		return s.placeMarketOrder(ctx, userID, req)
	case "limit":
		if req.Price == nil || *req.Price <= 0 {
			return nil, fmt.Errorf("limit price required and must be positive")
		}
		return s.placeLimitOrder(ctx, userID, req)
	default:
		return nil, fmt.Errorf("order type must be 'market' or 'limit'")
	}
}

func (s *TradingService) placeMarketOrder(ctx context.Context, userID string, req *model.PlaceOrderRequest) (*model.Order, error) {
	// Get latest price
	currentPrice, err := s.getPrice(req.Symbol)
	if err != nil {
		return nil, fmt.Errorf("price unavailable for %s: %w", req.Symbol, err)
	}

	// Calculate taker fee rate
	vipLevel, _ := s.userRepo.GetVipLevel(ctx, userID)
	_, takerRate := s.getVipFeeRates(vipLevel)

	// Pre-check: if balance can't cover margin + fee, auto-shrink qty to fit
	wallet, err := s.walletRepo.GetWallet(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("get wallet: %w", err)
	}
	qty := req.Qty
	margin := (qty * currentPrice) / float64(req.Leverage)
	openFee := math.Round(currentPrice*qty*takerRate*1e8) / 1e8

	if wallet.Balance < margin+openFee {
		// Shrink qty to fit available balance: balance = margin + fee = qty*price/lev + qty*price*feeRate
		// qty = balance / (price/lev + price*feeRate) = balance / (price * (1/lev + feeRate))
		maxQty := wallet.Balance / (currentPrice * (1.0/float64(req.Leverage) + takerRate))
		if maxQty <= 0 {
			return nil, fmt.Errorf("insufficient balance")
		}
		// Truncate to 8 decimals to avoid precision issues
		qty = math.Floor(maxQty*1e8) / 1e8
		margin = (qty * currentPrice) / float64(req.Leverage)
		openFee = math.Round(currentPrice*qty*takerRate*1e8) / 1e8
		req.Qty = qty
		log.Printf("[trading] auto-shrunk qty to %.8f (margin=%.2f fee=%.2f balance=%.2f)", qty, margin, openFee, wallet.Balance)
	}

	// Freeze margin
	if err := s.walletRepo.FreezeMargin(ctx, userID, margin); err != nil {
		return nil, fmt.Errorf("%w", err)
	}

	// Charge opening fee from balance
	if openFee > 0 {
		if err := s.walletRepo.ChargeFee(ctx, userID, openFee, "", "Open position fee (taker)"); err != nil {
			s.walletRepo.UnfreezeMargin(ctx, userID, margin)
			return nil, fmt.Errorf("insufficient balance for fee: %w", err)
		}
	}

	// Calculate liquidation price.
	// For cross margin, derive equity locally from the pre-freeze wallet we already
	// fetched above. After FreezeMargin+ChargeFee:
	//   new_balance + new_frozen = (old_balance - margin - openFee) + (old_frozen + margin)
	//                            = old_balance + old_frozen - openFee
	// so one DB round-trip is avoidable here.
	var liqEquity float64
	if req.MarginMode == "cross" {
		liqEquity = wallet.Balance + wallet.Frozen - openFee
	}
	liqPrice := calcLiqPrice(currentPrice, req.Side, req.Qty, margin, req.MarginMode, liqEquity)

	now := time.Now()
	order := &model.Order{
		UserID:       userID,
		Symbol:       req.Symbol,
		Side:         req.Side,
		OrderType:    "market",
		Qty:          req.Qty,
		FilledPrice:  &currentPrice,
		Leverage:     req.Leverage,
		MarginMode:   req.MarginMode,
		MarginAmount: margin,
		Status:       "filled",
		Fee:          openFee,
		FilledAt:     &now,
	}

	if err := s.orderRepo.Create(ctx, order); err != nil {
		s.walletRepo.UnfreezeMargin(ctx, userID, margin)
		return nil, fmt.Errorf("create order: %w", err)
	}

	// Upsert position
	pos := &model.Position{
		UserID:       userID,
		Symbol:       req.Symbol,
		Side:         req.Side,
		Qty:          req.Qty,
		EntryPrice:   currentPrice,
		Leverage:     req.Leverage,
		MarginMode:   req.MarginMode,
		MarginAmount: margin,
		LiqPrice:     &liqPrice,
		TpPrice:      req.TpPrice,
		SlPrice:      req.SlPrice,
		OpenFee:      openFee,
	}
	pos, err = s.positionRepo.UpsertPosition(ctx, pos)
	if err != nil {
		s.walletRepo.UnfreezeMargin(ctx, userID, margin)
		log.Printf("[trading] upsert position failed, unfroze margin=%.4f for user=%s: %v", margin, userID, err)
		return nil, fmt.Errorf("upsert position: %w", err)
	}

	// Set TP/SL if provided
	if req.TpPrice != nil || req.SlPrice != nil {
		s.positionRepo.UpdateTPSL(ctx, pos.ID, req.TpPrice, req.SlPrice)
		pos.TpPrice = req.TpPrice
		pos.SlPrice = req.SlPrice
	}

	// Recalculate liq price based on merged position data.
	// UpsertPosition does not touch the wallet, so the derived equity from above
	// is still valid (old_balance + old_frozen - openFee).
	var liqEquity2 float64
	if pos.MarginMode == "cross" {
		liqEquity2 = wallet.Balance + wallet.Frozen - openFee
	}
	newLiq := calcLiqPrice(pos.EntryPrice, pos.Side, pos.Qty, pos.MarginAmount, pos.MarginMode, liqEquity2)
	pos.LiqPrice = &newLiq
	s.positionRepo.UpdateLiqPrice(ctx, pos.ID, newLiq)

	// Enrich position with current price info
	pos.CurrentPrice = currentPrice
	pos.UnrealizedPnl = 0
	pos.ROE = 0

	// Update position cache
	s.addPositionToCache(pos)

	// Push WebSocket events
	wallet, _ = s.walletRepo.GetWallet(ctx, userID)
	s.pushOrderFilled(userID, order)
	s.pushPositionUpdate(userID, pos)
	if wallet != nil {
		s.pushBalanceUpdate(userID, wallet)
	}

	// Trigger copy trading for followers (async, non-blocking)
	if !order.IsCopyTrade {
		log.Printf("[copy-trading] market order filled, triggering copy open: user=%s isCopyTrade=%v", userID, order.IsCopyTrade)
		go s.triggerCopyOpen(context.Background(), userID, order, pos)
	} else {
		log.Printf("[copy-trading] skipping trigger: order is already a copy trade")
	}

	return order, nil
}

func (s *TradingService) placeLimitOrder(ctx context.Context, userID string, req *model.PlaceOrderRequest) (*model.Order, error) {
	limitPrice := *req.Price
	margin := (req.Qty * limitPrice) / float64(req.Leverage)

	if err := s.walletRepo.FreezeMargin(ctx, userID, margin); err != nil {
		return nil, fmt.Errorf("%w", err)
	}

	order := &model.Order{
		UserID:       userID,
		Symbol:       req.Symbol,
		Side:         req.Side,
		OrderType:    "limit",
		Qty:          req.Qty,
		Price:        req.Price,
		Leverage:     req.Leverage,
		MarginMode:   req.MarginMode,
		MarginAmount: margin,
		Status:       "pending",
	}

	if err := s.orderRepo.Create(ctx, order); err != nil {
		s.walletRepo.UnfreezeMargin(ctx, userID, margin)
		return nil, fmt.Errorf("create order: %w", err)
	}

	// Add to in-memory cache for instant trigger
	s.pendingMu.Lock()
	s.pendingBySymbol[req.Symbol] = append(s.pendingBySymbol[req.Symbol], *order)
	s.pendingMu.Unlock()

	// Push events
	wallet, _ := s.walletRepo.GetWallet(ctx, userID)
	s.pushOrderCreated(userID, order)
	if wallet != nil {
		s.pushBalanceUpdate(userID, wallet)
	}

	return order, nil
}

func (s *TradingService) fillLimitOrder(ctx context.Context, o *model.Order, fillPrice float64) error {
	// Calculate maker fee (limit order = maker)
	vipLevel, _ := s.userRepo.GetVipLevel(ctx, o.UserID)
	makerRate, _ := s.getVipFeeRates(vipLevel)
	openFee := math.Round(fillPrice*o.Qty*makerRate*1e8) / 1e8

	// Charge fee (if balance insufficient, set fee to 0 — margin already frozen)
	if openFee > 0 {
		if err := s.walletRepo.ChargeFee(ctx, o.UserID, openFee, o.ID, "Open position fee (maker)"); err != nil {
			log.Printf("[trading] limit fill: insufficient balance for fee, user=%s fee=%.4f, skipping fee", o.UserID, openFee)
			openFee = 0
		}
	}

	if err := s.orderRepo.FillOrder(ctx, o.ID, fillPrice, openFee); err != nil {
		return err
	}

	var liqEquity float64
	if o.MarginMode == "cross" {
		if w, err := s.walletRepo.GetWallet(ctx, o.UserID); err == nil {
			liqEquity = w.Balance + w.Frozen
		}
	}
	liqPrice := calcLiqPrice(fillPrice, o.Side, o.Qty, o.MarginAmount, o.MarginMode, liqEquity)

	pos := &model.Position{
		UserID:       o.UserID,
		Symbol:       o.Symbol,
		Side:         o.Side,
		Qty:          o.Qty,
		EntryPrice:   fillPrice,
		Leverage:     o.Leverage,
		MarginMode:   o.MarginMode,
		MarginAmount: o.MarginAmount,
		LiqPrice:     &liqPrice,
		OpenFee:      openFee,
	}
	pos, err := s.positionRepo.UpsertPosition(ctx, pos)
	if err != nil {
		s.walletRepo.UnfreezeMargin(ctx, o.UserID, o.MarginAmount)
		log.Printf("[trading] limit fill upsert failed, unfroze margin=%.4f for user=%s: %v", o.MarginAmount, o.UserID, err)
		return fmt.Errorf("upsert position for limit fill: %w", err)
	}

	// Recalculate liq price based on merged position data
	var liqEquity2 float64
	if pos.MarginMode == "cross" {
		if w, err := s.walletRepo.GetWallet(ctx, o.UserID); err == nil {
			liqEquity2 = w.Balance + w.Frozen
		}
	}
	newLiq := calcLiqPrice(pos.EntryPrice, pos.Side, pos.Qty, pos.MarginAmount, pos.MarginMode, liqEquity2)
	pos.LiqPrice = &newLiq
	s.positionRepo.UpdateLiqPrice(ctx, pos.ID, newLiq)

	pos.CurrentPrice = fillPrice
	pos.UnrealizedPnl = 0
	pos.ROE = 0

	// Update position cache
	s.addPositionToCache(pos)

	o.Status = "filled"
	o.FilledPrice = &fillPrice
	now := time.Now()
	o.FilledAt = &now

	wallet, _ := s.walletRepo.GetWallet(ctx, o.UserID)
	s.pushOrderFilled(o.UserID, o)
	s.pushPositionUpdate(o.UserID, pos)
	if wallet != nil {
		s.pushBalanceUpdate(o.UserID, wallet)
	}

	log.Printf("[trading] limit order filled: %s %s %s @ %.2f", o.ID, o.Side, o.Symbol, fillPrice)

	// Trigger copy trading for followers (async, non-blocking)
	if !o.IsCopyTrade {
		go s.triggerCopyOpen(context.Background(), o.UserID, o, pos)
	}

	return nil
}

// ClosePosition closes an open position at the current market price.
func (s *TradingService) ClosePosition(ctx context.Context, userID, positionID string) (*model.Position, error) {
	pos, err := s.positionRepo.GetByID(ctx, positionID)
	if err != nil {
		return nil, fmt.Errorf("position not found: %w", err)
	}
	if pos.UserID != userID {
		return nil, fmt.Errorf("unauthorized")
	}
	if pos.Status != "open" {
		return nil, fmt.Errorf("position is not open")
	}

	currentPrice, err := s.getPrice(pos.Symbol)
	if err != nil {
		return nil, fmt.Errorf("price unavailable: %w", err)
	}

	// Calculate PnL
	var pnl float64
	if pos.Side == "long" {
		pnl = (currentPrice - pos.EntryPrice) * pos.Qty
	} else {
		pnl = (pos.EntryPrice - currentPrice) * pos.Qty
	}

	// Calculate close fee (taker)
	vipLevel, _ := s.userRepo.GetVipLevel(ctx, userID)
	_, takerRate := s.getVipFeeRates(vipLevel)
	closeFee := math.Round(currentPrice*pos.Qty*takerRate*1e8) / 1e8

	// Close position FIRST (atomic status check prevents double-close race)
	if err := s.positionRepo.ClosePosition(ctx, positionID, pnl, currentPrice, closeFee); err != nil {
		return nil, fmt.Errorf("close position: %w", err)
	}

	// 跟单仓位 vs 普通仓位的结算分流：
	//   普通仓位 → wallet.SettleTrade
	//   跟单仓位 → bucket.SettleToBucket（钱永远不出主钱包）
	//             ProfitShareEnabled 时走 SettleToBucketWithCommission，自动按
	//             snapshot rate + HWM 算分润；rate=0 的存量行天然 skip。
	var psResult *repository.ProfitShareResult
	if pos.IsCopyTrade && pos.CopyTradingID != nil && s.traderRepo != nil {
		if s.ProfitShareEnabled {
			ct, ctErr := s.traderRepo.GetCopyTradingByID(ctx, *pos.CopyTradingID)
			if ctErr != nil {
				log.Printf("[trading] CRITICAL: copy position %s closed but copy_trading lookup failed: %v", positionID, ctErr)
				return nil, fmt.Errorf("settle to bucket: load ct: %w", ctErr)
			}
			res, sErr := s.traderRepo.SettleToBucketWithCommission(
				ctx, *pos.CopyTradingID, ct.TraderID, positionID,
				pos.MarginAmount, pnl, closeFee,
			)
			if sErr != nil {
				log.Printf("[trading] CRITICAL: copy position %s closed but bucket settle (commission) failed: %v", positionID, sErr)
				return nil, fmt.Errorf("settle to bucket commission: %w", sErr)
			}
			psResult = res
		} else {
			if err := s.traderRepo.SettleToBucket(ctx, *pos.CopyTradingID, pos.MarginAmount, pnl, closeFee); err != nil {
				log.Printf("[trading] CRITICAL: copy position %s closed but bucket settle failed: %v", positionID, err)
				return nil, fmt.Errorf("settle to bucket: %w", err)
			}
		}
	} else {
		if err := s.walletRepo.SettleTrade(ctx, userID, pos.MarginAmount, pnl, closeFee); err != nil {
			log.Printf("[trading] CRITICAL: position %s closed but settle failed: %v", positionID, err)
			return nil, fmt.Errorf("settle trade: %w", err)
		}
	}

	pos.Status = "closed"
	pos.RealizedPnl = pnl
	pos.CloseFee += closeFee
	pos.ClosePrice = currentPrice
	pos.CurrentPrice = currentPrice
	pos.UnrealizedPnl = 0

	// Remove from position cache
	s.removePositionFromCache(pos.Symbol, positionID)

	s.pushPositionClosed(userID, pos)
	// 跟单仓位主钱包没动，不必刷 balance；普通仓位才推
	if !pos.IsCopyTrade {
		wallet, _ := s.walletRepo.GetWallet(ctx, userID)
		if wallet != nil {
			s.pushBalanceUpdate(userID, wallet)
		}
	}

	// 分润 WS 推送：成功抽分润时给 trader 推 profit_share_received，
	// 给 follower 推 copy_profit_share_paid（带 hwm/bucket 余额）。
	if psResult != nil {
		s.pushProfitShareEvents(ctx, pos, psResult)
	}

	// Trigger copy close for followers
	if !pos.IsCopyTrade {
		go s.triggerCopyClose(context.Background(), userID, positionID)
	}

	return pos, nil
}

// CloseAllByCopyTrading market-closes every open follower position belonging
// to a single copy_trading subscription. Used by the force-unfollow flow so
// the user can drain the bucket and stop following in one click.
//
// Each close runs through the normal `ClosePosition` path, which means PnL
// settles to the bucket (not the wallet) — by the time this returns, the
// subscription's frozen_capital is back to 0 and available_capital reflects
// the realized PnL. We don't abort on individual close errors: we collect the
// count of successes/failures so the caller can report partial progress.
func (s *TradingService) CloseAllByCopyTrading(ctx context.Context, userID, copyTradingID string) (closed int, failed int, lastErr error) {
	positions, err := s.positionRepo.ListOpenByCopyTrading(ctx, copyTradingID)
	if err != nil {
		return 0, 0, fmt.Errorf("list open positions: %w", err)
	}
	for _, p := range positions {
		// Defensive: only close positions that belong to this user. The repo
		// query already filters by copy_trading_id, but copy_trading_id is
		// per-subscription so user_id should match — re-checking keeps a stray
		// row from being closed under the wrong identity.
		if p.UserID != userID {
			continue
		}
		if _, cerr := s.ClosePosition(ctx, userID, p.ID); cerr != nil {
			failed++
			lastErr = cerr
			log.Printf("[copy-trading] CloseAllByCopyTrading: position %s close failed: %v", p.ID, cerr)
			continue
		}
		closed++
	}
	return closed, failed, lastErr
}

// PartialClosePosition closes a portion of an open position.
func (s *TradingService) PartialClosePosition(ctx context.Context, userID, positionID string, closeQty float64) (*model.Position, error) {
	pos, err := s.positionRepo.GetByID(ctx, positionID)
	if err != nil {
		return nil, fmt.Errorf("position not found: %w", err)
	}
	if pos.UserID != userID {
		return nil, fmt.Errorf("unauthorized")
	}
	if pos.Status != "open" {
		return nil, fmt.Errorf("position is not open")
	}
	if closeQty <= 0 {
		return nil, fmt.Errorf("close quantity must be positive")
	}
	if closeQty >= pos.Qty {
		// Full close
		return s.ClosePosition(ctx, userID, positionID)
	}

	currentPrice, err := s.getPrice(pos.Symbol)
	if err != nil {
		return nil, fmt.Errorf("price unavailable: %w", err)
	}

	// PnL for the closed portion
	var pnl float64
	if pos.Side == "long" {
		pnl = (currentPrice - pos.EntryPrice) * closeQty
	} else {
		pnl = (pos.EntryPrice - currentPrice) * closeQty
	}

	// Calculate close fee on partial qty (taker)
	vipLevel, _ := s.userRepo.GetVipLevel(ctx, userID)
	_, takerRate := s.getVipFeeRates(vipLevel)
	closeFee := math.Round(currentPrice*closeQty*takerRate*1e8) / 1e8

	// Proportional margin release
	closeFraction := closeQty / pos.Qty
	releasedMargin := pos.MarginAmount * closeFraction
	remainingQty := pos.Qty - closeQty
	remainingMargin := pos.MarginAmount - releasedMargin

	// Reduce position FIRST (atomic status check prevents race condition)
	if err := s.positionRepo.ReducePosition(ctx, positionID, remainingQty, remainingMargin, closeFee, pnl); err != nil {
		return nil, fmt.Errorf("reduce position: %w", err)
	}

	// 跟单仓位 vs 普通仓位结算分流（部分平仓走与全平相同的分润逻辑）
	var psResult *repository.ProfitShareResult
	if pos.IsCopyTrade && pos.CopyTradingID != nil && s.traderRepo != nil {
		if s.ProfitShareEnabled {
			ct, ctErr := s.traderRepo.GetCopyTradingByID(ctx, *pos.CopyTradingID)
			if ctErr != nil {
				log.Printf("[trading] CRITICAL: copy position %s reduced but copy_trading lookup failed: %v", positionID, ctErr)
				return nil, fmt.Errorf("settle partial: load ct: %w", ctErr)
			}
			res, sErr := s.traderRepo.SettleToBucketWithCommission(
				ctx, *pos.CopyTradingID, ct.TraderID, positionID,
				releasedMargin, pnl, closeFee,
			)
			if sErr != nil {
				log.Printf("[trading] CRITICAL: copy position %s reduced but bucket settle (commission) failed: %v", positionID, sErr)
				return nil, fmt.Errorf("settle partial close commission: %w", sErr)
			}
			psResult = res
		} else {
			if err := s.traderRepo.SettleToBucket(ctx, *pos.CopyTradingID, releasedMargin, pnl, closeFee); err != nil {
				log.Printf("[trading] CRITICAL: copy position %s reduced but bucket settle failed: %v", positionID, err)
				return nil, fmt.Errorf("settle partial close to bucket: %w", err)
			}
		}
	} else {
		if err := s.walletRepo.SettleTrade(ctx, userID, releasedMargin, pnl, closeFee); err != nil {
			log.Printf("[trading] CRITICAL: position %s reduced but settle failed: %v", positionID, err)
			return nil, fmt.Errorf("settle partial close: %w", err)
		}
	}
	// 部分平仓也推分润事件（即使 share=0 也会更新 follower 的 hwm/bucket 余额）
	if psResult != nil {
		s.pushProfitShareEvents(ctx, pos, psResult)
	}

	// Update cache
	s.posMu.Lock()
	if positions, ok := s.openBySymbol[pos.Symbol]; ok {
		for i, cp := range positions {
			if cp.PositionID == positionID {
				positions[i].Qty = remainingQty
				positions[i].MarginAmount = remainingMargin
				positions[i].CloseFee += closeFee
				positions[i].RealizedPnl += pnl
				break
			}
		}
	}
	s.posMu.Unlock()

	// Return updated position
	pos.Qty = remainingQty
	pos.MarginAmount = remainingMargin
	pos.CurrentPrice = currentPrice
	if pos.Side == "long" {
		pos.UnrealizedPnl = (currentPrice - pos.EntryPrice) * remainingQty
	} else {
		pos.UnrealizedPnl = (pos.EntryPrice - currentPrice) * remainingQty
	}
	if remainingMargin > 0 {
		pos.ROE = (pos.UnrealizedPnl / remainingMargin) * 100
	}

	wallet, _ := s.walletRepo.GetWallet(ctx, userID)
	s.pushPositionUpdate(userID, pos)
	if wallet != nil {
		s.pushBalanceUpdate(userID, wallet)
	}

	// Trigger copy partial close for followers
	if !pos.IsCopyTrade {
		go s.triggerCopyPartialClose(context.Background(), userID, positionID, closeFraction)
	}

	return pos, nil
}

// liquidatePosition force-closes a position at the liquidation price.
// The entire margin is lost (PnL = -marginAmount).
func (s *TradingService) liquidatePosition(ctx context.Context, cp cachedPosition, currentPrice float64) {
	// PnL = loss of entire margin
	pnl := -cp.MarginAmount

	// Liquidate position FIRST (atomic status check prevents double-liquidation race)
	if err := s.positionRepo.LiquidatePosition(ctx, cp.PositionID, pnl, currentPrice); err != nil {
		log.Printf("[trading] liquidation close error for %s: %v (likely already closed)", cp.PositionID, err)
		return
	}

	// 跟单仓位 vs 普通仓位的结算分流（与 ClosePosition 保持一致）：
	//   普通仓位 → wallet.SettleTrade
	//   跟单仓位 → bucket.SettleToBucket（margin/pnl 都在 copy_trading 子账户里结算，
	//             钱永远不动主钱包，避免误伤其它仓位的 wallet.frozen）
	// 强平 pnl=-margin，无盈利，因此不需要走分润路径（share 只在 equity 创新高时才 > 0）。
	if cp.IsCopyTrade && cp.CopyTradingID != nil && s.traderRepo != nil {
		if err := s.traderRepo.SettleToBucket(ctx, *cp.CopyTradingID, cp.MarginAmount, pnl, 0); err != nil {
			log.Printf("[trading] CRITICAL: copy position %s liquidated but bucket settle failed: %v", cp.PositionID, err)
			return
		}
	} else {
		if err := s.walletRepo.SettleTrade(ctx, cp.UserID, cp.MarginAmount, pnl, 0); err != nil {
			log.Printf("[trading] CRITICAL: position %s liquidated but settle failed: %v", cp.PositionID, err)
			return
		}
	}

	// Remove from cache
	s.removePositionFromCache(cp.Symbol, cp.PositionID)

	pos := &model.Position{
		ID:            cp.PositionID,
		UserID:        cp.UserID,
		Symbol:        cp.Symbol,
		Side:          cp.Side,
		Qty:           cp.Qty,
		EntryPrice:    cp.EntryPrice,
		ClosePrice:    currentPrice,
		Leverage:      cp.Leverage,
		MarginMode:    cp.MarginMode,
		MarginAmount:  cp.MarginAmount,
		LiqPrice:      cp.LiqPrice,
		Status:        "liquidated",
		RealizedPnl:   pnl,
		CurrentPrice:  currentPrice,
		IsCopyTrade:   cp.IsCopyTrade,
		CopyTradingID: cp.CopyTradingID,
	}

	// Push liquidation event to user
	s.pusher.PushToUser(cp.UserID, map[string]any{
		"type": "position_liquidated",
		"data": pos,
	})

	// 跟单仓位主钱包没动，不必刷 balance；普通仓位才推
	if !cp.IsCopyTrade {
		wallet, _ := s.walletRepo.GetWallet(ctx, cp.UserID)
		if wallet != nil {
			s.pushBalanceUpdate(cp.UserID, wallet)
		}
	}

	log.Printf("[trading] LIQUIDATED: user=%s pos=%s %s %s, margin=%.2f lost",
		cp.UserID, cp.PositionID, cp.Side, cp.Symbol, cp.MarginAmount)

	// Trigger copy close for followers
	if !cp.IsCopyTrade {
		go s.triggerCopyClose(context.Background(), cp.UserID, cp.PositionID)
	}
}

// closePositionByTPSL auto-closes a position when TP or SL price is hit.
func (s *TradingService) closePositionByTPSL(ctx context.Context, cp cachedPosition, currentPrice float64) {
	var pnl float64
	if cp.Side == "long" {
		pnl = (currentPrice - cp.EntryPrice) * cp.Qty
	} else {
		pnl = (cp.EntryPrice - currentPrice) * cp.Qty
	}

	// Calculate close fee (taker)
	vipLevel, _ := s.userRepo.GetVipLevel(ctx, cp.UserID)
	_, takerRate := s.getVipFeeRates(vipLevel)
	closeFee := math.Round(currentPrice*cp.Qty*takerRate*1e8) / 1e8

	// Close position FIRST (atomic status check prevents double-close race)
	if err := s.positionRepo.ClosePosition(ctx, cp.PositionID, pnl, currentPrice, closeFee); err != nil {
		log.Printf("[trading] TP/SL close error for %s: %v (likely already closed)", cp.PositionID, err)
		return
	}

	// 跟单仓位 vs 普通仓位的结算分流（与 ClosePosition 完全一致，TP 可能盈利所以要走分润）：
	//   普通仓位 → wallet.SettleTrade
	//   跟单仓位 → bucket.SettleToBucket[WithCommission]（钱不出主钱包）
	var psResult *repository.ProfitShareResult
	if cp.IsCopyTrade && cp.CopyTradingID != nil && s.traderRepo != nil {
		if s.ProfitShareEnabled {
			ct, ctErr := s.traderRepo.GetCopyTradingByID(ctx, *cp.CopyTradingID)
			if ctErr != nil {
				log.Printf("[trading] CRITICAL: copy position %s TP/SL closed but copy_trading lookup failed: %v", cp.PositionID, ctErr)
				return
			}
			res, sErr := s.traderRepo.SettleToBucketWithCommission(
				ctx, *cp.CopyTradingID, ct.TraderID, cp.PositionID,
				cp.MarginAmount, pnl, closeFee,
			)
			if sErr != nil {
				log.Printf("[trading] CRITICAL: copy position %s TP/SL closed but bucket settle (commission) failed: %v", cp.PositionID, sErr)
				return
			}
			psResult = res
		} else {
			if err := s.traderRepo.SettleToBucket(ctx, *cp.CopyTradingID, cp.MarginAmount, pnl, closeFee); err != nil {
				log.Printf("[trading] CRITICAL: copy position %s TP/SL closed but bucket settle failed: %v", cp.PositionID, err)
				return
			}
		}
	} else {
		if err := s.walletRepo.SettleTrade(ctx, cp.UserID, cp.MarginAmount, pnl, closeFee); err != nil {
			log.Printf("[trading] CRITICAL: position %s TP/SL closed but settle failed: %v", cp.PositionID, err)
			return
		}
	}

	s.removePositionFromCache(cp.Symbol, cp.PositionID)

	pos := &model.Position{
		ID:            cp.PositionID,
		UserID:        cp.UserID,
		Symbol:        cp.Symbol,
		Side:          cp.Side,
		Qty:           cp.Qty,
		EntryPrice:    cp.EntryPrice,
		ClosePrice:    currentPrice,
		Leverage:      cp.Leverage,
		MarginMode:    cp.MarginMode,
		MarginAmount:  cp.MarginAmount,
		LiqPrice:      cp.LiqPrice,
		TpPrice:       cp.TpPrice,
		SlPrice:       cp.SlPrice,
		Status:        "closed",
		RealizedPnl:   pnl,
		CurrentPrice:  currentPrice,
		IsCopyTrade:   cp.IsCopyTrade,
		CopyTradingID: cp.CopyTradingID,
	}

	s.pushPositionClosed(cp.UserID, pos)
	// 跟单仓位主钱包没动，不必刷 balance；普通仓位才推
	if !cp.IsCopyTrade {
		wallet, _ := s.walletRepo.GetWallet(ctx, cp.UserID)
		if wallet != nil {
			s.pushBalanceUpdate(cp.UserID, wallet)
		}
	}

	// 分润 WS 推送（TP 盈利时可能有 share > 0）
	if psResult != nil {
		s.pushProfitShareEvents(ctx, pos, psResult)
	}

	log.Printf("[trading] TP/SL CLOSED: user=%s pos=%s %s %s @ %.4f, pnl=%.2f",
		cp.UserID, cp.PositionID, cp.Side, cp.Symbol, currentPrice, pnl)

	// Trigger copy close for followers
	if !cp.IsCopyTrade {
		go s.triggerCopyClose(context.Background(), cp.UserID, cp.PositionID)
	}
}

// CancelOrder cancels a pending limit order.
func (s *TradingService) CancelOrder(ctx context.Context, userID, orderID string) (*model.Order, error) {
	order, err := s.orderRepo.Cancel(ctx, orderID, userID)
	if err != nil {
		return nil, fmt.Errorf("cancel order: %w", err)
	}

	// Unfreeze margin
	if err := s.walletRepo.UnfreezeMargin(ctx, userID, order.MarginAmount); err != nil {
		return nil, fmt.Errorf("unfreeze margin: %w", err)
	}

	// Remove from in-memory cache
	s.pendingMu.Lock()
	pending := s.pendingBySymbol[order.Symbol]
	for i, o := range pending {
		if o.ID == orderID {
			s.pendingBySymbol[order.Symbol] = append(pending[:i], pending[i+1:]...)
			break
		}
	}
	s.pendingMu.Unlock()

	wallet, _ := s.walletRepo.GetWallet(ctx, userID)
	s.pushOrderCancelled(userID, order)
	if wallet != nil {
		s.pushBalanceUpdate(userID, wallet)
	}

	return order, nil
}

// GetAccountInfo returns the user's account overview.
func (s *TradingService) GetAccountInfo(ctx context.Context, userID string) (*model.AccountInfo, error) {
	wallet, err := s.walletRepo.EnsureWallet(ctx, userID)
	if err != nil {
		return nil, err
	}

	positions, err := s.positionRepo.ListOpen(ctx, userID)
	if err != nil {
		return nil, err
	}

	var totalUnrealizedPnl float64
	var totalMargin float64
	for _, p := range positions {
		price, err := s.getPrice(p.Symbol)
		if err != nil {
			continue
		}
		var pnl float64
		if p.Side == "long" {
			pnl = (price - p.EntryPrice) * p.Qty
		} else {
			pnl = (p.EntryPrice - price) * p.Qty
		}
		totalUnrealizedPnl += pnl
		totalMargin += p.MarginAmount
	}

	return &model.AccountInfo{
		Balance:       wallet.Balance,
		Frozen:        wallet.Frozen,
		Equity:        wallet.Balance + wallet.Frozen + totalUnrealizedPnl,
		MarginUsed:    totalMargin,
		Available:     wallet.Balance,
		UnrealizedPnl: totalUnrealizedPnl,
	}, nil
}

// ListPositionsWithPnL returns open positions enriched with unrealized PnL.
func (s *TradingService) ListPositionsWithPnL(ctx context.Context, userID string) ([]model.Position, error) {
	positions, err := s.positionRepo.ListOpen(ctx, userID)
	if err != nil {
		return nil, err
	}

	// First pass: compute unrealized PnL and current price for all positions
	for i := range positions {
		price, err := s.getPrice(positions[i].Symbol)
		if err != nil {
			continue
		}
		positions[i].CurrentPrice = price
		if positions[i].Side == "long" {
			positions[i].UnrealizedPnl = (price - positions[i].EntryPrice) * positions[i].Qty
		} else {
			positions[i].UnrealizedPnl = (positions[i].EntryPrice - price) * positions[i].Qty
		}
		if positions[i].MarginAmount > 0 {
			positions[i].ROE = (positions[i].UnrealizedPnl / positions[i].MarginAmount) * 100
		}
	}

	// Second pass: recalculate liq price for cross margin using total equity
	for i := range positions {
		if positions[i].MarginMode == "cross" {
			equity := s.calcCrossEquityForPosition(ctx, userID, positions[i].ID, positions)
			liq := calcLiqPrice(positions[i].EntryPrice, positions[i].Side, positions[i].Qty, positions[i].MarginAmount, "cross", equity)
			positions[i].LiqPrice = &liq
		}
	}

	return positions, nil
}

// UpdateTPSL sets take-profit and stop-loss prices on an open position.
func (s *TradingService) UpdateTPSL(ctx context.Context, userID, positionID string, tp *float64, sl *float64) (*model.Position, error) {
	pos, err := s.positionRepo.GetByID(ctx, positionID)
	if err != nil {
		return nil, fmt.Errorf("position not found: %w", err)
	}
	if pos.UserID != userID {
		return nil, fmt.Errorf("unauthorized")
	}
	if pos.Status != "open" {
		return nil, fmt.Errorf("position is not open")
	}

	if err := s.positionRepo.UpdateTPSL(ctx, positionID, tp, sl); err != nil {
		return nil, fmt.Errorf("update tp/sl: %w", err)
	}
	pos.TpPrice = tp
	pos.SlPrice = sl

	// Update cache
	s.addPositionToCache(pos)

	return pos, nil
}

// ListOrders returns orders for a user filtered by status.
func (s *TradingService) ListOrders(ctx context.Context, userID, status string, limit int) ([]model.Order, error) {
	orders, err := s.orderRepo.ListByUser(ctx, userID, status, limit)
	if err != nil {
		return nil, err
	}
	if orders == nil {
		orders = []model.Order{}
	}
	return orders, nil
}

// ListPositionHistory returns closed/liquidated positions for a user.
func (s *TradingService) ListPositionHistory(ctx context.Context, userID string, limit int) ([]model.Position, error) {
	return s.positionRepo.ListClosed(ctx, userID, limit)
}

// ListHistory returns non-pending orders (filled + cancelled).
func (s *TradingService) ListHistory(ctx context.Context, userID string, limit int) ([]model.Order, error) {
	all, err := s.orderRepo.ListByUser(ctx, userID, "all", limit)
	if err != nil {
		return nil, err
	}
	var history []model.Order
	for _, o := range all {
		if o.Status != "pending" {
			history = append(history, o)
		}
	}
	if history == nil {
		history = []model.Order{}
	}
	return history, nil
}

// ─── WebSocket push helpers ────────────────────

func (s *TradingService) pushOrderCreated(userID string, o *model.Order) {
	s.pusher.PushToUser(userID, map[string]any{
		"type": "order_created",
		"data": o,
	})
}

func (s *TradingService) pushOrderFilled(userID string, o *model.Order) {
	s.pusher.PushToUser(userID, map[string]any{
		"type": "order_filled",
		"data": o,
	})
}

func (s *TradingService) pushOrderCancelled(userID string, o *model.Order) {
	s.pusher.PushToUser(userID, map[string]any{
		"type": "order_cancelled",
		"data": o,
	})
}

func (s *TradingService) pushPositionUpdate(userID string, p *model.Position) {
	s.pusher.PushToUser(userID, map[string]any{
		"type": "position_update",
		"data": p,
	})
}

func (s *TradingService) pushPositionClosed(userID string, p *model.Position) {
	s.pusher.PushToUser(userID, map[string]any{
		"type": "position_closed",
		"data": p,
	})
}

func (s *TradingService) pushBalanceUpdate(userID string, w *model.Wallet) {
	s.pusher.PushToUser(userID, map[string]any{
		"type": "balance_update",
		"data": map[string]any{
			"balance": w.Balance,
			"frozen":  w.Frozen,
		},
	})
	// Also push full account info so UI sections update in real-time
	s.pushAccountUpdate(userID)
}

func (s *TradingService) pushAccountUpdate(userID string) {
	ctx := context.Background()
	info, err := s.GetAccountInfo(ctx, userID)
	if err != nil {
		log.Printf("[trading] pushAccountUpdate error for %s: %v", userID, err)
		return
	}
	s.pusher.PushToUser(userID, map[string]any{
		"type": "account_update",
		"data": info,
	})
}

// pushProfitShareEvents 推送分润事件（与 SettleToBucketWithCommission 配套）。
// 永远会推 copy_profit_share_settled 给 follower（含本次 hwm/bucket 余额，
// 即使 share=0 也让前端可以刷新跟单池子卡片）。
// 仅在 share>0 时给 trader 推 profit_share_received。
func (s *TradingService) pushProfitShareEvents(ctx context.Context, pos *model.Position, res *repository.ProfitShareResult) {
	if pos == nil || res == nil || s.pusher == nil {
		return
	}
	// follower（pos.UserID 即 follower 的 uid）—— 分润完成事件
	s.pusher.PushToUser(pos.UserID, map[string]any{
		"type": "copy_profit_share_settled",
		"data": map[string]any{
			"copy_trading_id": deref(pos.CopyTradingID),
			"position_id":     pos.ID,
			"share_paid":      res.ShareAmount,
			"hwm_after":       res.HwmAfter,
			"equity_after":    res.EquityAfter,
			"bucket_balance":  res.BucketBalance,
			"net_pnl":         res.NetPnl,
			"status":          res.Status,
		},
	})
	// trader 推送：仅在真的有进账时
	if !res.Settled || res.ShareAmount <= 0 {
		return
	}
	if s.traderRepo == nil || pos.CopyTradingID == nil {
		return
	}
	ct, err := s.traderRepo.GetCopyTradingByID(ctx, *pos.CopyTradingID)
	if err != nil || ct == nil {
		return
	}
	s.pusher.PushToUser(ct.TraderID, map[string]any{
		"type": "profit_share_received",
		"data": map[string]any{
			"copy_trading_id":    ct.ID,
			"from_follower_id":   ct.FollowerID,
			"position_id":        pos.ID,
			"symbol":             pos.Symbol,
			"amount":             res.ShareAmount,
			"new_lifetime_total": res.NewLifetimeIn,
		},
	})
}

// deref helper (used for *string -> string in WS payloads)
func deref(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

// ─── Helpers ────────────────────────────────────

// getPrice returns the latest price for any symbol (crypto, forex, or stock).
// Crypto symbols (e.g. BTC/USD) use Binance; forex/stocks use Polygon.
func (s *TradingService) getPrice(symbol string) (float64, error) {
	// 1. Try in-memory price cache first (fastest — updated by WS pushQuote)
	s.priceMu.RLock()
	if price, ok := s.priceCache[symbol]; ok && price > 0 {
		s.priceMu.RUnlock()
		return price, nil
	}
	s.priceMu.RUnlock()

	// 2. Try Binance in-memory prices for crypto
	if price, err := s.binance.GetPrice(symbol); err == nil {
		return price, nil
	}

	// 3. Fallback to Polygon REST (slow, only if cache misses)
	if s.polygon != nil {
		if strings.Contains(symbol, "/") {
			snap, err := s.polygon.GetForexSnapshot(symbol)
			if err != nil {
				return 0, fmt.Errorf("price not available for %s: %w", symbol, err)
			}
			if price, ok := snap["price"].(float64); ok && price > 0 {
				// Warm the cache
				s.priceMu.Lock()
				s.priceCache[symbol] = price
				s.priceMu.Unlock()
				return price, nil
			}
			return 0, fmt.Errorf("price not available for %s (zero from Polygon)", symbol)
		}
		snaps, err := s.polygon.GetSnapshotParsed([]string{symbol})
		if err != nil {
			return 0, fmt.Errorf("price not available for %s: %w", symbol, err)
		}
		if snap, ok := snaps[symbol]; ok {
			if price, ok := snap["price"].(float64); ok && price > 0 {
				s.priceMu.Lock()
				s.priceCache[symbol] = price
				s.priceMu.Unlock()
				return price, nil
			}
		}
		return 0, fmt.Errorf("price not available for %s (not in Polygon snapshot)", symbol)
	}

	return 0, fmt.Errorf("price not available for %s", symbol)
}

// calcLiqPrice calculates the liquidation price.
//
// For isolated margin:
//   availableMargin = marginAmount (only this position's margin)
//
// For cross margin:
//   availableMargin = totalEquity (balance + frozen + all unrealized PnL)
//     minus maintenance margin of OTHER positions
//   This is passed in via the walletEquity parameter.
//
// Formula:
//   Long:  liq = (entryPrice * qty - availableMargin) / (qty * (1 - mmr))
//   Short: liq = (entryPrice * qty + availableMargin) / (qty * (1 + mmr))
func calcLiqPrice(entryPrice float64, side string, qty float64, marginAmount float64, marginMode string, walletEquity float64) float64 {
	if qty <= 0 || entryPrice <= 0 {
		return 0
	}

	mmr := 0.005 // 0.5% maintenance margin rate

	var availableMargin float64
	if marginMode == "cross" {
		// walletEquity = total equity available for this position
		// (total balance + frozen + unrealized PnL - other positions' maintenance margin)
		availableMargin = walletEquity
	} else {
		availableMargin = marginAmount
	}

	notional := entryPrice * qty

	var liqPrice float64
	if side == "long" {
		denom := qty * (1.0 - mmr)
		if denom <= 0 {
			return 0
		}
		liqPrice = (notional - availableMargin) / denom
		if liqPrice < 0 {
			liqPrice = 0
		}
	} else {
		denom := qty * (1.0 + mmr)
		if denom <= 0 {
			return entryPrice * 2
		}
		liqPrice = (notional + availableMargin) / denom
	}

	return math.Round(liqPrice*100) / 100
}

// calcCrossEquityForPosition calculates the available equity for a specific cross-margin position.
// totalEquity = balance + frozen + sum(all unrealized PnL)
// availableForPos = totalEquity - sum(other positions' maintenance margin)
func (s *TradingService) calcCrossEquityForPosition(ctx context.Context, userID string, positionID string, allPositions []model.Position) float64 {
	w, err := s.walletRepo.GetWallet(ctx, userID)
	if err != nil {
		return 0
	}
	totalEquity := w.Balance + w.Frozen

	mmr := 0.005
	var otherMM float64
	for _, p := range allPositions {
		if p.ID == positionID {
			continue
		}
		// Add unrealized PnL of all positions to equity
		totalEquity += p.UnrealizedPnl
		// Subtract maintenance margin of other positions
		price, _ := s.getPrice(p.Symbol)
		if price <= 0 {
			price = p.EntryPrice
		}
		otherMM += price * p.Qty * mmr
	}
	// Also add this position's unrealized PnL
	for _, p := range allPositions {
		if p.ID == positionID {
			totalEquity += p.UnrealizedPnl
			break
		}
	}

	return totalEquity - otherMM
}

// ═══════════════════════════════════════════════════════════
// Copy Trading Engine
// ═══════════════════════════════════════════════════════════

// triggerCopyOpen mirrors a trader's new position to all active followers.
// Runs in a goroutine — errors are logged, never propagated to the trader.
func (s *TradingService) triggerCopyOpen(ctx context.Context, traderID string, order *model.Order, pos *model.Position) {
	log.Printf("[copy-trading] triggerCopyOpen called: trader=%s order=%s symbol=%s side=%s", traderID, order.ID, order.Symbol, order.Side)
	if s.traderRepo == nil {
		log.Printf("[copy-trading] traderRepo is nil, skipping")
		return
	}
	followers, err := s.traderRepo.ListActiveFollowersByTraderID(ctx, traderID)
	if err != nil {
		log.Printf("[copy-trading] ListActiveFollowers error: %v", err)
		return
	}
	if len(followers) == 0 {
		log.Printf("[copy-trading] no active followers for trader=%s", traderID)
		return
	}
	log.Printf("[copy-trading] found %d active follower(s) for trader=%s", len(followers), traderID)

	defer func() {
		if r := recover(); r != nil {
			log.Printf("[copy-trading] PANIC in triggerCopyOpen: %v", r)
		}
	}()

	currentPrice := pos.EntryPrice // use the fill price

	for _, ct := range followers {
		log.Printf("[copy-trading] processing follower=%s mode=%s ratio=%.2f direction=%s symbols=%v",
			ct.FollowerID, ct.CopyMode, ct.CopyRatio, ct.FollowDirection, ct.FollowSymbols)
		// Direction filter
		if ct.FollowDirection == "long" && order.Side != "long" {
			s.logCopySkip(ctx, &ct, order, pos, "direction_mismatch")
			continue
		}
		if ct.FollowDirection == "short" && order.Side != "short" {
			s.logCopySkip(ctx, &ct, order, pos, "direction_mismatch")
			continue
		}

		// Symbol filter
		if len(ct.FollowSymbols) > 0 {
			found := false
			for _, sym := range ct.FollowSymbols {
				if sym == order.Symbol {
					found = true
					break
				}
			}
			if !found {
				s.logCopySkip(ctx, &ct, order, pos, "symbol_not_followed")
				continue
			}
		}

		// 跟单子账户语义：每个 copy_trading 行是独立的虚拟池子（allocated_capital）
		// 仓位计算 / 资金来源都基于这个池子，与主钱包余额完全解耦。
		log.Printf("[copy-trading] passed direction/symbol filters for follower=%s bucket: allocated=%.2f available=%.2f frozen=%.2f",
			ct.FollowerID, ct.AllocatedCapital, ct.AvailableCapital, ct.FrozenCapital)
		if ct.AllocatedCapital <= 0 || ct.AvailableCapital <= 0 {
			s.logCopySkip(ctx, &ct, order, pos, "bucket_empty")
			continue
		}

		// Calculate follower margin
		var followerMargin float64
		if ct.CopyMode == "ratio" {
			// Ratio mode: 用交易员保证金占其总权益的比例 × 跟随者的「分配本金」 × 用户自定 copy_ratio
			// followerMargin = ct.AllocatedCapital × (traderMargin / traderEquity) × copy_ratio
			traderWallet, err := s.walletRepo.GetWallet(ctx, traderID)
			if err != nil || traderWallet == nil {
				log.Printf("[copy-trading] cannot get trader wallet for ratio calc, trader=%s: %v", traderID, err)
				s.logCopySkip(ctx, &ct, order, pos, "trader_wallet_error")
				continue
			}
			traderEquity := traderWallet.Balance + traderWallet.Frozen
			if traderEquity <= 0 {
				s.logCopySkip(ctx, &ct, order, pos, "trader_equity_zero")
				continue
			}
			traderRatio := order.MarginAmount / traderEquity // e.g. 10%
			followerMargin = ct.AllocatedCapital * traderRatio * ct.CopyRatio
			log.Printf("[copy-trading] ratio calc: traderEquity=%.2f traderMargin=%.2f traderRatio=%.4f bucketAllocated=%.2f copyRatio=%.2f → followerMargin=%.2f",
				traderEquity, order.MarginAmount, traderRatio, ct.AllocatedCapital, ct.CopyRatio, followerMargin)
		} else {
			// fixed amount
			if ct.FixedAmount != nil {
				followerMargin = *ct.FixedAmount
			} else {
				followerMargin = 100 // default
			}
		}

		// Apply max_single_margin cap
		if ct.MaxSingleMargin != nil && followerMargin > *ct.MaxSingleMargin {
			followerMargin = *ct.MaxSingleMargin
		}

		// 注意：max_position 上限的语义已与 allocated_capital 重叠，
		// 但保留逻辑做硬上限（用户可能想限制单交易员里实际开仓占池子的比例）。
		if ct.MaxPosition != nil {
			usedMargin, _ := s.traderRepo.GetTotalCopyMarginByTrader(ctx, ct.FollowerID, traderID)
			remaining := *ct.MaxPosition - usedMargin
			if remaining <= 0 {
				s.logCopySkip(ctx, &ct, order, pos, "max_position_exceeded")
				continue
			}
			if followerMargin > remaining {
				followerMargin = remaining
			}
		}

		// 检查池子剩余 available 能否覆盖 margin + 1% open fee 预留
		bucketAvailable := ct.AvailableCapital
		maxAffordable := bucketAvailable / 1.01
		log.Printf("[copy-trading] follower=%s bucket_available=%.2f needed_margin=%.2f maxAffordable=%.2f",
			ct.FollowerID, bucketAvailable, followerMargin, maxAffordable)
		if followerMargin > maxAffordable {
			if maxAffordable < 1 {
				// 池子余额不足，直接跳过这笔（不强行缩到 0）
				log.Printf("[copy-trading] follower=%s insufficient bucket capital (available=%.2f)", ct.FollowerID, bucketAvailable)
				s.logCopySkip(ctx, &ct, order, pos, "insufficient_allocated_capital")
				continue
			}
			log.Printf("[copy-trading] follower=%s shrinking margin from %.2f to %.2f (bucket limit)",
				ct.FollowerID, followerMargin, maxAffordable)
			followerMargin = maxAffordable
		}

		// Determine leverage
		leverage := order.Leverage
		if ct.LeverageMode == "custom" && ct.CustomLeverage != nil {
			leverage = *ct.CustomLeverage
		}

		// Calculate qty (after margin may have been shrunk)
		if currentPrice <= 0 || leverage <= 0 {
			s.logCopySkip(ctx, &ct, order, pos, "invalid_price_or_leverage")
			continue
		}
		followerQty := (followerMargin * float64(leverage)) / currentPrice
		if followerQty <= 0 {
			s.logCopySkip(ctx, &ct, order, pos, "zero_qty")
			continue
		}

		// Determine TP/SL
		var tpPrice, slPrice *float64
		if ct.TpSlMode == "trader" {
			tpPrice = pos.TpPrice
			slPrice = pos.SlPrice
		} else if ct.TpSlMode == "custom" {
			if ct.CustomTpRatio != nil && *ct.CustomTpRatio > 0 {
				tp := currentPrice * (1 + *ct.CustomTpRatio)
				if order.Side == "short" {
					tp = currentPrice * (1 - *ct.CustomTpRatio)
				}
				tpPrice = &tp
			}
			if ct.CustomSlRatio != nil && *ct.CustomSlRatio > 0 {
				sl := currentPrice * (1 - *ct.CustomSlRatio)
				if order.Side == "short" {
					sl = currentPrice * (1 + *ct.CustomSlRatio)
				}
				slPrice = &sl
			}
		}

		// Place the copy order
		copyOrder, copyPos, err := s.placeCopyOrder(ctx, ct.FollowerID, &ct, order, pos,
			followerMargin, followerQty, leverage, tpPrice, slPrice)
		if err != nil {
			log.Printf("[copy-trading] failed to place copy order for follower=%s trader=%s: %v",
				ct.FollowerID, traderID, err)
			s.logCopySkip(ctx, &ct, order, pos, "place_order_error: "+err.Error())
			continue
		}

		// Log success
		logEntry := &model.CopyTradeLog{
			CopyTradingID:    ct.ID,
			FollowerID:       ct.FollowerID,
			TraderID:         traderID,
			Action:           "open",
			SourceOrderID:    &order.ID,
			SourcePositionID: &pos.ID,
			FollowerOrderID:  &copyOrder.ID,
			FollowerPositionID: &copyPos.ID,
			Symbol:           order.Symbol,
			Side:             order.Side,
			TraderQty:        order.Qty,
			FollowerQty:      followerQty,
			TraderMargin:     order.MarginAmount,
			FollowerMargin:   followerMargin,
			FollowerLeverage: leverage,
		}
		_ = s.traderRepo.CreateCopyTradeLog(ctx, logEntry)

		// 拿最新池子快照（available/frozen 已被本次开仓修改）
		var bucket *model.CopyTrading
		if updated, gerr := s.traderRepo.GetCopyTradingByID(ctx, ct.ID); gerr == nil {
			bucket = updated
		}

		// Push notification to follower
		s.pusher.PushToUser(ct.FollowerID, map[string]any{
			"type": "copy_trade_opened",
			"data": map[string]any{
				"order":       copyOrder,
				"position":    copyPos,
				"trader_name": ct.TraderName,
				"bucket":      bucket,
			},
		})

		log.Printf("[copy-trading] opened: follower=%s trader=%s symbol=%s side=%s qty=%.4f margin=%.2f",
			ct.FollowerID, traderID, order.Symbol, order.Side, followerQty, followerMargin)
	}
}

// placeCopyOrder creates a market order for a follower mirroring a trader's trade.
func (s *TradingService) placeCopyOrder(
	ctx context.Context,
	followerID string,
	ct *model.CopyTrading,
	sourceOrder *model.Order,
	sourcePos *model.Position,
	margin, qty float64,
	leverage int,
	tpPrice, slPrice *float64,
) (*model.Order, *model.Position, error) {
	// 跟单仓位的资金来源是 copy_trading 子账户（池子），主钱包完全不动。
	// 1. 计算 open fee
	vipLevel, _ := s.userRepo.GetVipLevel(ctx, followerID)
	_, takerRate := s.getVipFeeRates(vipLevel)
	openFee := math.Round(sourcePos.EntryPrice*qty*takerRate*1e8) / 1e8
	// 2. 一次性原子扣 (margin + openFee)：margin 进 frozen，fee 是损耗
	if err := s.traderRepo.FreezeFromBucket(ctx, ct.ID, margin, openFee); err != nil {
		return nil, nil, fmt.Errorf("freeze from bucket: %w", err)
	}

	// Calculate liq price
	liqPrice := calcLiqPrice(sourcePos.EntryPrice, sourceOrder.Side, qty, margin, sourceOrder.MarginMode, 0)

	// Create order
	copyOrderID := sourceOrder.ID
	copyTradingID := ct.ID
	order := &model.Order{
		UserID:         followerID,
		Symbol:         sourceOrder.Symbol,
		Side:           sourceOrder.Side,
		OrderType:      "market",
		Qty:            qty,
		FilledPrice:    &sourcePos.EntryPrice,
		Leverage:       leverage,
		MarginMode:     sourceOrder.MarginMode,
		MarginAmount:   margin,
		Status:         "filled",
		Fee:            openFee,
		IsCopyTrade:    true,
		SourceOrderID:  &copyOrderID,
		SourceTraderID: &sourceOrder.UserID,
		CopyTradingID:  &copyTradingID,
	}
	now := time.Now()
	order.FilledAt = &now

	if err := s.orderRepo.Create(ctx, order); err != nil {
		_ = s.traderRepo.UnfreezeBucket(ctx, ct.ID, margin, openFee)
		return nil, nil, fmt.Errorf("create order: %w", err)
	}

	// Create position (always separate, never upsert)
	sourcePosID := sourcePos.ID
	pos := &model.Position{
		UserID:           followerID,
		Symbol:           sourceOrder.Symbol,
		Side:             sourceOrder.Side,
		Qty:              qty,
		EntryPrice:       sourcePos.EntryPrice,
		Leverage:         leverage,
		MarginMode:       sourceOrder.MarginMode,
		MarginAmount:     margin,
		LiqPrice:         &liqPrice,
		TpPrice:          tpPrice,
		SlPrice:          slPrice,
		OpenFee:          openFee,
		IsCopyTrade:      true,
		SourcePositionID: &sourcePosID,
		SourceTraderID:   &sourceOrder.UserID,
		CopyTradingID:    &copyTradingID,
	}

	pos, err := s.positionRepo.CreateCopyPosition(ctx, pos)
	if err != nil {
		_ = s.traderRepo.UnfreezeBucket(ctx, ct.ID, margin, openFee)
		log.Printf("[copy-trade] position creation failed, unfroze bucket margin=%.4f fee=%.4f for follower=%s: %v",
			margin, openFee, followerID, err)
		return nil, nil, fmt.Errorf("create position: %w", err)
	}

	// Recalculate liq_price against the merged position so adds get a correct
	// liquidation price (CreateCopyPosition leaves liq_price untouched on merge).
	newLiq := calcLiqPrice(pos.EntryPrice, pos.Side, pos.Qty, pos.MarginAmount, pos.MarginMode, 0)
	pos.LiqPrice = &newLiq
	s.positionRepo.UpdateLiqPrice(ctx, pos.ID, newLiq)

	// Add to cache
	s.addPositionToCache(pos)

	// Push events to follower（跟单仓位不动主钱包，所以不推 balance update；
	// 池子最新状态会随 copy_trade_opened 推送）
	s.pushOrderFilled(followerID, order)
	s.pushPositionUpdate(followerID, pos)

	return order, pos, nil
}

// triggerCopyClose closes all follower positions linked to a trader's position.
func (s *TradingService) triggerCopyClose(ctx context.Context, traderID, positionID string) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[copy-trading] PANIC in triggerCopyClose: %v", r)
		}
	}()
	if s.traderRepo == nil {
		return
	}
	followerPositions, err := s.positionRepo.ListBySourcePosition(ctx, positionID)
	if err != nil || len(followerPositions) == 0 {
		return
	}

	for _, fp := range followerPositions {
		closedPos, err := s.ClosePosition(ctx, fp.UserID, fp.ID)
		if err != nil {
			log.Printf("[copy-trading] failed to close follower pos=%s user=%s: %v", fp.ID, fp.UserID, err)
			continue
		}

		// Log
		logEntry := &model.CopyTradeLog{
			CopyTradingID:      strings.TrimSpace(func() string { if fp.CopyTradingID != nil { return *fp.CopyTradingID }; return "" }()),
			FollowerID:         fp.UserID,
			TraderID:           traderID,
			Action:             "close",
			SourcePositionID:   &positionID,
			FollowerPositionID: &fp.ID,
			Symbol:             fp.Symbol,
			Side:               fp.Side,
			TraderQty:          0,
			FollowerQty:        fp.Qty,
			TraderMargin:       0,
			FollowerMargin:     fp.MarginAmount,
			FollowerLeverage:   fp.Leverage,
			RealizedPnl:        closedPos.RealizedPnl,
		}
		_ = s.traderRepo.CreateCopyTradeLog(ctx, logEntry)

		// 推送时附带最新池子余额，前端可即时刷新「跟单本金」
		var bucket *model.CopyTrading
		if fp.CopyTradingID != nil {
			if updated, gerr := s.traderRepo.GetCopyTradingByID(ctx, *fp.CopyTradingID); gerr == nil {
				bucket = updated
			}
		}
		s.pusher.PushToUser(fp.UserID, map[string]any{
			"type": "copy_trade_closed",
			"data": map[string]any{
				"position": closedPos,
				"bucket":   bucket,
			},
		})

		log.Printf("[copy-trading] closed: follower=%s pos=%s pnl=%.2f", fp.UserID, fp.ID, closedPos.RealizedPnl)
	}
}

// triggerCopyPartialClose partial-closes follower positions proportionally.
func (s *TradingService) triggerCopyPartialClose(ctx context.Context, traderID, positionID string, fraction float64) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("[copy-trading] PANIC in triggerCopyPartialClose: %v", r)
		}
	}()
	if s.traderRepo == nil {
		return
	}
	followerPositions, err := s.positionRepo.ListBySourcePosition(ctx, positionID)
	if err != nil || len(followerPositions) == 0 {
		return
	}

	for _, fp := range followerPositions {
		closeQty := fp.Qty * fraction
		if closeQty <= 0 {
			continue
		}
		_, err := s.PartialClosePosition(ctx, fp.UserID, fp.ID, closeQty)
		if err != nil {
			log.Printf("[copy-trading] failed to partial-close follower pos=%s: %v", fp.ID, err)
			continue
		}
		log.Printf("[copy-trading] partial-closed: follower=%s pos=%s qty=%.4f (%.0f%%)",
			fp.UserID, fp.ID, closeQty, fraction*100)
	}
}

// logCopySkip logs a skipped copy trade.
func (s *TradingService) logCopySkip(ctx context.Context, ct *model.CopyTrading, order *model.Order, pos *model.Position, reason string) {
	logEntry := &model.CopyTradeLog{
		CopyTradingID:    ct.ID,
		FollowerID:       ct.FollowerID,
		TraderID:         ct.TraderID,
		Action:           "skip",
		SourceOrderID:    &order.ID,
		SourcePositionID: &pos.ID,
		Symbol:           order.Symbol,
		Side:             order.Side,
		TraderQty:        order.Qty,
		TraderMargin:     order.MarginAmount,
		SkipReason:       reason,
	}
	_ = s.traderRepo.CreateCopyTradeLog(ctx, logEntry)
}
