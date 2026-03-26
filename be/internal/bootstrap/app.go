package bootstrap

import (
	"context"
	"net/http"
	"os"
	"strings"
	"time"

	"rogue-dungeon-backend/internal/modules/audit"
	"rogue-dungeon-backend/internal/modules/auth"
	"rogue-dungeon-backend/internal/modules/commerce"
	"rogue-dungeon-backend/internal/modules/inventory"
	"rogue-dungeon-backend/internal/modules/player"
	"rogue-dungeon-backend/internal/modules/risk"
	"rogue-dungeon-backend/internal/modules/run"
	platformdb "rogue-dungeon-backend/internal/platform/db"
	appjwt "rogue-dungeon-backend/internal/platform/jwt"
	platformmigrate "rogue-dungeon-backend/internal/platform/migrate"
)

type App struct {
	server  *http.Server
	cleanup func()
}

func NewApp() (*App, error) {
	var (
		runRepo        run.Repository
		rewardJobStore run.RewardJobStore
		idemStore      run.IdempotencyStore
		authRepo       auth.Repository
		auditRepo      audit.Repository
		commerceRepo   commerce.Repository
		playerRepo     player.Repository
		inventoryRepo  inventory.Repository
		riskRepo       risk.Repository
		cleanup        = func() {}
	)

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL != "" {
		pool, err := platformdb.NewPostgresPool(context.Background(), databaseURL)
		if err != nil {
			return nil, err
		}

		autoMigrate := strings.ToLower(strings.TrimSpace(os.Getenv("AUTO_MIGRATE")))
		if autoMigrate != "false" && autoMigrate != "0" {
			runner := platformmigrate.NewRunner(pool, "")
			if err := runner.Run(context.Background()); err != nil {
				pool.Close()
				return nil, err
			}
		}

		runRepo = run.NewPostgresRepository(pool)
		rewardJobStore = run.NewPostgresRewardJobStore(pool)
		idemStore = run.NewPostgresIdempotencyStore(pool, 24*time.Hour)
		authRepo = auth.NewPostgresRepository(pool)
		auditRepo = audit.NewPostgresRepository(pool)
		commerceRepo = commerce.NewPostgresRepository(pool)
		playerRepo = player.NewPostgresRepository(pool)
		inventoryRepo = inventory.NewPostgresRepository(pool)
		riskRepo = risk.NewPostgresRepository(pool)
		cleanup = pool.Close
	} else {
		runRepo = run.NewMemoryRepository()
		rewardJobStore = run.NewMemoryRewardJobStore()
		idemStore = run.NewMemoryIdempotencyStore()
		authRepo = auth.NewMemoryRepository()
		auditRepo = audit.NewMemoryRepository()
		commerceRepo = commerce.NewMemoryRepository()
		playerRepo = player.NewMemoryRepository()
		inventoryRepo = inventory.NewMemoryRepository()
		riskRepo = risk.NewMemoryRepository()
	}

	riskEngine := run.NewBasicRiskEngine()
	rewardApplier := NewRewardApplierAdapter(authRepo, inventoryRepo)
	rewardService := run.NewInventoryRewardService(rewardApplier, rewardJobStore)
	riskService := risk.NewService(riskRepo)
	riskReporter := risk.NewReporter(riskService)
	runService := run.NewServiceWithConfig(runRepo, idemStore, riskEngine, rewardService, riskReporter, run.ServiceConfig{
		HostReconnectWindow:   durationFromEnv("RUN_HOST_RECONNECT_WINDOW", 3*time.Minute),
		PlayerReconnectWindow: durationFromEnv("RUN_PLAYER_RECONNECT_WINDOW", 3*time.Minute),
		HostMigrationWindow:   durationFromEnv("RUN_HOST_MIGRATION_WINDOW", 90*time.Second),
		ReconnectTokenTTL:     durationFromEnv("RUN_RECONNECT_TOKEN_TTL", 60*time.Second),
	})

	secret := os.Getenv("APP_JWT_SECRET")
	if secret == "" {
		secret = "dev-secret-change-this"
	}
	tokenManager := appjwt.NewTokenManager(appjwt.Config{
		Issuer:     "rogue-dungeon-backend",
		Secret:     secret,
		AccessTTL:  15 * time.Minute,
		RefreshTTL: 7 * 24 * time.Hour,
	})

	var steamVerifier auth.SteamVerifier = auth.NewLocalSteamVerifier()

	steamAPIKey := os.Getenv("STEAM_WEB_API_KEY")
	steamAppID := os.Getenv("STEAM_APP_ID")
	steamEndpoint := os.Getenv("STEAM_API_ENDPOINT")
	if steamAPIKey != "" && steamAppID != "" {
		steamVerifier = auth.NewSteamWebVerifier(steamAPIKey, steamAppID, steamEndpoint, 5*time.Second)
	}
	authService := auth.NewService(authRepo, steamVerifier, tokenManager)
	auditService := audit.NewService(auditRepo)
	commerceService := commerce.NewService(commerceRepo)
	playerService := player.NewService(playerRepo)
	inventoryService := inventory.NewService(inventoryRepo)
	adminToken := os.Getenv("ADMIN_API_TOKEN")

	router := NewRouter(runService, runRepo, rewardJobStore, rewardApplier, authService, riskService, auditService, commerceService, playerService, inventoryService, tokenManager, adminToken)

	server := &http.Server{
		Addr:              ":8080",
		Handler:           router,
		ReadHeaderTimeout: 5 * time.Second,
	}

	return &App{
		server:  server,
		cleanup: cleanup,
	}, nil
}

func (a *App) Run() error {
	err := a.server.ListenAndServe()
	if a.cleanup != nil {
		a.cleanup()
	}
	return err
}

func durationFromEnv(key string, fallback time.Duration) time.Duration {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(raw)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}
