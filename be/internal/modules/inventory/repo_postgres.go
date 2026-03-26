package inventory

import (
	"context"
	"encoding/json"
	"errors"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

func (r *PostgresRepository) GetOrCreate(ctx context.Context, actor UserRef) (InventoryRecord, error) {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO inventories (user_id)
		VALUES ($1)
		ON CONFLICT (user_id) DO NOTHING
	`, actor.UserID)
	if err != nil {
		return InventoryRecord{}, err
	}

	var (
		record     InventoryRecord
		steamIDInt int64
		itemsRaw   []byte
		cosRaw     []byte
	)
	err = r.pool.QueryRow(ctx, `
		SELECT i.user_id, u.steam_id, i.soft_currency, i.hard_currency, i.items, i.cosmetics, i.updated_at
		FROM inventories i
		JOIN users u ON u.id = i.user_id
		WHERE i.user_id = $1
	`, actor.UserID).Scan(
		&record.UserID,
		&steamIDInt,
		&record.SoftCurrency,
		&record.HardCurrency,
		&itemsRaw,
		&cosRaw,
		&record.UpdatedAt,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return InventoryRecord{}, err
		}
		return InventoryRecord{}, err
	}

	record.SteamID = strconv.FormatInt(steamIDInt, 10)
	if len(itemsRaw) == 0 {
		record.Items = []Item{}
	} else if err := json.Unmarshal(itemsRaw, &record.Items); err != nil {
		return InventoryRecord{}, err
	}
	if len(cosRaw) == 0 {
		record.Cosmetics = []string{}
	} else if err := json.Unmarshal(cosRaw, &record.Cosmetics); err != nil {
		return InventoryRecord{}, err
	}

	return record, nil
}

func (r *PostgresRepository) ApplyRewardsForRun(ctx context.Context, userID int64, runID uuid.UUID, grants []RewardGrant, at time.Time) (bool, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return false, err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	grantsPayload, err := json.Marshal(grants)
	if err != nil {
		return false, err
	}

	grantCmd, err := tx.Exec(ctx, `
		INSERT INTO reward_grants (user_id, run_id, payload, created_at)
		VALUES ($1, $2, $3::jsonb, $4)
		ON CONFLICT (user_id, run_id) DO NOTHING
	`, userID, runID, grantsPayload, at)
	if err != nil {
		return false, err
	}
	if grantCmd.RowsAffected() == 0 {
		if err := tx.Rollback(ctx); err != nil {
			return false, err
		}
		return false, nil
	}

	_, err = tx.Exec(ctx, `
		INSERT INTO inventories (user_id)
		VALUES ($1)
		ON CONFLICT (user_id) DO NOTHING
	`, userID)
	if err != nil {
		return false, err
	}

	var (
		softCurrency int
		hardCurrency int
		itemsRaw     []byte
		cosRaw       []byte
	)
	err = tx.QueryRow(ctx, `
		SELECT soft_currency, hard_currency, items, cosmetics
		FROM inventories
		WHERE user_id = $1
		FOR UPDATE
	`, userID).Scan(&softCurrency, &hardCurrency, &itemsRaw, &cosRaw)
	if err != nil {
		return false, err
	}

	items := []Item{}
	if len(itemsRaw) > 0 {
		if err := json.Unmarshal(itemsRaw, &items); err != nil {
			return false, err
		}
	}

	cosmetics := []string{}
	if len(cosRaw) > 0 {
		if err := json.Unmarshal(cosRaw, &cosmetics); err != nil {
			return false, err
		}
	}

	for _, grant := range grants {
		if grant.Amount <= 0 {
			continue
		}

		switch grant.Type {
		case "soft_currency":
			softCurrency += grant.Amount
		case "hard_currency":
			hardCurrency += grant.Amount
		case "item":
			found := false
			for idx := range items {
				if items[idx].ID == grant.ID {
					items[idx].Amount += grant.Amount
					found = true
					break
				}
			}
			if !found {
				items = append(items, Item{
					ID:     grant.ID,
					Amount: grant.Amount,
				})
			}
		case "cosmetic":
			owned := false
			for _, cosmeticID := range cosmetics {
				if cosmeticID == grant.ID {
					owned = true
					break
				}
			}
			if !owned {
				cosmetics = append(cosmetics, grant.ID)
			}
		}
	}

	newItemsRaw, err := json.Marshal(items)
	if err != nil {
		return false, err
	}
	newCosRaw, err := json.Marshal(cosmetics)
	if err != nil {
		return false, err
	}

	_, err = tx.Exec(ctx, `
		UPDATE inventories
		SET soft_currency = $2,
		    hard_currency = $3,
		    items = $4::jsonb,
		    cosmetics = $5::jsonb,
		    version = version + 1,
		    updated_at = $6
		WHERE user_id = $1
	`, userID, softCurrency, hardCurrency, newItemsRaw, newCosRaw, at)
	if err != nil {
		return false, err
	}

	if err := tx.Commit(ctx); err != nil {
		return false, err
	}
	return true, nil
}
