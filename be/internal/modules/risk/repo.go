package risk

import (
	"context"
	"errors"
	"maps"
	"slices"
	"strings"
	"sync"
	"time"
)

var ErrFlagNotFound = errors.New("RISK_FLAG_NOT_FOUND")

type Repository interface {
	CreateFlags(ctx context.Context, input CreateFlagsInput) error
	ListFlags(ctx context.Context, input ListFlagsInput) ([]RiskFlag, int, error)
	ApplyAction(ctx context.Context, id int64, input ApplyActionInput, handledAt time.Time) (RiskFlag, error)
}

type MemoryRepository struct {
	mu      sync.RWMutex
	autoID  int64
	records map[int64]RiskFlag
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		autoID:  1,
		records: make(map[int64]RiskFlag),
	}
}

func (r *MemoryRepository) CreateFlags(_ context.Context, input CreateFlagsInput) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if len(input.Reasons) == 0 {
		return nil
	}

	scorePerReason := max(1, input.RiskScore/len(input.Reasons))
	now := time.Now().UTC()
	for _, reason := range input.Reasons {
		if reason == "" {
			continue
		}

		id := r.autoID
		r.autoID++

		evidence := map[string]any{}
		if input.Evidence != nil {
			maps.Copy(evidence, input.Evidence)
		}

		r.records[id] = RiskFlag{
			ID:        id,
			UserID:    input.UserID,
			RunID:     input.RunID.String(),
			RuleCode:  reason,
			Score:     scorePerReason,
			Evidence:  evidence,
			Action:    ActionObserve,
			Status:    StatusPending,
			CreatedAt: now,
		}
	}
	return nil
}

func (r *MemoryRepository) ListFlags(_ context.Context, input ListFlagsInput) ([]RiskFlag, int, error) {
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

	all := make([]RiskFlag, 0, len(r.records))
	for _, record := range r.records {
		if input.Status != "" && record.Status != input.Status {
			continue
		}
		if input.RuleCode != "" && !strings.EqualFold(record.RuleCode, input.RuleCode) {
			continue
		}
		if input.Source != "" {
			source, _ := record.Evidence["source"].(string)
			if !strings.EqualFold(strings.TrimSpace(source), input.Source) {
				continue
			}
		}
		if input.Event != "" {
			allowed := reconnectEventRuleCodes(input.Event)
			if len(allowed) == 0 || !containsStringFold(allowed, record.RuleCode) {
				continue
			}
		}
		all = append(all, cloneFlag(record))
	}

	slices.SortStableFunc(all, func(a, b RiskFlag) int {
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

	total := len(all)
	if offset >= total {
		return []RiskFlag{}, total, nil
	}

	end := offset + limit
	if end > total {
		end = total
	}
	return all[offset:end], total, nil
}

func (r *MemoryRepository) ApplyAction(_ context.Context, id int64, input ApplyActionInput, handledAt time.Time) (RiskFlag, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	record, ok := r.records[id]
	if !ok {
		return RiskFlag{}, ErrFlagNotFound
	}

	record.Action = input.Action
	record.Status = StatusProcessed
	record.Note = input.Note
	record.HandledAt = &handledAt
	r.records[id] = record
	return cloneFlag(record), nil
}

func cloneFlag(flag RiskFlag) RiskFlag {
	evidence := map[string]any{}
	if flag.Evidence != nil {
		maps.Copy(evidence, flag.Evidence)
	}
	cloned := flag
	cloned.Evidence = evidence
	return cloned
}

func containsStringFold(values []string, target string) bool {
	for _, value := range values {
		if strings.EqualFold(value, target) {
			return true
		}
	}
	return false
}
