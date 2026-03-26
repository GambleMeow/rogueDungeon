package run

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
)

type RewardJobProcessor struct {
	store       RewardJobStore
	applier     RewardApplier
	repo        Repository
	maxAttempts int
	baseDelay   time.Duration
	maxDelay    time.Duration
}

type RewardJobProcessorConfig struct {
	MaxAttempts int
	BaseDelay   time.Duration
	MaxDelay    time.Duration
}

type RewardJobProcessSummary struct {
	Claimed   int `json:"claimed"`
	Completed int `json:"completed"`
	Retried   int `json:"retried"`
	Failed    int `json:"failed"`
}

func NewRewardJobProcessor(store RewardJobStore, applier RewardApplier, repo Repository) *RewardJobProcessor {
	return NewRewardJobProcessorWithConfig(store, applier, repo, RewardJobProcessorConfig{})
}

func NewRewardJobProcessorWithConfig(store RewardJobStore, applier RewardApplier, repo Repository, cfg RewardJobProcessorConfig) *RewardJobProcessor {
	maxAttempts := cfg.MaxAttempts
	if maxAttempts <= 0 {
		maxAttempts = 6
	}
	baseDelay := cfg.BaseDelay
	if baseDelay <= 0 {
		baseDelay = 15 * time.Second
	}
	maxDelay := cfg.MaxDelay
	if maxDelay <= 0 {
		maxDelay = 15 * time.Minute
	}
	if maxDelay < baseDelay {
		maxDelay = baseDelay
	}

	return &RewardJobProcessor{
		store:       store,
		applier:     applier,
		repo:        repo,
		maxAttempts: maxAttempts,
		baseDelay:   baseDelay,
		maxDelay:    maxDelay,
	}
}

func (p *RewardJobProcessor) ProcessDue(ctx context.Context, limit int) (RewardJobProcessSummary, error) {
	if p == nil || p.store == nil || p.applier == nil {
		return RewardJobProcessSummary{}, nil
	}

	if limit <= 0 {
		limit = 20
	}

	now := time.Now().UTC()
	jobs, err := p.store.ClaimDue(ctx, limit, now)
	if err != nil {
		return RewardJobProcessSummary{}, err
	}

	summary := RewardJobProcessSummary{Claimed: len(jobs)}
	for _, job := range jobs {
		runID, err := uuid.Parse(job.RunID)
		if err != nil {
			if markErr := p.store.MarkFailed(ctx, job.ID, err.Error(), time.Now().UTC()); markErr != nil {
				return summary, markErr
			}
			summary.Failed++
			continue
		}

		if err := p.applyJob(ctx, runID, job); err != nil {
			attempt := job.Attempts + 1
			if attempt >= p.maxAttempts {
				if markErr := p.store.MarkFailed(ctx, job.ID, err.Error(), time.Now().UTC()); markErr != nil {
					return summary, markErr
				}
				if err := p.syncRunRewardStatus(ctx, runID, RewardStatusDenied); err != nil {
					return summary, err
				}
				summary.Failed++
				continue
			}

			next := time.Now().UTC().Add(p.retryDelay(attempt))
			if markErr := p.store.MarkRetry(ctx, job.ID, next, err.Error(), time.Now().UTC()); markErr != nil {
				return summary, markErr
			}
			summary.Retried++
			continue
		}

		if err := p.store.MarkCompleted(ctx, job.ID, time.Now().UTC()); err != nil {
			return summary, err
		}
		if err := p.syncRunRewardStatus(ctx, runID, RewardStatusGranted); err != nil {
			return summary, err
		}
		summary.Completed++
	}

	return summary, nil
}

func (p *RewardJobProcessor) applyJob(ctx context.Context, runID uuid.UUID, job RewardJob) error {
	for _, member := range job.Members {
		if member.SteamID == "" || len(member.Rewards) == 0 {
			continue
		}
		if err := p.applier.ApplyRewards(ctx, member.SteamID, runID, member.Rewards, time.Now().UTC()); err != nil {
			return fmt.Errorf("apply rewards for steamId=%s failed: %w", member.SteamID, err)
		}
	}

	return nil
}

func (p *RewardJobProcessor) syncRunRewardStatus(ctx context.Context, runID uuid.UUID, rewardStatus string) error {
	if p.repo == nil {
		return nil
	}
	if err := p.repo.UpdateRunRewardStatus(ctx, runID, rewardStatus, time.Now().UTC()); err != nil && !errors.Is(err, errRecordNotFound) {
		return err
	}
	return nil
}

func (p *RewardJobProcessor) retryDelay(attempt int) time.Duration {
	if attempt < 1 {
		attempt = 1
	}
	delay := p.baseDelay
	for i := 1; i < attempt; i++ {
		delay *= 2
		if delay >= p.maxDelay {
			return p.maxDelay
		}
	}
	if delay < p.baseDelay {
		return p.baseDelay
	}
	if delay > p.maxDelay {
		return p.maxDelay
	}
	return delay
}

func (p *RewardJobProcessor) RetryNow(ctx context.Context, id int64) (RewardJob, error) {
	if p == nil || p.store == nil {
		return RewardJob{}, errors.New("reward processor unavailable")
	}
	return p.store.RetryNow(ctx, id, time.Now().UTC())
}
