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
	"tongxin-go/internal/config"
	"tongxin-go/internal/handler"
	"tongxin-go/internal/market"
	mw "tongxin-go/internal/middleware"
	"tongxin-go/internal/repository"
	"tongxin-go/internal/service"
	"tongxin-go/internal/ws"
)

func main() {
	cfg := config.Load()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// ── Database ──
	var userRepo *repository.UserRepo
	var friendRepo *repository.FriendRepo
	var convRepo *repository.ConversationRepo
	var msgRepo *repository.MessageRepo
	var teacherRepo *repository.TeacherRepo
	var watchlistRepo *repository.WatchlistRepo

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
			teacherRepo = repository.NewTeacherRepo(pool)
			watchlistRepo = repository.NewWatchlistRepo(pool)
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

	if userRepo != nil {
		userSvc = service.NewUserService(userRepo)
	}
	if friendRepo != nil {
		friendSvc = service.NewFriendService(friendRepo)
	}
	if msgRepo != nil && convRepo != nil {
		msgSvc = service.NewMessageService(msgRepo, convRepo)
	}
	if teacherRepo != nil {
		teacherSvc = service.NewTeacherService(teacherRepo)
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

	// ── Polygon WebSocket (real-time stock/forex) ──
	var polygonWS *market.PolygonWS
	if cfg.PolygonAPIKey != "" {
		polygonWS = market.NewPolygonWS(cfg.PolygonAPIKey)
		polygonWS.Start()
		log.Println("[OK] Polygon WebSocket started (stocks + forex)")
	}

	// ── WebSocket Hubs ──
	var chatHub *ws.ChatHub
	if msgSvc != nil && userSvc != nil {
		chatHub = ws.NewChatHub(msgSvc, userSvc)
		log.Println("[OK] Chat WebSocket hub initialized")
	}

	marketHub := ws.NewMarketHub(polygonClient, polygonWS, binance)
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

		// Crypto routes
		mux.HandleFunc("GET /api/crypto/quotes", marketH.CryptoQuotes)
		mux.HandleFunc("GET /api/crypto/pairs", marketH.CryptoPairs)
		mux.HandleFunc("GET /api/crypto/depth", marketH.CryptoDepth)

		// Forex routes
		mux.HandleFunc("GET /api/forex/pairs", marketH.ForexPairs)
		mux.HandleFunc("GET /api/forex/quotes", marketH.ForexQuotes)

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
		mux.Handle("GET /api/auth/profile/{id}", authMw.Authenticate(http.HandlerFunc(authH.GetProfileByID)))

		mux.Handle("GET /api/users/batch-profiles", authMw.Authenticate(http.HandlerFunc(usersH.BatchProfiles)))
		mux.Handle("GET /api/user-profiles/batch", authMw.Authenticate(http.HandlerFunc(usersH.BatchProfiles)))
		mux.Handle("GET /api/users", authMw.Authenticate(http.HandlerFunc(usersH.ListUsers)))

		log.Println("[OK] Auth + User routes registered")
	}

	// Friends
	if friendSvc != nil && userSvc != nil {
		friendsH := handler.NewFriendsHandler(friendSvc)
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
		msgsH := handler.NewMessagesHandler(msgSvc)
		mux.Handle("GET /api/conversations", authMw.Authenticate(http.HandlerFunc(convH.List)))
		mux.Handle("GET /api/conversations/unread-count", authMw.Authenticate(http.HandlerFunc(convH.UnreadCount)))
		mux.Handle("GET /api/conversations/{id}", authMw.Authenticate(http.HandlerFunc(convH.GetByID)))
		mux.Handle("POST /api/conversations/direct", authMw.Authenticate(http.HandlerFunc(convH.CreateDirect)))
		mux.Handle("POST /api/conversations/group", authMw.Authenticate(http.HandlerFunc(convH.CreateGroup)))
		mux.Handle("PATCH /api/conversations/{id}/read", authMw.Authenticate(http.HandlerFunc(convH.MarkAsRead)))
		mux.Handle("GET /api/conversations/{id}/group-info", authMw.Authenticate(http.HandlerFunc(convH.GroupInfo)))
		mux.Handle("GET /api/conversations/{id}/messages", authMw.Authenticate(http.HandlerFunc(msgsH.ListByConversation)))
		mux.Handle("POST /api/messages", authMw.Authenticate(http.HandlerFunc(msgsH.Send)))
		mux.Handle("DELETE /api/messages/{id}", authMw.Authenticate(http.HandlerFunc(msgsH.Delete)))
		log.Println("[OK] Conversations + Messages routes registered")
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
	if pool != nil {
		walletRepo := repository.NewWalletRepo(pool)
		orderRepo := repository.NewOrderRepo(pool)
		positionRepo := repository.NewPositionRepo(pool)

		tradingHub = ws.NewTradingHub()

		tradingSvc := service.NewTradingService(walletRepo, orderRepo, positionRepo, binance, polygonClient, tradingHub)

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

		// Wallet routes
		mux.Handle("POST /api/wallet/deposit", authMw.Authenticate(http.HandlerFunc(walletH.Deposit)))
		mux.Handle("GET /api/wallet", authMw.Authenticate(http.HandlerFunc(walletH.GetBalance)))
		mux.Handle("GET /api/wallet/transactions", authMw.Authenticate(http.HandlerFunc(walletH.GetTransactions)))

		log.Println("[OK] Native trading + wallet routes registered")
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

	// Admin
	if userSvc != nil && teacherSvc != nil {
		adminH := handler.NewAdminHandler(userSvc, teacherSvc)
		mux.Handle("GET /api/admin/users", authMw.Authenticate(http.HandlerFunc(adminH.ListUsers)))
		mux.Handle("GET /api/admin/teachers/pending", authMw.Authenticate(http.HandlerFunc(adminH.PendingTeachers)))
		mux.Handle("POST /api/admin/teachers/{id}/approve", authMw.Authenticate(http.HandlerFunc(adminH.ApproveTeacher)))
		mux.Handle("POST /api/admin/teachers/{id}/reject", authMw.Authenticate(http.HandlerFunc(adminH.RejectTeacher)))
		mux.Handle("GET /api/admin/stats", authMw.Authenticate(http.HandlerFunc(adminH.Stats)))
		mux.Handle("POST /api/admin/announcements", authMw.Authenticate(http.HandlerFunc(adminH.CreateAnnouncement)))
		mux.Handle("GET /api/admin/reports", authMw.Authenticate(http.HandlerFunc(adminH.ListReports)))
		mux.HandleFunc("GET /api/announcements", adminH.ListAnnouncements)
		log.Println("[OK] Admin routes registered")
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
		marketHub.Stop()
	}()

	log.Printf("tongxin-go server starting on :%s", cfg.Port)
	if err := srv.ListenAndServe(); err != http.ErrServerClosed {
		log.Fatalf("Server error: %v", err)
	}
	log.Println("Server stopped")
}
