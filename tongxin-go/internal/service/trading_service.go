package service

import (
	"context"
	"fmt"
	"log"
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
	UserID       string
	PositionID   string
	Symbol       string
	Side         string
	Qty          float64
	EntryPrice   float64
	Leverage     int
	MarginAmount float64
	MarginMode   string
	LiqPrice     *float64
	TpPrice      *float64
	SlPrice      *float64
}

type TradingService struct {
	walletRepo   *repository.WalletRepo
	orderRepo    *repository.OrderRepo
	positionRepo *repository.PositionRepo
	binance      *market.BinanceIngestor
	polygon      *market.PolygonClient
	pusher       TradingPusher

	// In-memory pending limit orders cache for instant trigger
	pendingMu       sync.RWMutex
	pendingBySymbol map[string][]model.Order

	// In-memory open positions cache for real-time PnL push
	posMu        sync.RWMutex
	openBySymbol map[string][]cachedPosition
}

func NewTradingService(
	wr *repository.WalletRepo,
	or *repository.OrderRepo,
	pr *repository.PositionRepo,
	bi *market.BinanceIngestor,
	pg *market.PolygonClient,
	pusher TradingPusher,
) *TradingService {
	return &TradingService{
		walletRepo:      wr,
		orderRepo:       or,
		positionRepo:    pr,
		binance:         bi,
		polygon:         pg,
		pusher:          pusher,
		pendingBySymbol: make(map[string][]model.Order),
		openBySymbol:    make(map[string][]cachedPosition),
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
		cp := cachedPosition{
			UserID:       p.UserID,
			PositionID:   p.ID,
			Symbol:       p.Symbol,
			Side:         p.Side,
			Qty:          p.Qty,
			EntryPrice:   p.EntryPrice,
			Leverage:     p.Leverage,
			MarginAmount: p.MarginAmount,
			MarginMode:   p.MarginMode,
			LiqPrice:     p.LiqPrice,
			TpPrice:      p.TpPrice,
			SlPrice:      p.SlPrice,
		}
		s.openBySymbol[p.Symbol] = append(s.openBySymbol[p.Symbol], cp)
	}
	log.Printf("[trading] loaded %d open positions into cache", len(positions))
}

// addPositionToCache adds or updates a position in the in-memory cache.
func (s *TradingService) addPositionToCache(p *model.Position) {
	cp := cachedPosition{
		UserID:       p.UserID,
		PositionID:   p.ID,
		Symbol:       p.Symbol,
		Side:         p.Side,
		Qty:          p.Qty,
		EntryPrice:   p.EntryPrice,
		Leverage:     p.Leverage,
		MarginAmount: p.MarginAmount,
		MarginMode:   p.MarginMode,
		LiqPrice:     p.LiqPrice,
		TpPrice:      p.TpPrice,
		SlPrice:      p.SlPrice,
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
	openPositions := s.openBySymbol[symbol]
	s.posMu.RUnlock()

	var toLiquidate []cachedPosition
	var toTPSL []cachedPosition
	for _, cp := range openPositions {
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

	margin := (req.Qty * currentPrice) / float64(req.Leverage)

	// Freeze margin
	if err := s.walletRepo.FreezeMargin(ctx, userID, margin); err != nil {
		return nil, fmt.Errorf("%w", err)
	}

	// Calculate liquidation price
	var walletBal float64
	if req.MarginMode == "cross" {
		if w, err := s.walletRepo.GetWallet(ctx, userID); err == nil {
			walletBal = w.Balance
		}
	}
	liqPrice := calcLiqPrice(currentPrice, req.Side, req.Qty, margin, req.MarginMode, walletBal)

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
		FilledAt:     &now,
	}

	if err := s.orderRepo.Create(ctx, order); err != nil {
		// Unfreeze on failure
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
	}
	pos, err = s.positionRepo.UpsertPosition(ctx, pos)
	if err != nil {
		return nil, fmt.Errorf("upsert position: %w", err)
	}

	// Set TP/SL if provided
	if req.TpPrice != nil || req.SlPrice != nil {
		s.positionRepo.UpdateTPSL(ctx, pos.ID, req.TpPrice, req.SlPrice)
		pos.TpPrice = req.TpPrice
		pos.SlPrice = req.SlPrice
	}

	// Recalculate liq price based on merged position data
	var walletBal2 float64
	if pos.MarginMode == "cross" {
		if w, err := s.walletRepo.GetWallet(ctx, userID); err == nil {
			walletBal2 = w.Balance
		}
	}
	newLiq := calcLiqPrice(pos.EntryPrice, pos.Side, pos.Qty, pos.MarginAmount, pos.MarginMode, walletBal2)
	pos.LiqPrice = &newLiq
	s.positionRepo.UpdateLiqPrice(ctx, pos.ID, newLiq)

	// Enrich position with current price info
	pos.CurrentPrice = currentPrice
	pos.UnrealizedPnl = 0
	pos.ROE = 0

	// Update position cache
	s.addPositionToCache(pos)

	// Push WebSocket events
	wallet, _ := s.walletRepo.GetWallet(ctx, userID)
	s.pushOrderFilled(userID, order)
	s.pushPositionUpdate(userID, pos)
	if wallet != nil {
		s.pushBalanceUpdate(userID, wallet)
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
	if err := s.orderRepo.FillOrder(ctx, o.ID, fillPrice); err != nil {
		return err
	}

	var walletBal float64
	if o.MarginMode == "cross" {
		if w, err := s.walletRepo.GetWallet(ctx, o.UserID); err == nil {
			walletBal = w.Balance
		}
	}
	liqPrice := calcLiqPrice(fillPrice, o.Side, o.Qty, o.MarginAmount, o.MarginMode, walletBal)

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
	}
	pos, err := s.positionRepo.UpsertPosition(ctx, pos)
	if err != nil {
		return fmt.Errorf("upsert position for limit fill: %w", err)
	}

	// Recalculate liq price based on merged position data
	var walletBal2 float64
	if pos.MarginMode == "cross" {
		if w, err := s.walletRepo.GetWallet(ctx, o.UserID); err == nil {
			walletBal2 = w.Balance
		}
	}
	newLiq := calcLiqPrice(pos.EntryPrice, pos.Side, pos.Qty, pos.MarginAmount, pos.MarginMode, walletBal2)
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

	// Settle: unfreeze margin + apply PnL
	if err := s.walletRepo.SettleTrade(ctx, userID, pos.MarginAmount, pnl); err != nil {
		return nil, fmt.Errorf("settle trade: %w", err)
	}

	if err := s.positionRepo.ClosePosition(ctx, positionID, pnl, currentPrice); err != nil {
		return nil, fmt.Errorf("close position: %w", err)
	}

	pos.Status = "closed"
	pos.RealizedPnl = pnl
	pos.ClosePrice = currentPrice
	pos.CurrentPrice = currentPrice
	pos.UnrealizedPnl = 0

	// Remove from position cache
	s.removePositionFromCache(pos.Symbol, positionID)

	wallet, _ := s.walletRepo.GetWallet(ctx, userID)
	s.pushPositionClosed(userID, pos)
	if wallet != nil {
		s.pushBalanceUpdate(userID, wallet)
	}

	return pos, nil
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

	// Proportional margin release
	closeFraction := closeQty / pos.Qty
	releasedMargin := pos.MarginAmount * closeFraction
	remainingQty := pos.Qty - closeQty
	remainingMargin := pos.MarginAmount - releasedMargin

	// Settle the closed portion: release proportional margin + PnL
	if err := s.walletRepo.SettleTrade(ctx, userID, releasedMargin, pnl); err != nil {
		return nil, fmt.Errorf("settle partial close: %w", err)
	}

	// Update position with reduced qty and margin
	if err := s.positionRepo.ReducePosition(ctx, positionID, remainingQty, remainingMargin); err != nil {
		return nil, fmt.Errorf("reduce position: %w", err)
	}

	// Update cache
	s.posMu.Lock()
	if positions, ok := s.openBySymbol[pos.Symbol]; ok {
		for i, cp := range positions {
			if cp.PositionID == positionID {
				positions[i].Qty = remainingQty
				positions[i].MarginAmount = remainingMargin
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

	return pos, nil
}

// liquidatePosition force-closes a position at the liquidation price.
// The entire margin is lost (PnL = -marginAmount).
func (s *TradingService) liquidatePosition(ctx context.Context, cp cachedPosition, currentPrice float64) {
	// PnL = loss of entire margin
	pnl := -cp.MarginAmount

	// Settle: unfreeze margin, apply PnL (margin is fully lost)
	if err := s.walletRepo.SettleTrade(ctx, cp.UserID, cp.MarginAmount, pnl); err != nil {
		log.Printf("[trading] liquidation settle error for %s: %v", cp.PositionID, err)
		return
	}

	if err := s.positionRepo.LiquidatePosition(ctx, cp.PositionID, pnl, currentPrice); err != nil {
		log.Printf("[trading] liquidation close error for %s: %v", cp.PositionID, err)
		return
	}

	// Remove from cache
	s.removePositionFromCache(cp.Symbol, cp.PositionID)

	pos := &model.Position{
		ID:           cp.PositionID,
		UserID:       cp.UserID,
		Symbol:       cp.Symbol,
		Side:         cp.Side,
		Qty:          cp.Qty,
		EntryPrice:   cp.EntryPrice,
		ClosePrice:   currentPrice,
		Leverage:     cp.Leverage,
		MarginMode:   cp.MarginMode,
		MarginAmount: cp.MarginAmount,
		LiqPrice:     cp.LiqPrice,
		Status:       "liquidated",
		RealizedPnl:  pnl,
		CurrentPrice: currentPrice,
	}

	// Push liquidation event to user
	s.pusher.PushToUser(cp.UserID, map[string]any{
		"type": "position_liquidated",
		"data": pos,
	})

	wallet, _ := s.walletRepo.GetWallet(ctx, cp.UserID)
	if wallet != nil {
		s.pushBalanceUpdate(cp.UserID, wallet)
	}

	log.Printf("[trading] LIQUIDATED: user=%s pos=%s %s %s, margin=%.2f lost",
		cp.UserID, cp.PositionID, cp.Side, cp.Symbol, cp.MarginAmount)
}

// closePositionByTPSL auto-closes a position when TP or SL price is hit.
func (s *TradingService) closePositionByTPSL(ctx context.Context, cp cachedPosition, currentPrice float64) {
	var pnl float64
	if cp.Side == "long" {
		pnl = (currentPrice - cp.EntryPrice) * cp.Qty
	} else {
		pnl = (cp.EntryPrice - currentPrice) * cp.Qty
	}

	if err := s.walletRepo.SettleTrade(ctx, cp.UserID, cp.MarginAmount, pnl); err != nil {
		log.Printf("[trading] TP/SL settle error for %s: %v", cp.PositionID, err)
		return
	}

	if err := s.positionRepo.ClosePosition(ctx, cp.PositionID, pnl, currentPrice); err != nil {
		log.Printf("[trading] TP/SL close error for %s: %v", cp.PositionID, err)
		return
	}

	s.removePositionFromCache(cp.Symbol, cp.PositionID)

	pos := &model.Position{
		ID:           cp.PositionID,
		UserID:       cp.UserID,
		Symbol:       cp.Symbol,
		Side:         cp.Side,
		Qty:          cp.Qty,
		EntryPrice:   cp.EntryPrice,
		ClosePrice:   currentPrice,
		Leverage:     cp.Leverage,
		MarginMode:   cp.MarginMode,
		MarginAmount: cp.MarginAmount,
		LiqPrice:     cp.LiqPrice,
		TpPrice:      cp.TpPrice,
		SlPrice:      cp.SlPrice,
		Status:       "closed",
		RealizedPnl:  pnl,
		CurrentPrice: currentPrice,
	}

	s.pushPositionClosed(cp.UserID, pos)
	wallet, _ := s.walletRepo.GetWallet(ctx, cp.UserID)
	if wallet != nil {
		s.pushBalanceUpdate(cp.UserID, wallet)
	}

	log.Printf("[trading] TP/SL CLOSED: user=%s pos=%s %s %s @ %.4f, pnl=%.2f",
		cp.UserID, cp.PositionID, cp.Side, cp.Symbol, currentPrice, pnl)
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

// ─── Helpers ────────────────────────────────────

// getPrice returns the latest price for any symbol (crypto, forex, or stock).
// Crypto symbols (e.g. BTC/USD) use Binance; forex/stocks use Polygon.
func (s *TradingService) getPrice(symbol string) (float64, error) {
	// Try Binance first for crypto symbols
	if price, err := s.binance.GetPrice(symbol); err == nil {
		return price, nil
	}

	// Fallback to Polygon for forex/stocks
	if s.polygon != nil {
		if strings.Contains(symbol, "/") {
			// Forex symbol like EUR/USD
			snap, err := s.polygon.GetForexSnapshot(symbol)
			if err != nil {
				return 0, fmt.Errorf("price not available for %s: %w", symbol, err)
			}
			if price, ok := snap["price"].(float64); ok && price > 0 {
				return price, nil
			}
			return 0, fmt.Errorf("price not available for %s (zero from Polygon)", symbol)
		}
		// Stock symbol like AAPL
		snaps, err := s.polygon.GetSnapshotParsed([]string{symbol})
		if err != nil {
			return 0, fmt.Errorf("price not available for %s: %w", symbol, err)
		}
		if snap, ok := snaps[symbol]; ok {
			if price, ok := snap["price"].(float64); ok && price > 0 {
				return price, nil
			}
		}
		return 0, fmt.Errorf("price not available for %s (not in Polygon snapshot)", symbol)
	}

	return 0, fmt.Errorf("price not available for %s", symbol)
}

// calcLiqPrice calculates the liquidation price.
//   - isolated: only the position's margin is at risk
//   - cross: the entire wallet balance backs the position
//
// walletBalance is the user's available balance (only used for cross mode).
func calcLiqPrice(entryPrice float64, side string, qty float64, marginAmount float64, marginMode string, walletBalance float64) float64 {
	mmr := 0.005 // 0.5% maintenance margin rate
	maintenanceMargin := entryPrice * qty * mmr

	var availableMargin float64
	if marginMode == "cross" {
		availableMargin = walletBalance + marginAmount
	} else {
		// isolated: only the position's own margin
		availableMargin = marginAmount
	}

	buffer := availableMargin - maintenanceMargin
	if buffer <= 0 {
		// Already at or past liquidation
		return entryPrice
	}

	if side == "long" {
		return entryPrice - buffer/qty
	}
	return entryPrice + buffer/qty
}
