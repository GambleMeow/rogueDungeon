package commerce

import (
	"context"
	"sort"
	"sync"
	"time"
)

type Repository interface {
	GetCatalog(ctx context.Context) ([]CatalogItem, error)
	ReplaceEntitlements(ctx context.Context, userID int64, dlcIDs []int, syncedAt time.Time) error
	GetOwnedEntitlements(ctx context.Context, userID int64) ([]int, error)
}

type MemoryRepository struct {
	mu           sync.RWMutex
	catalog      []CatalogItem
	entitlements map[int64]map[int]bool
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		catalog: []CatalogItem{
			{ID: "skin_knight_01", Type: "cosmetic", Price: 1200, Currency: "CNY"},
			{ID: "skin_mage_01", Type: "cosmetic", Price: 1200, Currency: "CNY"},
			{ID: "dlc_pack_01", Type: "dlc", Price: 2800, Currency: "CNY"},
		},
		entitlements: make(map[int64]map[int]bool),
	}
}

func (r *MemoryRepository) GetCatalog(_ context.Context) ([]CatalogItem, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	items := make([]CatalogItem, 0, len(r.catalog))
	for _, item := range r.catalog {
		items = append(items, item)
	}
	return items, nil
}

func (r *MemoryRepository) ReplaceEntitlements(_ context.Context, userID int64, dlcIDs []int, _ time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	set := make(map[int]bool, len(dlcIDs))
	for _, dlcID := range dlcIDs {
		set[dlcID] = true
	}
	r.entitlements[userID] = set
	return nil
}

func (r *MemoryRepository) GetOwnedEntitlements(_ context.Context, userID int64) ([]int, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	set, ok := r.entitlements[userID]
	if !ok {
		return []int{}, nil
	}

	result := make([]int, 0, len(set))
	for dlcID, owned := range set {
		if owned {
			result = append(result, dlcID)
		}
	}
	sort.Ints(result)
	return result, nil
}
