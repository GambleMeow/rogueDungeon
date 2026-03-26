package run

import (
	"context"
	"time"

	"github.com/google/uuid"
)

type RewardApplier interface {
	ApplyRewards(ctx context.Context, steamID string, runID uuid.UUID, rewards []RewardDraft, at time.Time) error
}

type NoopRewardService struct{}

func NewNoopRewardService() *NoopRewardService {
	return &NoopRewardService{}
}

func (s *NoopRewardService) GrantNow(_ context.Context, _ UserRef, _ uuid.UUID, _ FinishRunInput) error {
	return nil
}

func (s *NoopRewardService) EnqueueRetry(_ context.Context, _ UserRef, _ uuid.UUID, _ FinishRunInput) error {
	return nil
}

func (s *NoopRewardService) EnqueueReview(_ context.Context, _ UserRef, _ uuid.UUID, _ FinishRunInput) error {
	return nil
}

type InventoryRewardService struct {
	applier RewardApplier
	jobs    RewardJobStore
}

func NewInventoryRewardService(applier RewardApplier, jobs RewardJobStore) *InventoryRewardService {
	return &InventoryRewardService{
		applier: applier,
		jobs:    jobs,
	}
}

func (s *InventoryRewardService) GrantNow(ctx context.Context, _ UserRef, runID uuid.UUID, req FinishRunInput) error {
	if s.applier == nil {
		return nil
	}

	for _, member := range req.Members {
		rewards := member.RewardDraft
		if member.SteamID == "" || len(rewards) == 0 {
			continue
		}

		if err := s.applier.ApplyRewards(ctx, member.SteamID, runID, rewards, time.Now().UTC()); err != nil {
			return err
		}
	}

	return nil
}

func (s *InventoryRewardService) EnqueueRetry(ctx context.Context, _ UserRef, runID uuid.UUID, req FinishRunInput) error {
	if s.jobs == nil {
		return nil
	}
	return s.jobs.EnqueueDelayed(ctx, runID, req.Members, time.Now().UTC(), false)
}

func (s *InventoryRewardService) EnqueueReview(ctx context.Context, _ UserRef, runID uuid.UUID, req FinishRunInput) error {
	if s.jobs == nil {
		return nil
	}
	return s.jobs.EnqueueDelayed(ctx, runID, req.Members, time.Now().UTC(), true)
}

type NoopRiskReporter struct{}

func NewNoopRiskReporter() *NoopRiskReporter {
	return &NoopRiskReporter{}
}

func (r *NoopRiskReporter) Report(_ context.Context, _ RiskReport) error {
	return nil
}
