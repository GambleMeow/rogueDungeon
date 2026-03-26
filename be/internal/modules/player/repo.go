package player

import (
	"context"
	"sync"
	"time"
)

type Repository interface {
	GetOrCreate(ctx context.Context, actor UserRef) (ProfileRecord, error)
	UpdateLoadout(ctx context.Context, userID int64, loadout Loadout, at time.Time) (ProfileRecord, error)
}

type MemoryRepository struct {
	mu      sync.RWMutex
	records map[int64]ProfileRecord
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		records: make(map[int64]ProfileRecord),
	}
}

func (r *MemoryRepository) GetOrCreate(_ context.Context, actor UserRef) (ProfileRecord, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if record, ok := r.records[actor.UserID]; ok {
		return cloneProfileRecord(record), nil
	}

	now := time.Now().UTC()
	record := ProfileRecord{
		UserID:       actor.UserID,
		SteamID:      actor.SteamID,
		Level:        1,
		Exp:          0,
		TalentPoints: 0,
		Talents:      map[string]int{},
		Loadout: Loadout{
			CharacterID: "warrior_a",
			WeaponID:    "sword_a",
			SkillIDs:    []string{},
		},
		UpdatedAt: now,
	}
	r.records[actor.UserID] = record
	return cloneProfileRecord(record), nil
}

func (r *MemoryRepository) UpdateLoadout(_ context.Context, userID int64, loadout Loadout, at time.Time) (ProfileRecord, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	record, ok := r.records[userID]
	if !ok {
		record = ProfileRecord{
			UserID:       userID,
			Level:        1,
			Exp:          0,
			TalentPoints: 0,
			Talents:      map[string]int{},
		}
	}

	record.Loadout = Loadout{
		CharacterID: loadout.CharacterID,
		WeaponID:    loadout.WeaponID,
		SkillIDs:    append([]string(nil), loadout.SkillIDs...),
	}
	record.UpdatedAt = at
	r.records[userID] = record
	return cloneProfileRecord(record), nil
}

func cloneProfileRecord(record ProfileRecord) ProfileRecord {
	talents := make(map[string]int, len(record.Talents))
	for key, value := range record.Talents {
		talents[key] = value
	}
	return ProfileRecord{
		UserID:       record.UserID,
		SteamID:      record.SteamID,
		Level:        record.Level,
		Exp:          record.Exp,
		TalentPoints: record.TalentPoints,
		Talents:      talents,
		Loadout: Loadout{
			CharacterID: record.Loadout.CharacterID,
			WeaponID:    record.Loadout.WeaponID,
			SkillIDs:    append([]string(nil), record.Loadout.SkillIDs...),
		},
		UpdatedAt: record.UpdatedAt,
	}
}
