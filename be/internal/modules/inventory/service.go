package inventory

import (
	"context"
	"errors"
	"strings"
)

var (
	ErrUnauthorized = errors.New("UNAUTHORIZED")
	ErrInternal     = errors.New("INTERNAL_ERROR")
)

type Service interface {
	GetInventory(ctx context.Context, actor UserRef) (InventoryOutput, error)
}

type service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return &service{repo: repo}
}

func (s *service) GetInventory(ctx context.Context, actor UserRef) (InventoryOutput, error) {
	if actor.UserID <= 0 || strings.TrimSpace(actor.SteamID) == "" {
		return InventoryOutput{}, ErrUnauthorized
	}

	record, err := s.repo.GetOrCreate(ctx, actor)
	if err != nil {
		return InventoryOutput{}, ErrInternal
	}
	return toInventoryOutput(record), nil
}

func toInventoryOutput(record InventoryRecord) InventoryOutput {
	items := make([]Item, 0, len(record.Items))
	for _, item := range record.Items {
		items = append(items, Item{ID: item.ID, Amount: item.Amount})
	}
	return InventoryOutput{
		UserID:       record.UserID,
		SteamID:      record.SteamID,
		SoftCurrency: record.SoftCurrency,
		HardCurrency: record.HardCurrency,
		Items:        items,
		Cosmetics:    append([]string(nil), record.Cosmetics...),
		UpdatedAt:    record.UpdatedAt,
	}
}
