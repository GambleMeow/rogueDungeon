package commerce

import (
	"context"
	"errors"
	"slices"
	"strings"
	"time"
)

var (
	ErrInvalidArgument = errors.New("INVALID_ARGUMENT")
	ErrUnauthorized    = errors.New("UNAUTHORIZED")
	ErrInternal        = errors.New("INTERNAL_ERROR")
)

type Service interface {
	GetCatalog(ctx context.Context) (CatalogOutput, error)
	SyncEntitlements(ctx context.Context, actor UserRef, input SyncEntitlementsInput) (SyncEntitlementsOutput, error)
}

type service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return &service{repo: repo}
}

func (s *service) GetCatalog(ctx context.Context) (CatalogOutput, error) {
	items, err := s.repo.GetCatalog(ctx)
	if err != nil {
		return CatalogOutput{}, ErrInternal
	}
	return CatalogOutput{Items: items}, nil
}

func (s *service) SyncEntitlements(ctx context.Context, actor UserRef, input SyncEntitlementsInput) (SyncEntitlementsOutput, error) {
	if actor.UserID <= 0 || strings.TrimSpace(actor.SteamID) == "" {
		return SyncEntitlementsOutput{}, ErrUnauthorized
	}
	if input.OwnedDLCIDs == nil || len(input.OwnedDLCIDs) > 128 {
		return SyncEntitlementsOutput{}, ErrInvalidArgument
	}

	uniq := make(map[int]struct{}, len(input.OwnedDLCIDs))
	dlcIDs := make([]int, 0, len(input.OwnedDLCIDs))
	for _, id := range input.OwnedDLCIDs {
		if id <= 0 {
			return SyncEntitlementsOutput{}, ErrInvalidArgument
		}
		if _, exists := uniq[id]; exists {
			continue
		}
		uniq[id] = struct{}{}
		dlcIDs = append(dlcIDs, id)
	}
	slices.Sort(dlcIDs)

	syncedAt := time.Now().UTC()
	if err := s.repo.ReplaceEntitlements(ctx, actor.UserID, dlcIDs, syncedAt); err != nil {
		return SyncEntitlementsOutput{}, ErrInternal
	}
	owned, err := s.repo.GetOwnedEntitlements(ctx, actor.UserID)
	if err != nil {
		return SyncEntitlementsOutput{}, ErrInternal
	}

	return SyncEntitlementsOutput{
		UserID:      actor.UserID,
		SteamID:     actor.SteamID,
		OwnedDLCIDs: owned,
		SyncedAt:    syncedAt,
	}, nil
}
