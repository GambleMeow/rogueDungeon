package audit

import (
	"context"
	"maps"
	"slices"
	"sync"
	"time"
)

type Repository interface {
	Create(ctx context.Context, input CreateLogInput, at time.Time) error
	List(ctx context.Context, input ListLogsInput) ([]LogEntry, int, error)
}

type MemoryRepository struct {
	mu      sync.RWMutex
	autoID  int64
	records []LogEntry
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		autoID:  1,
		records: make([]LogEntry, 0, 64),
	}
}

func (r *MemoryRepository) Create(_ context.Context, input CreateLogInput, at time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	payload := map[string]any{}
	if input.Payload != nil {
		maps.Copy(payload, input.Payload)
	}

	entry := LogEntry{
		ID:         r.autoID,
		AdminActor: input.AdminActor,
		Action:     input.Action,
		TargetType: input.TargetType,
		TargetID:   input.TargetID,
		Payload:    payload,
		CreatedAt:  at,
	}
	r.autoID++
	r.records = append(r.records, entry)
	return nil
}

func (r *MemoryRepository) List(_ context.Context, input ListLogsInput) ([]LogEntry, int, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	limit := input.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	offset := input.Offset
	if offset < 0 {
		offset = 0
	}

	items := make([]LogEntry, 0, len(r.records))
	for _, record := range r.records {
		payload := map[string]any{}
		if record.Payload != nil {
			maps.Copy(payload, record.Payload)
		}
		items = append(items, LogEntry{
			ID:         record.ID,
			AdminActor: record.AdminActor,
			Action:     record.Action,
			TargetType: record.TargetType,
			TargetID:   record.TargetID,
			Payload:    payload,
			CreatedAt:  record.CreatedAt,
		})
	}

	slices.SortStableFunc(items, func(a, b LogEntry) int {
		if a.CreatedAt.Equal(b.CreatedAt) {
			switch {
			case a.ID > b.ID:
				return -1
			case a.ID < b.ID:
				return 1
			default:
				return 0
			}
		}
		if a.CreatedAt.After(b.CreatedAt) {
			return -1
		}
		return 1
	})

	total := len(items)
	if offset >= total {
		return []LogEntry{}, total, nil
	}
	end := offset + limit
	if end > total {
		end = total
	}
	return items[offset:end], total, nil
}
