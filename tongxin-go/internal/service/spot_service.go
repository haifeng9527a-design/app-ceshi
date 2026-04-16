package service

import (
	"context"
	"errors"
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

// SpotPusher 用于解耦 ws.TradingHub（避免循环依赖）。
type SpotPusher interface {
	PushToUser(userID string, payload any)
}

// SpotService 现货交易服务。
type SpotService struct {
	repo        *repository.SpotRepo
	userRepo    *repository.UserRepo
	binance     *market.BinanceIngestor
	polygon     *market.PolygonClient
	pusher      SpotPusher
	referralSvc *ReferralService

	// in-memory cache
	priceCache map[string]float64
	priceMu    sync.RWMutex

	// pending limit orders, indexed by symbol → slice
	pendingBySymbol map[string][]*model.SpotOrder
	pendingMu       sync.RWMutex

	// supported symbol cache
	symbolMeta map[string]*model.SpotSupportedSymbol
	symbolMu   sync.RWMutex
}

func NewSpotService(repo *repository.SpotRepo, userRepo *repository.UserRepo, binance *market.BinanceIngestor, polygon *market.PolygonClient, pusher SpotPusher) *SpotService {
	return &SpotService{
		repo:            repo,
		userRepo:        userRepo,
		binance:         binance,
		polygon:         polygon,
		pusher:          pusher,
		priceCache:      make(map[string]float64),
		pendingBySymbol: make(map[string][]*model.SpotOrder),
		symbolMeta:      make(map[string]*model.SpotSupportedSymbol),
	}
}

// SetReferralService 注入返佣服务（commit 6 fee instrumentation）。
func (s *SpotService) SetReferralService(r *ReferralService) {
	s.referralSvc = r
}

// LoadSymbolMeta 启动时加载所有上架交易对到内存。
func (s *SpotService) LoadSymbolMeta(ctx context.Context) error {
	syms, err := s.repo.ListSupportedSymbols(ctx, "", true)
	if err != nil {
		return err
	}
	s.symbolMu.Lock()
	defer s.symbolMu.Unlock()
	for i := range syms {
		s.symbolMeta[syms[i].Symbol] = &syms[i]
	}
	log.Printf("[spot] loaded %d supported symbols", len(syms))
	return nil
}

// LoadPendingOrders 启动时加载所有 pending 限价单到内存（重启恢复）。
func (s *SpotService) LoadPendingOrders(ctx context.Context) error {
	orders, err := s.repo.ListPendingOrdersForSymbol(ctx, "")
	if err != nil {
		return err
	}
	s.pendingMu.Lock()
	defer s.pendingMu.Unlock()
	for _, o := range orders {
		s.pendingBySymbol[o.Symbol] = append(s.pendingBySymbol[o.Symbol], o)
	}
	log.Printf("[spot] loaded %d pending limit orders", len(orders))
	return nil
}

// OnPriceUpdate 价格 tick 回调（与 trading_service.OnPriceUpdate 并存，由 MarketHub 派发）。
func (s *SpotService) OnPriceUpdate(symbol string, price float64) {
	s.priceMu.Lock()
	s.priceCache[symbol] = price
	s.priceMu.Unlock()

	s.pendingMu.RLock()
	pending, ok := s.pendingBySymbol[symbol]
	s.pendingMu.RUnlock()
	if !ok || len(pending) == 0 {
		return
	}

	// 找出可成交的订单
	var toFill []*model.SpotOrder
	s.pendingMu.Lock()
	remaining := pending[:0]
	for _, o := range pending {
		if o.Price == nil {
			continue
		}
		shouldFill := false
		if o.Side == model.SpotSideBuy && price <= *o.Price {
			shouldFill = true
		} else if o.Side == model.SpotSideSell && price >= *o.Price {
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
		if err := s.FillPendingSpotOrder(ctx, o, fillPrice); err != nil {
			log.Printf("[spot] fill failed order=%s err=%v", o.ID, err)
			// 失败放回队列，等待下次价格触发
			s.pendingMu.Lock()
			s.pendingBySymbol[symbol] = append(s.pendingBySymbol[symbol], o)
			s.pendingMu.Unlock()
		}
	}
}

// ── 公共 API ──

// PlaceSpotOrder 下现货单（市价 or 限价）。
func (s *SpotService) PlaceSpotOrder(ctx context.Context, userID string, req *model.SpotPlaceOrderRequest) (*model.SpotOrder, error) {
	// 1. 校验
	req.Symbol = strings.ToUpper(strings.TrimSpace(req.Symbol))
	req.Side = strings.ToLower(strings.TrimSpace(req.Side))
	req.OrderType = strings.ToLower(strings.TrimSpace(req.OrderType))

	if req.Side != model.SpotSideBuy && req.Side != model.SpotSideSell {
		return nil, fmt.Errorf("invalid side: %s", req.Side)
	}
	if req.OrderType != model.SpotOrderTypeMarket && req.OrderType != model.SpotOrderTypeLimit {
		return nil, fmt.Errorf("invalid order_type: %s", req.OrderType)
	}

	meta, err := s.getSymbolMeta(ctx, req.Symbol)
	if err != nil {
		return nil, fmt.Errorf("symbol not supported: %w", err)
	}

	// 2. 解析价格 + 数量
	currentPrice, err := s.getPrice(req.Symbol)
	if err != nil || currentPrice <= 0 {
		return nil, fmt.Errorf("price unavailable for %s", req.Symbol)
	}

	var qty float64
	if req.Qty != nil && *req.Qty > 0 {
		qty = *req.Qty
	} else if req.QuoteQty != nil && *req.QuoteQty > 0 {
		// 按金额下单：qty = quote_qty / price
		referencePrice := currentPrice
		if req.OrderType == model.SpotOrderTypeLimit && req.Price != nil {
			referencePrice = *req.Price
		}
		if referencePrice <= 0 {
			return nil, errors.New("invalid reference price for quote_qty")
		}
		qty = *req.QuoteQty / referencePrice
	} else {
		return nil, errors.New("either qty or quote_qty required")
	}

	if qty < meta.MinQty {
		return nil, fmt.Errorf("qty below minimum %.8f", meta.MinQty)
	}

	// 精度规整
	qty = roundDown(qty, meta.QtyPrecision)
	if qty <= 0 {
		return nil, fmt.Errorf("qty rounds to zero, increase amount")
	}

	// 3. 取手续费
	vipLevel := 0
	if s.userRepo != nil {
		vipLevel, _ = s.userRepo.GetVipLevel(ctx, userID)
	}
	makerFee, takerFee, err := s.repo.GetFeeRate(ctx, vipLevel)
	if err != nil {
		return nil, fmt.Errorf("get fee rate: %w", err)
	}

	// 4. 分支处理
	if req.OrderType == model.SpotOrderTypeMarket {
		return s.placeMarket(ctx, userID, meta, req.Side, qty, currentPrice, takerFee, req.ClientOrderID)
	}

	// limit
	if req.Price == nil || *req.Price <= 0 {
		return nil, errors.New("limit order requires positive price")
	}
	limitPrice := roundDown(*req.Price, meta.PricePrecision)
	if limitPrice <= 0 {
		return nil, errors.New("limit price rounds to zero")
	}

	// 限价合理性：buy 限价不能太离谱（≥ 1.5×current 给警告？），暂时不做硬限制
	return s.placeLimit(ctx, userID, meta, req.Side, qty, limitPrice, makerFee, req.ClientOrderID)
}

func (s *SpotService) placeMarket(ctx context.Context, userID string, meta *model.SpotSupportedSymbol, side string, qty, price, feeRate float64, clientOrderID *string) (*model.SpotOrder, error) {
	res, err := s.repo.ExecuteSpotMarketOrder(ctx, struct {
		UserID        string
		Symbol        string
		BaseAsset     string
		QuoteAsset    string
		Side          string
		Qty           float64
		FilledPrice   float64
		FeeRate       float64
		ClientOrderID *string
	}{
		UserID: userID, Symbol: meta.Symbol, BaseAsset: meta.BaseAsset, QuoteAsset: meta.QuoteAsset,
		Side: side, Qty: qty, FilledPrice: price, FeeRate: feeRate, ClientOrderID: clientOrderID,
	})
	if err != nil {
		return nil, err
	}

	// 异步触发返佣
	if s.referralSvc != nil && res.Fee > 0 {
		s.referralSvc.RecordCommissionEventAsync(userID, res.Fee, model.ProductTypeSpot, res.OrderID)
	}

	// 推 WS
	s.pushOrderUpdate(userID, "spot_order_filled", res.OrderID, meta, side, qty, price, res.Fee)
	s.pushBalanceUpdate(userID, meta, res.BaseAvailable, res.QuoteAvailable)

	// 返回完整订单
	return s.repo.GetOrder(ctx, res.OrderID)
}

func (s *SpotService) placeLimit(ctx context.Context, userID string, meta *model.SpotSupportedSymbol, side string, qty, price, feeRate float64, clientOrderID *string) (*model.SpotOrder, error) {
	orderID, err := s.repo.ExecuteSpotLimitPlace(ctx, repository.PlaceLimitOrderParams{
		UserID: userID, Symbol: meta.Symbol, BaseAsset: meta.BaseAsset, QuoteAsset: meta.QuoteAsset,
		Side: side, Qty: qty, Price: price, FeeRate: feeRate, ClientOrderID: clientOrderID,
	})
	if err != nil {
		return nil, err
	}

	order, err := s.repo.GetOrder(ctx, orderID)
	if err != nil {
		return nil, err
	}

	// 加入内存
	s.pendingMu.Lock()
	s.pendingBySymbol[meta.Symbol] = append(s.pendingBySymbol[meta.Symbol], order)
	s.pendingMu.Unlock()

	// 推 WS
	if s.pusher != nil {
		s.pusher.PushToUser(userID, map[string]any{
			"type":     "spot_order_placed",
			"order_id": order.ID,
			"symbol":   order.Symbol,
			"side":     order.Side,
			"qty":      order.Qty,
			"price":    order.Price,
			"time":     time.Now().Unix(),
		})
	}

	return order, nil
}

// CancelSpotOrder 取消限价单。
func (s *SpotService) CancelSpotOrder(ctx context.Context, userID, orderID string) error {
	if err := s.repo.ExecuteSpotLimitCancel(ctx, orderID, userID); err != nil {
		return err
	}

	// 从内存 pending 移除
	s.pendingMu.Lock()
	for sym, list := range s.pendingBySymbol {
		newList := list[:0]
		for _, o := range list {
			if o.ID != orderID {
				newList = append(newList, o)
			}
		}
		s.pendingBySymbol[sym] = newList
	}
	s.pendingMu.Unlock()

	// WS
	if s.pusher != nil {
		s.pusher.PushToUser(userID, map[string]any{
			"type":     "spot_order_cancelled",
			"order_id": orderID,
			"time":     time.Now().Unix(),
		})
	}

	return nil
}

// FillPendingSpotOrder 限价单成交（由 OnPriceUpdate 驱动）。
func (s *SpotService) FillPendingSpotOrder(ctx context.Context, order *model.SpotOrder, fillPrice float64) error {
	res, err := s.repo.ExecuteSpotLimitFill(ctx, order, fillPrice)
	if err != nil {
		return err
	}

	if s.referralSvc != nil && res.Fee > 0 {
		s.referralSvc.RecordCommissionEventAsync(order.UserID, res.Fee, model.ProductTypeSpot, res.OrderID)
	}

	meta, _ := s.getSymbolMeta(ctx, order.Symbol)
	if meta != nil {
		s.pushOrderUpdate(order.UserID, "spot_order_filled", res.OrderID, meta, order.Side, order.Qty, fillPrice, res.Fee)
		s.pushBalanceUpdate(order.UserID, meta, res.BaseAvailable, res.QuoteAvailable)
	}

	return nil
}

// ListSpotOrders 用户订单列表。
func (s *SpotService) ListSpotOrders(ctx context.Context, userID, status, symbol string, limit, offset int) ([]*model.SpotOrder, int, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	return s.repo.ListUserOrders(ctx, userID, status, symbol, limit, offset)
}

// GetSpotAccount 返回现货账户概览（持仓 + 估值）。
func (s *SpotService) GetSpotAccount(ctx context.Context, userID string) (*model.SpotAccountInfo, error) {
	// 复用 assets_repo 的 ListSpotBalances 比较好；但为最小耦合这里直接查
	holdings := []model.SpotAccountHolding{}

	// 拿所有支持的币种 + USDT/USD 计价资产 → 列出余额
	syms, err := s.repo.ListSupportedSymbols(ctx, "", true)
	if err != nil {
		return nil, err
	}

	// 收集所有相关 asset code（base + quote）
	assetSet := map[string]struct{}{
		"USDT": {},
		"USD":  {},
	}
	for _, sm := range syms {
		assetSet[sm.BaseAsset] = struct{}{}
		assetSet[sm.QuoteAsset] = struct{}{}
	}

	totalUsdt := 0.0
	for asset := range assetSet {
		avail, frozen, err := s.repo.GetSpotBalance(ctx, userID, asset)
		if err != nil {
			continue
		}
		if avail == 0 && frozen == 0 {
			continue
		}

		// 估值：USDT/USD 直接 = amount，其它币按当前价格
		valuation := 0.0
		if asset == "USDT" || asset == "USD" {
			valuation = avail + frozen
		} else {
			// 找一个交易对计价（默认 /USDT 或 /USD）
			pair := asset + "/USDT"
			if _, err := s.getSymbolMeta(ctx, pair); err != nil {
				pair = asset + "/USD"
			}
			if px, err := s.getPrice(pair); err == nil && px > 0 {
				valuation = (avail + frozen) * px
			}
		}
		totalUsdt += valuation

		holdings = append(holdings, model.SpotAccountHolding{
			Asset:         asset,
			Available:     avail,
			Frozen:        frozen,
			ValuationUSDT: valuation,
		})
	}

	return &model.SpotAccountInfo{
		UserID:             userID,
		TotalValuationUSDT: totalUsdt,
		Holdings:           holdings,
	}, nil
}

// ListSupportedSymbols 公开端点：上架交易对。
func (s *SpotService) ListSupportedSymbols(ctx context.Context, category string) ([]model.SpotSupportedSymbol, error) {
	return s.repo.ListSupportedSymbols(ctx, category, true)
}

// GetFeeSchedule 公开端点：所有 VIP 等级的现货费率。
func (s *SpotService) GetFeeSchedule(ctx context.Context) ([]model.SpotFeeTier, error) {
	return s.repo.ListFeeSchedule(ctx)
}

// ── helpers ──

func (s *SpotService) getSymbolMeta(ctx context.Context, symbol string) (*model.SpotSupportedSymbol, error) {
	s.symbolMu.RLock()
	if m, ok := s.symbolMeta[symbol]; ok {
		s.symbolMu.RUnlock()
		return m, nil
	}
	s.symbolMu.RUnlock()

	// fallback DB
	m, err := s.repo.GetSupportedSymbol(ctx, symbol)
	if err != nil {
		return nil, err
	}
	if !m.IsActive {
		return nil, fmt.Errorf("symbol %s is disabled", symbol)
	}
	s.symbolMu.Lock()
	s.symbolMeta[symbol] = m
	s.symbolMu.Unlock()
	return m, nil
}

func (s *SpotService) getPrice(symbol string) (float64, error) {
	s.priceMu.RLock()
	if p, ok := s.priceCache[symbol]; ok && p > 0 {
		s.priceMu.RUnlock()
		return p, nil
	}
	s.priceMu.RUnlock()

	// 转换 BTC/USDT → btcusdt 给 binance
	if s.binance != nil {
		if p, err := s.binance.GetPrice(symbol); err == nil && p > 0 {
			s.priceMu.Lock()
			s.priceCache[symbol] = p
			s.priceMu.Unlock()
			return p, nil
		}
	}

	// fallback Polygon for stocks (e.g. AAPL/USD → AAPL)
	if s.polygon != nil {
		ticker := strings.TrimSuffix(symbol, "/USD")
		ticker = strings.TrimSuffix(ticker, "/USDT")
		if snaps, err := s.polygon.GetSnapshotParsed([]string{ticker}); err == nil {
			if snap, ok := snaps[ticker]; ok {
				if px, ok := snap["price"].(float64); ok && px > 0 {
					s.priceMu.Lock()
					s.priceCache[symbol] = px
					s.priceMu.Unlock()
					return px, nil
				}
			}
		}
	}

	return 0, fmt.Errorf("price unavailable for %s", symbol)
}

func (s *SpotService) pushOrderUpdate(userID, eventType, orderID string, meta *model.SpotSupportedSymbol, side string, qty, price, fee float64) {
	if s.pusher == nil {
		return
	}
	s.pusher.PushToUser(userID, map[string]any{
		"type":     eventType,
		"order_id": orderID,
		"symbol":   meta.Symbol,
		"side":     side,
		"qty":      qty,
		"price":    price,
		"fee":      fee,
		"time":     time.Now().Unix(),
	})
}

func (s *SpotService) pushBalanceUpdate(userID string, meta *model.SpotSupportedSymbol, baseAvail, quoteAvail float64) {
	if s.pusher == nil {
		return
	}
	s.pusher.PushToUser(userID, map[string]any{
		"type": "spot_balance_update",
		"balances": map[string]float64{
			meta.BaseAsset:  baseAvail,
			meta.QuoteAsset: quoteAvail,
		},
		"time": time.Now().Unix(),
	})
}

// roundDown 保留 n 位小数（向下取整）。
func roundDown(v float64, precision int) float64 {
	if precision < 0 {
		precision = 0
	}
	if precision > 18 {
		precision = 18
	}
	multiplier := math.Pow10(precision)
	return math.Floor(v*multiplier) / multiplier
}
