package auth

import (
	"context"
	"errors"
	"strconv"
	"strings"
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

func (r *PostgresRepository) GetBySteamID(ctx context.Context, steamID string) (User, error) {
	steamInt, err := parseSteamID(steamID)
	if err != nil {
		return User{}, ErrUserNotFound
	}

	var (
		user      User
		steamDB   int64
		lastLogin *time.Time
	)
	err = r.pool.QueryRow(ctx, `
		SELECT id, steam_id, created_at, last_login_at
		FROM users
		WHERE steam_id = $1
	`, steamInt).Scan(&user.UserID, &steamDB, &user.CreatedAt, &lastLogin)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return User{}, ErrUserNotFound
		}
		return User{}, err
	}

	user.SteamID = strconv.FormatInt(steamDB, 10)
	if lastLogin != nil {
		user.LastLogin = *lastLogin
	}
	return user, nil
}

func (r *PostgresRepository) Create(ctx context.Context, steamID string) (User, error) {
	steamInt, err := parseSteamID(steamID)
	if err != nil {
		return User{}, ErrUserNotFound
	}

	var (
		user      User
		steamDB   int64
		lastLogin *time.Time
	)
	err = r.pool.QueryRow(ctx, `
		INSERT INTO users (steam_id, last_login_at, updated_at)
		VALUES ($1, NOW(), NOW())
		ON CONFLICT (steam_id)
		DO UPDATE SET last_login_at = NOW(), updated_at = NOW()
		RETURNING id, steam_id, created_at, last_login_at
	`, steamInt).Scan(&user.UserID, &steamDB, &user.CreatedAt, &lastLogin)
	if err != nil {
		return User{}, err
	}

	user.SteamID = strconv.FormatInt(steamDB, 10)
	if lastLogin != nil {
		user.LastLogin = *lastLogin
	}
	return user, nil
}

func (r *PostgresRepository) TouchLogin(ctx context.Context, steamID string, at time.Time) error {
	steamInt, err := parseSteamID(steamID)
	if err != nil {
		return ErrUserNotFound
	}

	cmd, err := r.pool.Exec(ctx, `
		UPDATE users
		SET last_login_at = $2, updated_at = NOW()
		WHERE steam_id = $1
	`, steamInt, at)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return ErrUserNotFound
	}
	return nil
}

func parseSteamID(steamID string) (int64, error) {
	steamID = strings.TrimSpace(steamID)
	if steamID == "" {
		return 0, ErrUserNotFound
	}
	value, err := strconv.ParseInt(steamID, 10, 64)
	if err != nil {
		return 0, err
	}
	return value, nil
}
