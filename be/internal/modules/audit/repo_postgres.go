package audit

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

func (r *PostgresRepository) Create(ctx context.Context, input CreateLogInput, at time.Time) error {
	payloadRaw, err := json.Marshal(input.Payload)
	if err != nil {
		return err
	}
	if len(payloadRaw) == 0 {
		payloadRaw = []byte("{}")
	}

	_, err = r.pool.Exec(ctx, `
		INSERT INTO admin_audit_logs (admin_actor, action, target_type, target_id, payload, created_at)
		VALUES ($1, $2, $3, $4, $5::jsonb, $6)
	`, input.AdminActor, input.Action, input.TargetType, input.TargetID, payloadRaw, at)
	return err
}

func (r *PostgresRepository) List(ctx context.Context, input ListLogsInput) ([]LogEntry, int, error) {
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

	var total int
	if err := r.pool.QueryRow(ctx, `SELECT COUNT(1) FROM admin_audit_logs`).Scan(&total); err != nil {
		return nil, 0, err
	}

	rows, err := r.pool.Query(ctx, `
		SELECT id, admin_actor, action, target_type, target_id, payload, created_at
		FROM admin_audit_logs
		ORDER BY created_at DESC, id DESC
		LIMIT $1 OFFSET $2
	`, limit, offset)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]LogEntry, 0, limit)
	for rows.Next() {
		var (
			entry      LogEntry
			payloadRaw []byte
		)
		if err := rows.Scan(&entry.ID, &entry.AdminActor, &entry.Action, &entry.TargetType, &entry.TargetID, &payloadRaw, &entry.CreatedAt); err != nil {
			return nil, 0, err
		}
		entry.Payload = map[string]any{}
		if len(payloadRaw) > 0 {
			if err := json.Unmarshal(payloadRaw, &entry.Payload); err != nil {
				return nil, 0, err
			}
		}
		items = append(items, entry)
	}
	if rows.Err() != nil {
		return nil, 0, rows.Err()
	}

	return items, total, nil
}
