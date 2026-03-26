package bootstrap

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"rogue-dungeon-backend/internal/modules/audit"
	"rogue-dungeon-backend/internal/modules/auth"
	"rogue-dungeon-backend/internal/modules/commerce"
	"rogue-dungeon-backend/internal/modules/inventory"
	"rogue-dungeon-backend/internal/modules/player"
	"rogue-dungeon-backend/internal/modules/risk"
	"rogue-dungeon-backend/internal/modules/run"
	appjwt "rogue-dungeon-backend/internal/platform/jwt"
)

func NewRouter(runService run.Service, runRepo run.Repository, rewardJobStore run.RewardJobStore, rewardApplier run.RewardApplier, authService auth.Service, riskService risk.Service, auditService audit.Service, commerceService commerce.Service, playerService player.Service, inventoryService inventory.Service, tokenManager *appjwt.TokenManager, adminToken string) *gin.Engine {
	router := gin.New()
	router.Use(gin.Recovery())
	router.Use(RequestIDMiddleware())

	router.GET("/healthz", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	authHandler := auth.NewHandler(authService)
	auditHandler := audit.NewHandler(auditService)
	riskHandler := risk.NewHandler(riskService, auditService)
	commerceHandler := commerce.NewHandler(commerceService)
	runHandler := run.NewHandler(runService)
	rewardJobHandler := run.NewRewardJobAdminHandler(rewardJobStore, runRepo, rewardApplier, auditService)
	playerHandler := player.NewHandler(playerService)
	inventoryHandler := inventory.NewHandler(inventoryService)

	v1 := router.Group("/v1")
	{
		v1.POST("/auth/steam/login", authHandler.SteamLogin)
		v1.POST("/auth/refresh", authHandler.Refresh)
		v1.GET("/store/catalog", commerceHandler.GetCatalog)

		protected := v1.Group("")
		protected.Use(AuthMiddleware(tokenManager))
		protected.POST("/entitlements/sync", commerceHandler.SyncEntitlements)
		protected.GET("/me/profile", playerHandler.GetProfile)
		protected.PATCH("/me/loadout", playerHandler.UpdateLoadout)
		protected.GET("/me/inventory", inventoryHandler.GetInventory)
		protected.GET("/me/runs", runHandler.ListRuns)
		protected.GET("/me/runs/:runId/detail", runHandler.GetRunDetail)
		protected.GET("/me/runs/:runId/reasons", runHandler.GetRunReasons)
		protected.POST("/runs/start", runHandler.StartRun)
		protected.POST("/runs/:runId/abort", runHandler.AbortRun)
		protected.POST("/runs/:runId/heartbeat", runHandler.Heartbeat)
		protected.POST("/runs/:runId/host-migration/claim", runHandler.HostMigrationClaim)
		protected.POST("/runs/:runId/host-migration/confirm", runHandler.HostMigrationConfirm)
		protected.POST("/runs/:runId/reconnect/request", runHandler.ReconnectRequest)
		protected.POST("/runs/:runId/reconnect/confirm", runHandler.ReconnectConfirm)
		protected.GET("/runs/:runId/session-state", runHandler.GetSessionState)
		protected.GET("/runs/:runId", runHandler.GetRun)
		protected.POST("/runs/:runId/finish", runHandler.FinishRun)

		admin := v1.Group("/admin")
		admin.Use(AdminAuthMiddleware(adminToken))
		admin.GET("/risk-flags", riskHandler.ListFlags)
		admin.POST("/risk-flags/:id/action", riskHandler.ApplyAction)
		admin.GET("/reward-jobs", rewardJobHandler.List)
		admin.GET("/reward-jobs/stats", rewardJobHandler.Stats)
		admin.GET("/reward-jobs/timezones", rewardJobHandler.Timezones)
		admin.GET("/reward-jobs/:id", rewardJobHandler.Get)
		admin.POST("/reward-jobs/:id/retry", rewardJobHandler.Retry)
		admin.POST("/reward-jobs/:id/approve", rewardJobHandler.Approve)
		admin.POST("/reward-jobs/:id/deny", rewardJobHandler.Deny)
		admin.GET("/audit-logs", auditHandler.ListLogs)
	}

	return router
}
