package bootstrap

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"

	"rogue-dungeon-backend/internal/modules/auth"
	"rogue-dungeon-backend/internal/modules/inventory"
	"rogue-dungeon-backend/internal/modules/run"
)

type rewardApplierAdapter struct {
	authRepo      auth.Repository
	inventoryRepo inventory.Repository
}

func NewRewardApplierAdapter(authRepo auth.Repository, inventoryRepo inventory.Repository) run.RewardApplier {
	return &rewardApplierAdapter{
		authRepo:      authRepo,
		inventoryRepo: inventoryRepo,
	}
}

func (a *rewardApplierAdapter) ApplyRewards(ctx context.Context, steamID string, runID uuid.UUID, rewards []run.RewardDraft, at time.Time) error {
	grants := make([]inventory.RewardGrant, 0, len(rewards))
	for _, reward := range rewards {
		if reward.Amount <= 0 {
			continue
		}
		grants = append(grants, inventory.RewardGrant{
			Type:   reward.Type,
			ID:     reward.ID,
			Amount: reward.Amount,
		})
	}
	if len(grants) == 0 {
		return nil
	}

	user, err := a.authRepo.GetBySteamID(ctx, steamID)
	if err != nil {
		if errors.Is(err, auth.ErrUserNotFound) {
			user, err = a.authRepo.Create(ctx, steamID)
			if err != nil {
				return err
			}
		} else {
			return err
		}
	}

	_, err = a.inventoryRepo.ApplyRewardsForRun(ctx, user.UserID, runID, grants, at)
	return err
}
