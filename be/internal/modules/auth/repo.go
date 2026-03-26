package auth

import (
	"context"
	"errors"
	"sync"
	"time"
)

var (
	ErrUserNotFound = errors.New("USER_NOT_FOUND")
)

type Repository interface {
	GetBySteamID(ctx context.Context, steamID string) (User, error)
	Create(ctx context.Context, steamID string) (User, error)
	TouchLogin(ctx context.Context, steamID string, at time.Time) error
}

type MemoryRepository struct {
	mu         sync.RWMutex
	autoID     int64
	userByID   map[int64]User
	idBySteam  map[string]int64
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		autoID:    1000,
		userByID:  make(map[int64]User),
		idBySteam: make(map[string]int64),
	}
}

func (r *MemoryRepository) GetBySteamID(_ context.Context, steamID string) (User, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	id, ok := r.idBySteam[steamID]
	if !ok {
		return User{}, ErrUserNotFound
	}
	user, ok := r.userByID[id]
	if !ok {
		return User{}, ErrUserNotFound
	}
	return user, nil
}

func (r *MemoryRepository) Create(_ context.Context, steamID string) (User, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if id, exists := r.idBySteam[steamID]; exists {
		if user, ok := r.userByID[id]; ok {
			return user, nil
		}
	}

	now := time.Now().UTC()
	r.autoID++
	user := User{
		UserID:    r.autoID,
		SteamID:   steamID,
		CreatedAt: now,
		LastLogin: now,
	}

	r.userByID[user.UserID] = user
	r.idBySteam[steamID] = user.UserID
	return user, nil
}

func (r *MemoryRepository) TouchLogin(_ context.Context, steamID string, at time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	id, ok := r.idBySteam[steamID]
	if !ok {
		return ErrUserNotFound
	}
	user, ok := r.userByID[id]
	if !ok {
		return ErrUserNotFound
	}
	user.LastLogin = at
	r.userByID[id] = user
	return nil
}
