package inventory

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/google/uuid"
)

type Repository interface {
	GetOrCreate(ctx context.Context, actor UserRef) (InventoryRecord, error)
	ApplyRewardsForRun(ctx context.Context, userID int64, runID uuid.UUID, grants []RewardGrant, at time.Time) (bool, error)
}

type MemoryRepository struct {
	mu      sync.RWMutex
	records map[int64]InventoryRecord
	grants  map[string]time.Time
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		records: make(map[int64]InventoryRecord),
		grants:  make(map[string]time.Time),
	}
}

func (r *MemoryRepository) GetOrCreate(_ context.Context, actor UserRef) (InventoryRecord, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if record, ok := r.records[actor.UserID]; ok {
		return cloneInventoryRecord(record), nil
	}

	record := InventoryRecord{
		UserID:       actor.UserID,
		SteamID:      actor.SteamID,
		SoftCurrency: 0,
		HardCurrency: 0,
		Items:        []Item{},
		Cosmetics:    []string{},
		UpdatedAt:    time.Now().UTC(),
	}
	r.records[actor.UserID] = record
	return cloneInventoryRecord(record), nil
}

func (r *MemoryRepository) ApplyRewardsForRun(_ context.Context, userID int64, runID uuid.UUID, grants []RewardGrant, at time.Time) (bool, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	key := fmt.Sprintf("%d:%s", userID, runID.String())
	if _, exists := r.grants[key]; exists {
		return false, nil
	}

	record, ok := r.records[userID]
	if !ok {
		record = InventoryRecord{
			UserID:       userID,
			SoftCurrency: 0,
			HardCurrency: 0,
			Items:        []Item{},
			Cosmetics:    []string{},
		}
	}

	for _, grant := range grants {
		if grant.Amount <= 0 {
			continue
		}

		switch grant.Type {
		case "soft_currency":
			record.SoftCurrency += grant.Amount
		case "hard_currency":
			record.HardCurrency += grant.Amount
		case "item":
			found := false
			for idx := range record.Items {
				if record.Items[idx].ID == grant.ID {
					record.Items[idx].Amount += grant.Amount
					found = true
					break
				}
			}
			if !found {
				record.Items = append(record.Items, Item{
					ID:     grant.ID,
					Amount: grant.Amount,
				})
			}
		case "cosmetic":
			alreadyOwned := false
			for _, cosmeticID := range record.Cosmetics {
				if cosmeticID == grant.ID {
					alreadyOwned = true
					break
				}
			}
			if !alreadyOwned {
				record.Cosmetics = append(record.Cosmetics, grant.ID)
			}
		}
	}

	record.UpdatedAt = at
	r.records[userID] = record
	r.grants[key] = at
	return true, nil
}

func cloneInventoryRecord(record InventoryRecord) InventoryRecord {
	items := make([]Item, 0, len(record.Items))
	for _, item := range record.Items {
		items = append(items, Item{ID: item.ID, Amount: item.Amount})
	}
	cosmetics := append([]string(nil), record.Cosmetics...)
	return InventoryRecord{
		UserID:       record.UserID,
		SteamID:      record.SteamID,
		SoftCurrency: record.SoftCurrency,
		HardCurrency: record.HardCurrency,
		Items:        items,
		Cosmetics:    cosmetics,
		UpdatedAt:    record.UpdatedAt,
	}
}
