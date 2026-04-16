package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"tongxin-go/internal/config"
	"tongxin-go/internal/handler"
	"tongxin-go/internal/integrations/udun"
	"tongxin-go/internal/market"
	mw "tongxin-go/internal/middleware"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/scheduler"
	"tongxin-go/internal/service"
	"tongxin-go/internal/ws"
)

func main() {
	cfg := config.Load()
	var chatRedisCancel context.CancelFunc
	var rdb *redis.Client

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// ── Database ──
	var userRepo *repository.UserRepo
	var friendRepo *repository.FriendRepo
	var convRepo *repository.ConversationRepo
	var msgRepo *repository.MessageRepo
	var teacherRepo *repository.TeacherRepo
	var watchlistRepo *repository.WatchlistRepo
	var callRepo *repository.CallRepo
	var supportRepo *repository.SupportRepo
	var assetsRepo *repository.AssetsRepo

	var dbCloser func()
	var pool *pgxpool.Pool

	if cfg.DatabaseURL != "" {
		var err error
		pool, err = repository.NewPool(ctx, cfg.DatabaseURL)
		if err != nil {
			log.Printf("[WARN] Database unavailable: %v (running without DB)", err)
		} else {
			dbCloser = pool.Close
			userRepo = repository.NewUserRepo(pool)
			friendRepo = repository.NewFriendRepo(pool)
			convRepo = repository.NewConversationRepo(pool)
			msgRepo = repository.NewMessageRepo(pool)
			callRepo = repository.NewCallRepo(pool)
			teacherRepo = repository.NewTeacherRepo(pool)
			watchlistRepo = repository.NewWatchlistRepo(pool)
			supportRepo = repository.NewSupportRepo(pool)
			assetsRepo = repository.NewAssetsRepo(pool)
			log.Println("[OK] Database connected")
		}
	} else {
		log.Println("[WARN] DATABASE_URL not set, running without database")
	}

	// ── JWT Auth ──
	jwtSecret := cfg.JWTSecret
	if jwtSecret == "" {
		jwtSecret = "tongxin-dev-secret-change-in-production"
		log.Println("[WARN] JWT_SECRET not set, using default dev secret")
	}
	authMw := mw.NewJWTAuthMiddleware(jwtSecret)
	log.Println("[OK] JWT Auth initialized")

	// ── Services ──
	var userSvc *service.UserService
	var friendSvc *service.FriendService
	var msgSvc *service.MessageService
	var teacherSvc *service.TeacherService
	var callSvc *service.CallService
	var supportSvc *service.SupportService
	var chatProfileSvc *service.ChatProfileService
	var udunClient *udun.Client
	var udunStatus string

	if userRepo != nil {
		userSvc = service.NewUserService(userRepo)
	}
	if friendRepo != nil {
		friendSvc = service.NewFriendService(friendRepo)
	}
	if msgRepo != nil && convRepo != nil {
		msgSvc = service.NewMessageService(msgRepo, convRepo)
	}
	if callRepo != nil && convRepo != nil {
		callSvc = service.NewCallService(callRepo, convRepo)
	}
	if supportRepo != nil && userRepo != nil && convRepo != nil {
		supportSvc = service.NewSupportService(supportRepo, userRepo, convRepo)
	}
	if teacherRepo != nil {
		teacherSvc = service.NewTeacherService(teacherRepo)
	}
	if cfg.UdunEnabled {
		client, err := udun.NewFromAppConfig(cfg)
		if err != nil {
			udunStatus = err.Error()
			log.Printf("[WARN] Udun client unavailable: %v", err)
		} else {
			udunClient = client
			udunStatus = "ready"
			log.Println("[OK] Udun client initialized")
		}
	} else {
		udunStatus = "UDUN_ENABLED=false"
	}

	// ── Market Data ──
	cache := market.NewCache()
	var polygonClient *market.PolygonClient
	if cfg.PolygonAPIKey != "" {
		polygonClient = market.NewPolygonClient(cfg.PolygonAPIKey, cache)
		log.Println("[OK] Polygon client initialized")
	}

	binance := market.NewBinanceIngestor()
	cryptoSymbols := []string{
		"btcusdt", "ethusdt", "bnbusdt", "solusdt", "xrpusdt",
		"dogeusdt", "adausdt", "avaxusdt", "dotusdt", "maticusdt",
		"linkusdt", "uniusdt", "shibusdt", "ltcusdt", "trxusdt",
		"atomusdt", "nearusdt", "aptusdt", "arbusdt", "opusdt",
		"filusdt", "icpusdt", "aaveusdt", "grtusdt", "mkrusdt",
		"imxusdt", "injusdt", "runeusdt", "ftmusdt", "algousdt",
		"xlmusdt", "vetusdt", "sandusdt", "manausdt", "axsusdt",
		"thetausdt", "eosusdt", "iotausdt", "xtzusdt", "flowusdt",
		"chzusdt", "crvusdt", "ldousdt", "snxusdt", "compusdt",
		"zecusdt", "dashusdt", "enjusdt", "batusdt", "1inchusdt",
		"sushiusdt", "yfiusdt", "zrxusdt", "ksmusdt", "celousdt",
		"qtumusdt", "icxusdt", "ontusdt", "zilusdt", "wavesusdt",
		"ankrusdt", "sklusdt", "renusdt", "srmusdt", "dydxusdt",
		"maskusdt", "api3usdt", "bandusdt", "oceanusdt", "storjusdt",
		"nknusdt", "suiusdt", "seiusdt", "tiausdt", "jupusdt",
		"wifusdt", "bonkusdt", "pepeusdt", "flokiusdt", "ordiusdt",
		"stxusdt", "pythusdt", "jtousdt", "blurusdt", "strkusdt",
		"memeusdt", "wldusdt", "cyberusdt", "arkmusdt", "pendleusdt",
		"gmxusdt", "ssvusdt", "rplusdt", "fxsusdt", "osmousdt",
		"kavausdt", "cfxusdt", "fetusdt", "rndrusdt",
		"arusdt", "hntusdt", "roseusdt", "bchusdt", "etcusdt",
	}
	binance.Start(cryptoSymbols)
	log.Println("[OK] Binance crypto ingestor started")

	// ── Polygon WebSocket (stocks + forex on separate endpoints / keys) ──
	var polygonWS, forexWS *market.PolygonWS
	if cfg.PolygonAPIKey != "" {
		polygonWS = market.NewPolygonWS(cfg.PolygonAPIKey, "stocks")
		polygonWS.Start()
		log.Println("[OK] Polygon WebSocket started (stocks)")
	}
	forexKey := cfg.PolygonForexAPIKey
	if forexKey == "" {
		forexKey = cfg.PolygonAPIKey
	}
	if forexKey != "" {
		forexWS = market.NewPolygonWS(forexKey, "forex")
		forexWS.Start()
		log.Println("[OK] Polygon WebSocket started (forex)")
	}

	// ── Redis (optional: chat WS fan-out across instances; Postgres remains source of truth) ──
	if cfg.RedisURL != "" {
		opt, err := redis.ParseURL(cfg.RedisURL)
		if err != nil {
			log.Printf("[WARN] REDIS_URL invalid: %v (chat uses in-process broadcast only)", err)
		} else {
			rdb = redis.NewClient(opt)
			pingCtx, pingCancel := context.WithTimeout(context.Background(), 3*time.Second)
			err = rdb.Ping(pingCtx).Err()
			pingCancel()
			if err != nil {
				log.Printf("[WARN] Redis ping failed: %v (chat uses in-process broadcast only)", err)
				_ = rdb.Close()
				rdb = nil
			} else {
				log.Println("[OK] Redis connected (chat Pub/Sub)")
			}
		}
	}

	// ── WebSocket Hubs ──
	var chatHub *ws.ChatHub
	if msgSvc != nil && userSvc != nil {
		chatHub = ws.NewChatHub(msgSvc, userSvc, rdb)
		log.Println("[OK] Chat WebSocket hub initialized")
		if rdb != nil {
			var redisSubCtx context.Context
			redisSubCtx, chatRedisCancel = context.WithCancel(context.Background())
			go chatHub.RunRedisSubscriber(redisSubCtx)
		}
	}

	marketHub := ws.NewMarketHub(polygonClient, polygonWS, forexWS, binance)
	marketHub.StartRealtime()
	log.Println("[OK] Market WebSocket hub initialized (real-time)")

	// ── Router ──
	mux := http.NewServeMux()

	// Public routes
	mux.HandleFunc("GET /api/health", handler.HealthCheck)
	mux.HandleFunc("GET /api/version", handler.Version)

	// Static file serving for uploads
	uploadH := handler.NewUploadHandler(cfg.StoragePath)
	fs := http.FileServer(http.Dir(cfg.StoragePath))
	mux.Handle("GET /uploads/", http.StripPrefix("/uploads/", fs))

	// Market routes (no auth required)
	if polygonClient != nil {
		marketH := handler.NewMarketHandler(polygonClient, binance)

		// Original /api/market/* routes
		mux.HandleFunc("GET /api/market/snapshot", marketH.Snapshot)
		mux.HandleFunc("GET /api/market/candles", marketH.Candles)
		mux.HandleFunc("GET /api/market/search", marketH.Search)
		mux.HandleFunc("GET /api/market/gainers", marketH.Gainers)
		mux.HandleFunc("GET /api/market/losers", marketH.Losers)
		mux.HandleFunc("GET /api/market/crypto/prices", marketH.CryptoPrices)
		mux.HandleFunc("GET /api/market/snapshots", marketH.Snapshots)

		// Frontend-compatible short aliases
		mux.HandleFunc("GET /api/quotes", marketH.Quotes)
		mux.HandleFunc("GET /api/candles", marketH.Candles)
		mux.HandleFunc("GET /api/search", marketH.Search)
		mux.HandleFunc("GET /api/gainers", marketH.Gainers)
		mux.HandleFunc("GET /api/losers", marketH.Losers)
		mux.HandleFunc("GET /api/tickers-page", marketH.TickersPage)
		mux.HandleFunc("GET /api/funding-rate", marketH.FundingRate)

		// Crypto routes
		mux.HandleFunc("GET /api/crypto/quotes", marketH.CryptoQuotes)
		mux.HandleFunc("GET /api/crypto/pairs", marketH.CryptoPairs)
		mux.HandleFunc("GET /api/crypto/depth", marketH.CryptoDepth)

		// Forex routes
		mux.HandleFunc("GET /api/forex/pairs", marketH.ForexPairs)
		mux.HandleFunc("GET /api/forex/quotes", marketH.ForexQuotes)

		// Futures routes
		mux.HandleFunc("GET /api/futures/quotes", marketH.FuturesQuotes)

		// News
		mux.HandleFunc("GET /api/news", marketH.News)
		mux.HandleFunc("GET /api/news/hot", marketH.News)

		log.Println("[OK] Market routes registered")
	} else {
		marketH := handler.NewMarketHandler(nil, binance)
		mux.HandleFunc("GET /api/market/crypto/prices", marketH.CryptoPrices)
		mux.HandleFunc("GET /api/crypto/quotes", marketH.CryptoQuotes)
		mux.HandleFunc("GET /api/crypto/pairs", marketH.CryptoPairs)
		mux.HandleFunc("GET /api/crypto/depth", marketH.CryptoDepth)
	}

	// Market WebSocket (no auth required)
	mux.HandleFunc("GET /ws/market", marketHub.HandleWS)

	// ── Auth routes (register/login are PUBLIC) ──
	if userSvc != nil {
		authH := handler.NewAuthHandler(userSvc)
		usersH := handler.NewUsersHandler(userSvc)

		// Public — no token needed
		mux.HandleFunc("POST /api/auth/register", authH.Register)
		mux.HandleFunc("POST /api/auth/login", authH.Login)

		// Protected — token needed
		mux.Handle("GET /api/auth/profile", authMw.Authenticate(http.HandlerFunc(authH.GetProfile)))
		mux.Handle("PUT /api/auth/profile", authMw.Authenticate(http.HandlerFunc(authH.UpdateProfile)))
		mux.Handle("POST /api/auth/change-password", authMw.Authenticate(http.HandlerFunc(authH.ChangePassword)))
		mux.Handle("POST /api/auth/change-email", authMw.Authenticate(http.HandlerFunc(authH.ChangeEmail)))
		mux.Handle("GET /api/auth/delete-account/check", authMw.Authenticate(http.HandlerFunc(authH.CheckDeleteAccount)))
		mux.Handle("POST /api/auth/delete-account", authMw.Authenticate(http.HandlerFunc(authH.DeleteAccount)))
		mux.Handle("GET /api/auth/profile/{id}", authMw.Authenticate(http.HandlerFunc(authH.GetProfileByID)))

		mux.Handle("GET /api/users/batch-profiles", authMw.Authenticate(http.HandlerFunc(usersH.BatchProfiles)))
		mux.Handle("GET /api/user-profiles/batch", authMw.Authenticate(http.HandlerFunc(usersH.BatchProfiles)))
		mux.Handle("GET /api/users", authMw.Authenticate(http.HandlerFunc(usersH.ListUsers)))

		log.Println("[OK] Auth + User routes registered")
	}

	// Friends
	if friendSvc != nil && userSvc != nil {
		friendsH := handler.NewFriendsHandler(friendSvc, userSvc, chatHub)
		usersH := handler.NewUsersHandler(userSvc)
		mux.Handle("GET /api/friends", authMw.Authenticate(http.HandlerFunc(friendsH.ListFriends)))
		mux.Handle("GET /api/friends/search", authMw.Authenticate(http.HandlerFunc(usersH.SearchUsers)))
		mux.Handle("POST /api/friends/request", authMw.Authenticate(http.HandlerFunc(friendsH.SendRequest)))
		mux.Handle("POST /api/friends/requests", authMw.Authenticate(http.HandlerFunc(friendsH.SendRequest)))
		mux.Handle("POST /api/friends/accept", authMw.Authenticate(http.HandlerFunc(friendsH.AcceptRequest)))
		mux.Handle("POST /api/friends/reject", authMw.Authenticate(http.HandlerFunc(friendsH.RejectRequest)))
		mux.Handle("GET /api/friends/incoming", authMw.Authenticate(http.HandlerFunc(friendsH.GetIncoming)))
		mux.Handle("GET /api/friends/outgoing", authMw.Authenticate(http.HandlerFunc(friendsH.GetOutgoing)))
		mux.Handle("DELETE /api/friends/{id}", authMw.Authenticate(http.HandlerFunc(friendsH.DeleteFriend)))
		mux.Handle("POST /api/friends/block", authMw.Authenticate(http.HandlerFunc(friendsH.BlockUser)))
		log.Println("[OK] Friends routes registered")
	}

	// Conversations + Messages
	if msgSvc != nil {
		convH := handler.NewConversationsHandler(msgSvc)
		msgsH := handler.NewMessagesHandler(msgSvc, chatHub)
		mux.Handle("GET /api/conversations", authMw.Authenticate(http.HandlerFunc(convH.List)))
		mux.Handle("GET /api/conversations/unread-count", authMw.Authenticate(http.HandlerFunc(convH.UnreadCount)))
		mux.Handle("GET /api/conversations/{id}", authMw.Authenticate(http.HandlerFunc(convH.GetByID)))
		mux.Handle("POST /api/conversations/direct", authMw.Authenticate(http.HandlerFunc(convH.CreateDirect)))
		mux.Handle("POST /api/conversations/group", authMw.Authenticate(http.HandlerFunc(convH.CreateGroup)))
		mux.Handle("PATCH /api/conversations/{id}/read", authMw.Authenticate(http.HandlerFunc(convH.MarkAsRead)))
		mux.Handle("GET /api/conversations/{id}/group-info", authMw.Authenticate(http.HandlerFunc(convH.GroupInfo)))
		mux.Handle("PUT /api/conversations/{id}/group-info", authMw.Authenticate(http.HandlerFunc(convH.UpdateGroupInfo)))
		mux.Handle("POST /api/conversations/{id}/members", authMw.Authenticate(http.HandlerFunc(convH.AddMembers)))
		mux.Handle("PATCH /api/conversations/{id}/members/{userId}/role", authMw.Authenticate(http.HandlerFunc(convH.UpdateMemberRole)))
		mux.Handle("DELETE /api/conversations/{id}/members/{userId}", authMw.Authenticate(http.HandlerFunc(convH.RemoveMember)))
		mux.Handle("DELETE /api/conversations/{id}", authMw.Authenticate(http.HandlerFunc(convH.Dissolve)))
		mux.Handle("GET /api/conversations/{id}/messages/search", authMw.Authenticate(http.HandlerFunc(msgsH.Search)))
		mux.Handle("GET /api/conversations/{id}/messages", authMw.Authenticate(http.HandlerFunc(msgsH.ListByConversation)))
		mux.Handle("POST /api/messages", authMw.Authenticate(http.HandlerFunc(msgsH.Send)))
		mux.Handle("DELETE /api/messages/{id}", authMw.Authenticate(http.HandlerFunc(msgsH.Delete)))
		log.Println("[OK] Conversations + Messages routes registered")
	}

	if supportSvc != nil {
		supportH := handler.NewSupportHandler(supportSvc, chatHub)
		mux.Handle("GET /api/support/me", authMw.Authenticate(http.HandlerFunc(supportH.GetMyAssignment)))
		mux.Handle("POST /api/support/me/ensure", authMw.Authenticate(http.HandlerFunc(supportH.EnsureMyAssignment)))
		log.Println("[OK] Support user routes registered")
	}

	if callSvc != nil {
		callsH := handler.NewCallsHandler(callSvc, chatHub, cfg)
		mux.Handle("POST /api/calls/start", authMw.Authenticate(http.HandlerFunc(callsH.Start)))
		mux.Handle("GET /api/calls/{id}", authMw.Authenticate(http.HandlerFunc(callsH.Get)))
		mux.Handle("GET /api/calls/{id}/livekit-token", authMw.Authenticate(http.HandlerFunc(callsH.LiveKitToken)))
		mux.Handle("POST /api/calls/{id}/accept", authMw.Authenticate(http.HandlerFunc(callsH.Accept)))
		mux.Handle("POST /api/calls/{id}/reject", authMw.Authenticate(http.HandlerFunc(callsH.Reject)))
		mux.Handle("POST /api/calls/{id}/end", authMw.Authenticate(http.HandlerFunc(callsH.End)))
		log.Println("[OK] Calls routes registered")
	}

	// Chat WebSocket
	if chatHub != nil {
		mux.HandleFunc("GET /ws/chat", func(w http.ResponseWriter, r *http.Request) {
			token := r.URL.Query().Get("token")
			if token == "" {
				http.Error(w, "token required", http.StatusUnauthorized)
				return
			}
			claims, err := mw.VerifyJWT(token, mw.JWTSecret)
			if err != nil {
				http.Error(w, "invalid token", http.StatusUnauthorized)
				return
			}
			uid, _ := claims["uid"].(string)
			if uid == "" {
				http.Error(w, "invalid token", http.StatusUnauthorized)
				return
			}
			chatHub.HandleWS(w, r, uid)
		})
		log.Println("[OK] Chat WebSocket registered")
	}

	// Teachers
	if teacherSvc != nil {
		teachersH := handler.NewTeachersHandler(teacherSvc)
		mux.HandleFunc("GET /api/teachers", teachersH.List)
		mux.HandleFunc("GET /api/teachers/featured", teachersH.Featured)
		mux.Handle("GET /api/teachers/my", authMw.Authenticate(http.HandlerFunc(teachersH.GetMy)))
		mux.Handle("PUT /api/teachers/my", authMw.Authenticate(http.HandlerFunc(teachersH.UpdateMy)))
		mux.Handle("POST /api/teachers/apply", authMw.Authenticate(http.HandlerFunc(teachersH.Apply)))
		mux.Handle("POST /api/teachers/strategies", authMw.Authenticate(http.HandlerFunc(teachersH.CreateStrategy)))
		mux.Handle("DELETE /api/strategy/{id}", authMw.Authenticate(http.HandlerFunc(teachersH.DeleteStrategy)))
		mux.Handle("POST /api/strategy/{id}/like", authMw.Authenticate(http.HandlerFunc(teachersH.LikeStrategy)))
		mux.HandleFunc("GET /api/teachers/{id}/strategies", teachersH.ListStrategies)
		mux.HandleFunc("GET /api/teachers/{id}", teachersH.GetByID)
		mux.Handle("POST /api/teachers/{id}/follow", authMw.Authenticate(http.HandlerFunc(teachersH.Follow)))
		mux.Handle("DELETE /api/teachers/{id}/follow", authMw.Authenticate(http.HandlerFunc(teachersH.Unfollow)))
		log.Println("[OK] Teachers routes registered")
	}

	// Native Trading + Wallet
	var tradingHub *ws.TradingHub
	var tradingSvc *service.TradingService
	var walletRepo *repository.WalletRepo
	var orderRepo *repository.OrderRepo
	var positionRepo *repository.PositionRepo
	var feeRepo *repository.FeeRepo
	if pool != nil {
		walletRepo = repository.NewWalletRepo(pool)
		orderRepo = repository.NewOrderRepo(pool)
		positionRepo = repository.NewPositionRepo(pool)
		feeRepo = repository.NewFeeRepo(pool)
		traderRepoEarly := repository.NewTraderRepo(pool)

		tradingHub = ws.NewTradingHub()

		tradingSvc = service.NewTradingService(walletRepo, orderRepo, positionRepo, userRepo, traderRepoEarly, feeRepo, binance, polygonClient, tradingHub)
		tradingSvc.ProfitShareEnabled = cfg.ProfitShareEnabled

		// Load fee schedule from DB
		tradingSvc.LoadFeeSchedule(context.Background())

		// Load pending limit orders into memory and hook price updates
		tradingSvc.LoadPendingOrders(context.Background())
		tradingSvc.LoadOpenPositions(context.Background())
		marketHub.SetOnPriceUpdate(tradingSvc.OnPriceUpdate)

		tradingH := handler.NewTradingHandler(tradingSvc)
		walletH := handler.NewWalletHandler(walletRepo, tradingHub)

		// Trading routes
		mux.Handle("POST /api/trading/orders", authMw.Authenticate(http.HandlerFunc(tradingH.CreateOrder)))
		mux.Handle("GET /api/trading/orders", authMw.Authenticate(http.HandlerFunc(tradingH.ListOrders)))
		mux.Handle("DELETE /api/trading/orders/{id}", authMw.Authenticate(http.HandlerFunc(tradingH.CancelOrder)))
		mux.Handle("GET /api/trading/positions", authMw.Authenticate(http.HandlerFunc(tradingH.ListPositions)))
		mux.Handle("DELETE /api/trading/positions/{id}", authMw.Authenticate(http.HandlerFunc(tradingH.ClosePosition)))
		mux.Handle("GET /api/trading/account", authMw.Authenticate(http.HandlerFunc(tradingH.GetAccount)))
		mux.Handle("GET /api/trading/history", authMw.Authenticate(http.HandlerFunc(tradingH.GetHistory)))
		mux.Handle("GET /api/trading/positions/history", authMw.Authenticate(http.HandlerFunc(tradingH.ListPositionHistory)))
		mux.Handle("PUT /api/trading/positions/{id}/tp-sl", authMw.Authenticate(http.HandlerFunc(tradingH.UpdateTPSL)))
		mux.Handle("POST /api/trading/positions/{id}/partial-close", authMw.Authenticate(http.HandlerFunc(tradingH.PartialClosePosition)))
		mux.HandleFunc("GET /api/trading/fee-schedule", tradingH.GetFeeSchedule)
		mux.Handle("GET /api/trading/vip-info", authMw.Authenticate(http.HandlerFunc(tradingH.GetVipInfo)))

		// Wallet routes
		mux.Handle("POST /api/wallet/deposit", authMw.Authenticate(http.HandlerFunc(walletH.Deposit)))
		mux.Handle("GET /api/wallet", authMw.Authenticate(http.HandlerFunc(walletH.GetBalance)))
		mux.Handle("GET /api/wallet/transactions", authMw.Authenticate(http.HandlerFunc(walletH.GetTransactions)))

		log.Println("[OK] Native trading + wallet routes registered")
	}

	// ── Referral / Agent program ──
	var referralSvc *service.ReferralService
	var commissionScheduler *scheduler.Scheduler
	if pool != nil {
		referralRepo := repository.NewReferralRepo(pool)
		referralSvc = service.NewReferralService(cfg, referralRepo)

		commissionScheduler = scheduler.NewScheduler(cfg, referralSvc)
		commissionScheduler.Start()
	}

	// Wire referral into trading service for fee instrumentation (commit 6)
	if tradingSvc != nil && referralSvc != nil {
		tradingSvc.ReferralSvc = referralSvc
	}

	var assetsSvc *service.AssetsService

	// Assets (read-only aggregation first; no copy bucket writes here)
	if assetsRepo != nil {
		assetsSvc = service.NewAssetsService(assetsRepo, walletRepo, tradingSvc, udunClient, udunStatus)
		assetsH := handler.NewAssetsHandler(assetsSvc)
		callbackSecret := strings.TrimSpace(cfg.UdunSignSecret)
		if callbackSecret == "" {
			callbackSecret = strings.TrimSpace(cfg.UdunAPIKey)
		}
		udunCallbackH := handler.NewUdunCallbackHandler(assetsSvc, callbackSecret)
		mux.HandleFunc("POST /api/integrations/udun/callback/deposit", udunCallbackH.Deposit)
		mux.HandleFunc("POST /api/integrations/udun/callback/withdraw", udunCallbackH.Withdraw)
		mux.Handle("GET /api/assets/overview", authMw.Authenticate(http.HandlerFunc(assetsH.GetOverview)))
		mux.Handle("GET /api/assets/copy-summary", authMw.Authenticate(http.HandlerFunc(assetsH.GetCopySummary)))
		mux.Handle("GET /api/assets/transactions", authMw.Authenticate(http.HandlerFunc(assetsH.GetTransactions)))
		mux.Handle("GET /api/assets/deposits", authMw.Authenticate(http.HandlerFunc(assetsH.GetDepositRecords)))
		mux.Handle("GET /api/assets/deposit-options", authMw.Authenticate(http.HandlerFunc(assetsH.GetDepositOptions)))
		mux.Handle("GET /api/assets/deposit-addresses", authMw.Authenticate(http.HandlerFunc(assetsH.GetDepositAddresses)))
		mux.Handle("POST /api/assets/deposit-addresses", authMw.Authenticate(http.HandlerFunc(assetsH.CreateDepositAddress)))
		mux.Handle("POST /api/assets/deposit", authMw.Authenticate(http.HandlerFunc(assetsH.Deposit)))
		mux.Handle("POST /api/assets/withdraw", authMw.Authenticate(http.HandlerFunc(assetsH.Withdraw)))
		mux.Handle("POST /api/assets/transfer", authMw.Authenticate(http.HandlerFunc(assetsH.Transfer)))
		log.Println("[OK] Assets routes registered")
	}

	// Trading WebSocket (authenticated)
	if tradingHub != nil {
		mux.HandleFunc("GET /ws/trading", func(w http.ResponseWriter, r *http.Request) {
			token := r.URL.Query().Get("token")
			if token == "" {
				http.Error(w, "token required", http.StatusUnauthorized)
				return
			}
			claims, err := mw.VerifyJWT(token, mw.JWTSecret)
			if err != nil {
				http.Error(w, "invalid token", http.StatusUnauthorized)
				return
			}
			uid, _ := claims["uid"].(string)
			if uid == "" {
				http.Error(w, "invalid token", http.StatusUnauthorized)
				return
			}
			tradingHub.HandleWS(w, r, uid)
		})
		log.Println("[OK] Trading WebSocket registered")
	}

	// Watchlist
	if watchlistRepo != nil {
		watchlistH := handler.NewWatchlistHandler(watchlistRepo)
		mux.Handle("GET /api/watchlist", authMw.Authenticate(http.HandlerFunc(watchlistH.List)))
		mux.Handle("POST /api/watchlist", authMw.Authenticate(http.HandlerFunc(watchlistH.Add)))
		mux.Handle("DELETE /api/watchlist/{symbol}", authMw.Authenticate(http.HandlerFunc(watchlistH.Remove)))
		mux.Handle("GET /api/watchlist/check", authMw.Authenticate(http.HandlerFunc(watchlistH.Check)))
		log.Println("[OK] Watchlist routes registered")
	}

	// Upload
	mux.Handle("POST /api/upload", authMw.Authenticate(http.HandlerFunc(uploadH.Upload)))

	// Feedback
	var feedbackH *handler.FeedbackHandler
	if pool != nil {
		feedbackRepo := repository.NewFeedbackRepo(pool)
		feedbackH = handler.NewFeedbackHandler(feedbackRepo)
		mux.Handle("POST /api/feedbacks", authMw.Authenticate(http.HandlerFunc(feedbackH.Create)))
		mux.Handle("GET /api/feedbacks", authMw.Authenticate(http.HandlerFunc(feedbackH.ListMy)))
		// 具体路径放在 {id} 前面，net/http ServeMux 按最具体匹配；这里保险起见明确注册
		mux.Handle("GET /api/feedbacks/unread-count", authMw.Authenticate(http.HandlerFunc(feedbackH.UnreadCount)))
		mux.Handle("GET /api/feedbacks/{id}", authMw.Authenticate(http.HandlerFunc(feedbackH.GetOne)))
		mux.Handle("POST /api/feedbacks/{id}/read", authMw.Authenticate(http.HandlerFunc(feedbackH.MarkRead)))
		log.Println("[OK] Feedback routes registered")
	}

	// Trader system
	var traderSvc *service.TraderService
	if pool != nil {
		traderRepo := repository.NewTraderRepo(pool)
		traderSvc = service.NewTraderService(traderRepo, walletRepo)
		traderSvc.ProfitShareEnabled = cfg.ProfitShareEnabled
		chatProfileSvc = service.NewChatProfileService(userSvc, friendSvc, traderSvc)
		traderH := handler.NewTraderHandler(traderSvc, tradingSvc)

		// Public trader routes (profile uses optional auth for is_followed)
		mux.HandleFunc("GET /api/trader/rankings", traderH.Rankings)
		mux.Handle("GET /api/trader/{uid}/profile", authMw.OptionalAuth(http.HandlerFunc(traderH.TraderProfile)))
		mux.HandleFunc("GET /api/trader/{uid}/positions", traderH.TraderPositions)
		mux.HandleFunc("GET /api/trader/{uid}/trades", traderH.TraderTrades)
		mux.HandleFunc("GET /api/trader/{uid}/equity", traderH.TraderEquity)

		// Authenticated trader routes
		mux.Handle("POST /api/trader/apply", authMw.Authenticate(http.HandlerFunc(traderH.Apply)))
		mux.Handle("GET /api/trader/my-application", authMw.Authenticate(http.HandlerFunc(traderH.MyApplication)))
		mux.Handle("GET /api/trader/my-stats", authMw.Authenticate(http.HandlerFunc(traderH.MyStats)))
		mux.Handle("PUT /api/trader/copy-trading-toggle", authMw.Authenticate(http.HandlerFunc(traderH.ToggleCopyTrading)))
		mux.Handle("GET /api/trader/my-followers", authMw.Authenticate(http.HandlerFunc(traderH.MyFollowers)))
		mux.Handle("GET /api/trader/my-following", authMw.Authenticate(http.HandlerFunc(traderH.MyFollowing)))
		mux.Handle("GET /api/trader/my-watched", authMw.Authenticate(http.HandlerFunc(traderH.MyWatchedTraders)))
		mux.Handle("POST /api/trader/{uid}/watch", authMw.Authenticate(http.HandlerFunc(traderH.WatchTrader)))
		mux.Handle("DELETE /api/trader/{uid}/watch", authMw.Authenticate(http.HandlerFunc(traderH.UnwatchTrader)))
		mux.Handle("POST /api/trader/{uid}/follow", authMw.Authenticate(http.HandlerFunc(traderH.FollowTrader)))
		mux.Handle("DELETE /api/trader/{uid}/follow", authMw.Authenticate(http.HandlerFunc(traderH.UnfollowTrader)))
		mux.Handle("PUT /api/trader/{uid}/follow/settings", authMw.Authenticate(http.HandlerFunc(traderH.UpdateCopySettings)))
		mux.Handle("PATCH /api/trader/{uid}/follow/capital", authMw.Authenticate(http.HandlerFunc(traderH.AdjustAllocatedCapital)))
		mux.Handle("POST /api/trader/{uid}/follow/pause", authMw.Authenticate(http.HandlerFunc(traderH.PauseCopyTrading)))
		mux.Handle("POST /api/trader/{uid}/follow/resume", authMw.Authenticate(http.HandlerFunc(traderH.ResumeCopyTrading)))
		mux.Handle("GET /api/trader/copy-trade-logs", authMw.Authenticate(http.HandlerFunc(traderH.CopyTradeLogs)))

		// Profit share (跟单分润) — trader 仪表盘
		mux.Handle("PUT /api/trader/profile/share-rate", authMw.Authenticate(http.HandlerFunc(traderH.UpdateDefaultShareRate)))
		mux.Handle("GET /api/trader/profit-share/summary", authMw.Authenticate(http.HandlerFunc(traderH.ProfitShareSummary)))
		mux.Handle("GET /api/trader/profit-share/records", authMw.Authenticate(http.HandlerFunc(traderH.ProfitShareRecords)))

		// Admin trader routes (require auth + admin role)
		adminTraderAuth := func(h http.HandlerFunc) http.Handler {
			return authMw.Authenticate(mw.RequireAdmin(pool)(http.HandlerFunc(h)))
		}
		mux.Handle("GET /api/admin/trader-applications", adminTraderAuth(traderH.AdminListApplications))
		mux.Handle("POST /api/admin/trader-applications/{id}/approve", adminTraderAuth(traderH.AdminApprove))
		mux.Handle("POST /api/admin/trader-applications/{id}/reject", adminTraderAuth(traderH.AdminReject))

		log.Println("[OK] Trader system routes registered")

		// Trader strategies
		traderStrategyRepo := repository.NewTraderStrategyRepo(pool)
		traderStrategySvc := service.NewTraderStrategyService(traderStrategyRepo, traderRepo)
		traderStrategyH := handler.NewTraderStrategyHandler(traderStrategySvc)

		// Public strategy routes
		mux.HandleFunc("GET /api/strategies/feed", traderStrategyH.Feed)
		mux.HandleFunc("GET /api/strategies/author/{uid}", traderStrategyH.ListByAuthor)
		mux.HandleFunc("GET /api/strategies/{id}", traderStrategyH.GetByID)

		// Authenticated strategy routes
		mux.Handle("POST /api/strategies", authMw.Authenticate(http.HandlerFunc(traderStrategyH.Create)))
		mux.Handle("GET /api/strategies/my", authMw.Authenticate(http.HandlerFunc(traderStrategyH.ListMy)))
		mux.Handle("PUT /api/strategies/{id}", authMw.Authenticate(http.HandlerFunc(traderStrategyH.Update)))
		mux.Handle("DELETE /api/strategies/{id}", authMw.Authenticate(http.HandlerFunc(traderStrategyH.Delete)))
		mux.Handle("POST /api/strategies/{id}/like", authMw.Authenticate(http.HandlerFunc(traderStrategyH.Like)))
		log.Println("[OK] Trader strategy routes registered")
	}

	if chatProfileSvc != nil {
		chatProfileH := handler.NewChatProfileHandler(chatProfileSvc, chatHub)
		mux.Handle("GET /api/users/{uid}/chat-profile", authMw.Authenticate(http.HandlerFunc(chatProfileH.Get)))
		log.Println("[OK] Chat profile route registered")
	}

	// Admin
	if userSvc != nil && teacherSvc != nil {
		adminH := handler.NewAdminHandler(userSvc, teacherSvc, traderSvc)
		adminAuth := func(h http.HandlerFunc) http.Handler {
			return authMw.Authenticate(mw.RequireAdmin(pool)(http.HandlerFunc(h)))
		}
		mux.Handle("GET /api/admin/users", adminAuth(adminH.ListUsers))
		mux.Handle("POST /api/admin/users/{uid}/role", adminAuth(adminH.UpdateUserRole))
		mux.Handle("POST /api/admin/users/{uid}/status", adminAuth(adminH.UpdateUserStatus))
		mux.Handle("POST /api/admin/users/{uid}/password", adminAuth(adminH.ResetUserPassword))
		mux.Handle("POST /api/admin/users/{uid}/support-agent", adminAuth(adminH.SetSupportAgent))
		mux.Handle("POST /api/admin/users/{uid}/trader", adminAuth(adminH.SetTrader))
		mux.Handle("GET /api/admin/teachers/pending", adminAuth(adminH.PendingTeachers))
		mux.Handle("POST /api/admin/teachers/{id}/approve", adminAuth(adminH.ApproveTeacher))
		mux.Handle("POST /api/admin/teachers/{id}/reject", adminAuth(adminH.RejectTeacher))
		mux.Handle("GET /api/admin/stats", adminAuth(adminH.Stats))
		mux.Handle("GET /api/admin/users/search", adminAuth(adminH.SearchUsers))
		mux.Handle("GET /api/admin/admins", adminAuth(adminH.ListAdmins))
		mux.Handle("POST /api/admin/admins", adminAuth(adminH.AddAdmin))
		mux.Handle("DELETE /api/admin/admins/{uid}", adminAuth(adminH.RemoveAdmin))
		if supportSvc != nil {
			supportH := handler.NewSupportHandler(supportSvc, chatHub)
			mux.Handle("GET /api/admin/support/agents", adminAuth(supportH.ListAgents))
			mux.Handle("GET /api/admin/support/agent-loads", adminAuth(supportH.AgentLoads))
			mux.Handle("GET /api/admin/users/{uid}/support-assignment", adminAuth(supportH.AdminGetAssignment))
			mux.Handle("POST /api/admin/users/{uid}/support-assignment", adminAuth(supportH.AdminAssign))
		}
		mux.Handle("POST /api/admin/announcements", adminAuth(adminH.CreateAnnouncement))
		mux.Handle("GET /api/admin/reports", adminAuth(adminH.ListReports))

		// Admin feedback routes
		if feedbackH != nil {
			mux.Handle("GET /api/admin/feedbacks", adminAuth(feedbackH.AdminList))
			mux.Handle("PUT /api/admin/feedbacks/{id}", adminAuth(feedbackH.AdminReply))
		}
		mux.HandleFunc("GET /api/announcements", adminH.ListAnnouncements)
		log.Println("[OK] Admin routes registered")

		// Admin Trading & Financial routes
		if tradingSvc != nil && feeRepo != nil {
			revenueRepo := repository.NewRevenueRepo(pool)
			tpaRepo := repository.NewThirdPartyApiRepo(pool)
			adminTradingH := handler.NewAdminTradingHandler(
				tradingSvc, assetsSvc, feeRepo, walletRepo, assetsRepo, positionRepo, orderRepo, userRepo, revenueRepo, tpaRepo,
			)

			// Fee management
			mux.Handle("GET /api/admin/fee-tiers", adminAuth(adminTradingH.ListFeeTiers))
			mux.Handle("POST /api/admin/fee-tiers", adminAuth(adminTradingH.CreateFeeTier))
			mux.Handle("PUT /api/admin/fee-tiers/{level}", adminAuth(adminTradingH.UpdateFeeTier))
			mux.Handle("DELETE /api/admin/fee-tiers/{level}", adminAuth(adminTradingH.DeleteFeeTier))
			mux.Handle("POST /api/admin/users/{uid}/vip-level", adminAuth(adminTradingH.SetUserVipLevel))
			mux.Handle("GET /api/admin/fee-stats", adminAuth(adminTradingH.GetFeeStats))

			// Position monitoring
			mux.Handle("GET /api/admin/positions", adminAuth(adminTradingH.ListAllPositions))
			mux.Handle("GET /api/admin/positions/summary", adminAuth(adminTradingH.PositionsSummary))

			// Liquidation data
			mux.Handle("GET /api/admin/liquidations", adminAuth(adminTradingH.ListLiquidations))
			mux.Handle("GET /api/admin/liquidations/stats", adminAuth(adminTradingH.LiquidationStats))

			// Financial management
			mux.Handle("GET /api/admin/revenue/daily", adminAuth(adminTradingH.DailyRevenue))
			mux.Handle("GET /api/admin/revenue/summary", adminAuth(adminTradingH.RevenueSummary))
			mux.Handle("POST /api/admin/revenue/snapshot", adminAuth(adminTradingH.TriggerSnapshot))

			// Third-party API management
			mux.Handle("GET /api/admin/third-party-apis", adminAuth(adminTradingH.ListThirdPartyApis))
			mux.Handle("GET /api/admin/third-party-apis/{name}", adminAuth(adminTradingH.GetThirdPartyApi))
			mux.Handle("PUT /api/admin/third-party-apis/{name}", adminAuth(adminTradingH.UpdateThirdPartyApi))
			mux.Handle("POST /api/admin/third-party-apis/{name}/toggle", adminAuth(adminTradingH.ToggleThirdPartyApi))
			mux.Handle("POST /api/admin/third-party-apis/{name}/verify", adminAuth(adminTradingH.VerifyThirdPartyApi))
			mux.Handle("GET /api/admin/third-party-apis/{name}/history", adminAuth(adminTradingH.ApiKeyHistory))

			// Trading & wallet overview
			mux.Handle("GET /api/admin/trading-stats", adminAuth(adminTradingH.TradingStats))
			mux.Handle("GET /api/admin/orders", adminAuth(adminTradingH.ListAllOrders))
			mux.Handle("GET /api/admin/wallets", adminAuth(adminTradingH.ListWallets))
			mux.Handle("GET /api/admin/wallet-transactions", adminAuth(adminTradingH.ListAllTransactions))
			mux.Handle("GET /api/admin/asset-withdrawals", adminAuth(adminTradingH.ListAssetWithdrawals))
			mux.Handle("POST /api/admin/asset-withdrawals/{id}/approve", adminAuth(adminTradingH.ApproveAssetWithdrawal))
			mux.Handle("POST /api/admin/asset-withdrawals/{id}/reject", adminAuth(adminTradingH.RejectAssetWithdrawal))

			log.Println("[OK] Admin trading & financial routes registered")
		}
	}

	// ── Middleware stack ──
	// CORS wraps only non-WebSocket routes (rs/cors wraps ResponseWriter,
	// breaking http.Hijacker which gorilla/websocket needs).
	corsHandler := mw.NewCORS(cfg.CORSOrigins)
	corsWrapped := corsHandler(mux)
	var finalHandler http.Handler = http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/ws/") {
			mux.ServeHTTP(w, r)
		} else {
			corsWrapped.ServeHTTP(w, r)
		}
	})
	finalHandler = mw.Logging(finalHandler)

	// ── Server ──
	srv := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      finalHandler,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// ── Graceful shutdown ──
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		log.Println("Shutting down...")

		if commissionScheduler != nil {
			commissionScheduler.Stop()
		}
		if chatRedisCancel != nil {
			chatRedisCancel()
		}
		if rdb != nil {
			if err := rdb.Close(); err != nil {
				log.Printf("Redis close: %v", err)
			}
		}

		shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer shutdownCancel()

		if err := srv.Shutdown(shutdownCtx); err != nil {
			log.Printf("Shutdown error: %v", err)
		}
		if dbCloser != nil {
			dbCloser()
		}
		binance.Stop()
		if polygonWS != nil {
			polygonWS.Stop()
		}
		if forexWS != nil {
			forexWS.Stop()
		}
		marketHub.Stop()
	}()

	log.Printf("tongxin-go server starting on :%s", cfg.Port)
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
	log.Println("Server stopped")
}
