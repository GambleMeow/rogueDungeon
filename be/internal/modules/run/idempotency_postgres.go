package run

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const idempotencyRoute = "/v1/runs/:runId/finish"

type PostgresIdempotencyStore struct {
	pool *pgxpool.Pool
	ttl  time.Duration
}

func NewPostgresIdempotencyStore(pool *pgxpool.Pool, ttl time.Duration) *PostgresIdempotencyStore {
	if ttl <= 0 {
		ttl = 24 * time.Hour
	}
	return &PostgresIdempotencyStore{
		pool: pool,
		ttl:  ttl,
	}
}

func (s *PostgresIdempotencyStore) Get(ctx context.Context, key string) (*IdempotencyRecord, error) {
	var (
		requestHash string
		responseRaw []byte
		createdAt   time.Time
	)
	err := s.pool.QueryRow(ctx, `
		SELECT request_hash, response_body, created_at
		FROM idempotency_keys
		WHERE key = $1 AND expires_at > NOW()
	`, key).Scan(&requestHash, &responseRaw, &createdAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}

	var response FinishRunOutput
	if len(responseRaw) > 0 {
		if err := json.Unmarshal(responseRaw, &response); err != nil {
			return nil, err
		}
	}

	return &IdempotencyRecord{
		Key:         key,
		RequestHash: requestHash,
		Response:    response,
		CreatedAt:   createdAt,
	}, nil
}

func (s *PostgresIdempotencyStore) Put(ctx context.Context, record IdempotencyRecord) error {
	responseRaw, err := json.Marshal(record.Response)
	if err != nil {
		return err
	}
	if record.CreatedAt.IsZero() {
		record.CreatedAt = time.Now().UTC()
	}

	cmd, err := s.pool.Exec(ctx, `
		INSERT INTO idempotency_keys (key, route, request_hash, response_body, status_code, expires_at, created_at)
		VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7)
		ON CONFLICT (key) DO NOTHING
	`, record.Key, idempotencyRoute, record.RequestHash, responseRaw, 200, time.Now().UTC().Add(s.ttl), record.CreatedAt)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		existing, err := s.Get(ctx, record.Key)
		if err != nil {
			return err
		}
		if existing != nil && existing.RequestHash != record.RequestHash {
			return ErrIdempotencyReplayMismatch
		}
	}
	return nil
}
