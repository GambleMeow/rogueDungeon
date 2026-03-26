package player

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

func (r *PostgresRepository) GetOrCreate(ctx context.Context, actor UserRef) (ProfileRecord, error) {
	defaultLoadout, err := json.Marshal(Loadout{
		CharacterID: "warrior_a",
		WeaponID:    "sword_a",
		SkillIDs:    []string{},
	})
	if err != nil {
		return ProfileRecord{}, err
	}

	_, err = r.pool.Exec(ctx, `
		INSERT INTO player_profiles (user_id, loadout)
		VALUES ($1, $2::jsonb)
		ON CONFLICT (user_id) DO NOTHING
	`, actor.UserID, defaultLoadout)
	if err != nil {
		return ProfileRecord{}, err
	}

	return r.fetchProfile(ctx, actor.UserID)
}

func (r *PostgresRepository) UpdateLoadout(ctx context.Context, userID int64, loadout Loadout, at time.Time) (ProfileRecord, error) {
	loadoutJSON, err := json.Marshal(loadout)
	if err != nil {
		return ProfileRecord{}, err
	}

	_, err = r.pool.Exec(ctx, `
		UPDATE player_profiles
		SET loadout = $2::jsonb, updated_at = $3
		WHERE user_id = $1
	`, userID, loadoutJSON, at)
	if err != nil {
		return ProfileRecord{}, err
	}

	return r.fetchProfile(ctx, userID)
}

func (r *PostgresRepository) fetchProfile(ctx context.Context, userID int64) (ProfileRecord, error) {
	var (
		record     ProfileRecord
		steamIDInt int64
		talentsRaw []byte
		loadoutRaw []byte
	)

	err := r.pool.QueryRow(ctx, `
		SELECT p.user_id, u.steam_id, p.level, p.exp, p.talent_points, p.talents, p.loadout, p.updated_at
		FROM player_profiles p
		JOIN users u ON u.id = p.user_id
		WHERE p.user_id = $1
	`, userID).Scan(
		&record.UserID,
		&steamIDInt,
		&record.Level,
		&record.Exp,
		&record.TalentPoints,
		&talentsRaw,
		&loadoutRaw,
		&record.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ProfileRecord{}, err
		}
		return ProfileRecord{}, err
	}

	record.SteamID = strconv.FormatInt(steamIDInt, 10)
	if len(talentsRaw) == 0 {
		record.Talents = map[string]int{}
	} else if err := json.Unmarshal(talentsRaw, &record.Talents); err != nil {
		return ProfileRecord{}, err
	}
	if len(loadoutRaw) == 0 {
		record.Loadout = Loadout{}
	} else if err := json.Unmarshal(loadoutRaw, &record.Loadout); err != nil {
		return ProfileRecord{}, err
	}
	return record, nil
}
