package main

import (
	"context"
	"log"
	"os"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"rogue-dungeon-backend/internal/bootstrap"
	"rogue-dungeon-backend/internal/modules/auth"
	"rogue-dungeon-backend/internal/modules/inventory"
	"rogue-dungeon-backend/internal/modules/risk"
	"rogue-dungeon-backend/internal/modules/run"
	platformdb "rogue-dungeon-backend/internal/platform/db"
	platformmigrate "rogue-dungeon-backend/internal/platform/migrate"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	var (
		authRepo       auth.Repository
		inventoryRepo  inventory.Repository
		riskRepo       risk.Repository
		runRepo        run.Repository
		rewardJobStore run.RewardJobStore
		cleanup        = func() {}
	)

	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL != "" {
		pool, err := platformdb.NewPostgresPool(ctx, databaseURL)
		if err != nil {
			log.Fatalf("connect postgres failed: %v", err)
		}

		autoMigrate := strings.ToLower(strings.TrimSpace(os.Getenv("AUTO_MIGRATE")))
		if autoMigrate != "false" && autoMigrate != "0" {
			runner := platformmigrate.NewRunner(pool, "")
			if err := runner.Run(ctx); err != nil {
				pool.Close()
				log.Fatalf("run migration failed: %v", err)
			}
		}

		authRepo = auth.NewPostgresRepository(pool)
		inventoryRepo = inventory.NewPostgresRepository(pool)
		riskRepo = risk.NewPostgresRepository(pool)
		runRepo = run.NewPostgresRepository(pool)
		rewardJobStore = run.NewPostgresRewardJobStore(pool)
		cleanup = pool.Close
	} else {
		// Development fallback: queue is in-memory only.
		authRepo = auth.NewMemoryRepository()
		inventoryRepo = inventory.NewMemoryRepository()
		riskRepo = risk.NewMemoryRepository()
		runRepo = run.NewMemoryRepository()
		rewardJobStore = run.NewMemoryRewardJobStore()
	}
	defer cleanup()

	applier := bootstrap.NewRewardApplierAdapter(authRepo, inventoryRepo)
	riskService := risk.NewService(riskRepo)
	riskReporter := risk.NewReporter(riskService)

	interval := parseDurationEnv("REWARD_WORKER_INTERVAL", 5*time.Second)
	batchSize := parseIntEnv("REWARD_WORKER_BATCH", 20)
	if batchSize <= 0 {
		batchSize = 20
	}
	maxAttempts := parseIntEnv("REWARD_WORKER_MAX_ATTEMPTS", 6)
	baseDelay := parseDurationEnv("REWARD_WORKER_BASE_DELAY", 15*time.Second)
	maxDelay := parseDurationEnv("REWARD_WORKER_MAX_DELAY", 15*time.Minute)
	sessionSweepInterval := parseDurationEnv("RUN_SESSION_SWEEP_INTERVAL", 10*time.Second)
	hostMigrationWindow := parseDurationEnv("RUN_HOST_MIGRATION_WINDOW", 90*time.Second)

	rewardTicker := time.NewTicker(interval)
	defer rewardTicker.Stop()
	sweepTicker := time.NewTicker(sessionSweepInterval)
	defer sweepTicker.Stop()

	processor := run.NewRewardJobProcessorWithConfig(rewardJobStore, applier, runRepo, run.RewardJobProcessorConfig{
		MaxAttempts: maxAttempts,
		BaseDelay:   baseDelay,
		MaxDelay:    maxDelay,
	})

	log.Printf("reward worker started (rewardInterval=%s, batch=%d, sessionSweepInterval=%s, hostMigrationWindow=%s)", interval, batchSize, sessionSweepInterval, hostMigrationWindow)

	for {
		select {
		case <-ctx.Done():
			log.Println("reward worker stopped")
			return
		case <-rewardTicker.C:
			summary, err := processor.ProcessDue(ctx, batchSize)
			if err != nil {
				log.Printf("process reward jobs failed: %v", err)
				continue
			}
			if summary.Claimed > 0 {
				log.Printf("processed reward jobs: claimed=%d completed=%d retried=%d failed=%d",
					summary.Claimed, summary.Completed, summary.Retried, summary.Failed)
			}
		case <-sweepTicker.C:
			changedRuns, err := runRepo.AbortExpiredRuns(ctx, time.Now().UTC(), hostMigrationWindow)
			if err != nil {
				log.Printf("sweep expired runs failed: %v", err)
				continue
			}
			for _, changedRun := range changedRuns {
				score := 55
				stage := "worker_sweep_promote_migration_wait"
				if changedRun.Status == run.RunStatusAborted {
					score = 70
					stage = "worker_sweep_abort_after_migration_wait"
				}
				if err := riskReporter.Report(ctx, run.RiskReport{
					UserID:    changedRun.HostUserID,
					RunID:     changedRun.RunID,
					RiskScore: score,
					Reasons:   []string{run.RiskReasonHostReconnectTimeout},
					Source:    "run_reconnect",
					Evidence: map[string]any{
						"stage":                   stage,
						"expiredAt":               changedRun.HostReconnectDeadlineAt,
						"hostMigrationDeadlineAt": changedRun.HostMigrationDeadlineAt,
					},
				}); err != nil {
					log.Printf("report reconnect timeout risk failed: runId=%s err=%v", changedRun.RunID.String(), err)
				}
			}
			if len(changedRuns) > 0 {
				log.Printf("swept expired runs: changed=%d", len(changedRuns))
			}
		}
	}
}

func parseIntEnv(key string, def int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return def
	}
	value, err := strconv.Atoi(raw)
	if err != nil {
		return def
	}
	return value
}

func parseDurationEnv(key string, def time.Duration) time.Duration {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return def
	}
	value, err := time.ParseDuration(raw)
	if err != nil {
		return def
	}
	return value
}
