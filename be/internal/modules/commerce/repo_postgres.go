package commerce

import (
	"context"
	"sort"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

func (r *PostgresRepository) GetCatalog(_ context.Context) ([]CatalogItem, error) {
	// Keep catalog static for MVP; replace with DB or config service later.
	return []CatalogItem{
		{ID: "skin_knight_01", Type: "cosmetic", Price: 1200, Currency: "CNY"},
		{ID: "skin_mage_01", Type: "cosmetic", Price: 1200, Currency: "CNY"},
		{ID: "dlc_pack_01", Type: "dlc", Price: 2800, Currency: "CNY"},
	}, nil
}

func (r *PostgresRepository) ReplaceEntitlements(ctx context.Context, userID int64, dlcIDs []int, syncedAt time.Time) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	_, err = tx.Exec(ctx, `
		INSERT INTO entitlements (user_id, steam_dlc_id, owned, source, synced_at)
		SELECT $1, unnest($2::int[]), TRUE, 'steam', $3
		ON CONFLICT (user_id, steam_dlc_id)
		DO UPDATE SET owned = TRUE, synced_at = EXCLUDED.synced_at
	`, userID, dlcIDs, syncedAt)
	if err != nil {
		return err
	}

	_, err = tx.Exec(ctx, `
		UPDATE entitlements
		SET owned = FALSE, synced_at = $3
		WHERE user_id = $1 AND NOT (steam_dlc_id = ANY($2::int[]))
	`, userID, dlcIDs, syncedAt)
	if err != nil {
		return err
	}

	if err := tx.Commit(ctx); err != nil {
		return err
	}
	return nil
}

func (r *PostgresRepository) GetOwnedEntitlements(ctx context.Context, userID int64) ([]int, error) {
	rows, err := r.pool.Query(ctx, `
		SELECT steam_dlc_id
		FROM entitlements
		WHERE user_id = $1 AND owned = TRUE
		ORDER BY steam_dlc_id ASC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	result := make([]int, 0, 8)
	for rows.Next() {
		var dlcID int
		if err := rows.Scan(&dlcID); err != nil {
			return nil, err
		}
		result = append(result, dlcID)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	sort.Ints(result)
	return result, nil
}
