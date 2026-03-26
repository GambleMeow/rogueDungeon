package migrate

import (
	"context"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

type Runner struct {
	pool          *pgxpool.Pool
	migrationsDir string
}

func NewRunner(pool *pgxpool.Pool, migrationsDir string) *Runner {
	return &Runner{
		pool:          pool,
		migrationsDir: strings.TrimSpace(migrationsDir),
	}
}

func (r *Runner) Run(ctx context.Context) error {
	if err := r.ensureSchemaMigrationsTable(ctx); err != nil {
		return err
	}

	migrationsDir, err := r.resolveMigrationsDir()
	if err != nil {
		return err
	}

	entries, err := os.ReadDir(migrationsDir)
	if err != nil {
		return err
	}

	upFiles := make([]string, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := entry.Name()
		if strings.HasSuffix(name, ".up.sql") {
			upFiles = append(upFiles, name)
		}
	}
	sort.Strings(upFiles)

	for _, fileName := range upFiles {
		version := strings.TrimSuffix(fileName, ".up.sql")
		applied, err := r.isApplied(ctx, version)
		if err != nil {
			return err
		}
		if applied {
			continue
		}

		content, err := os.ReadFile(filepath.Join(migrationsDir, fileName))
		if err != nil {
			return err
		}

		tx, err := r.pool.Begin(ctx)
		if err != nil {
			return err
		}

		if _, err := tx.Exec(ctx, string(content)); err != nil {
			_ = tx.Rollback(ctx)
			return err
		}
		if _, err := tx.Exec(ctx, `
			INSERT INTO schema_migrations (version)
			VALUES ($1)
		`, version); err != nil {
			_ = tx.Rollback(ctx)
			return err
		}

		if err := tx.Commit(ctx); err != nil {
			return err
		}
	}

	return nil
}

func (r *Runner) ensureSchemaMigrationsTable(ctx context.Context) error {
	_, err := r.pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS schema_migrations (
			version VARCHAR(64) PRIMARY KEY,
			applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
		)
	`)
	return err
}

func (r *Runner) isApplied(ctx context.Context, version string) (bool, error) {
	var exists bool
	err := r.pool.QueryRow(ctx, `
		SELECT EXISTS(
			SELECT 1 FROM schema_migrations WHERE version = $1
		)
	`, version).Scan(&exists)
	return exists, err
}

func (r *Runner) resolveMigrationsDir() (string, error) {
	if r.migrationsDir != "" {
		return r.migrationsDir, nil
	}

	if fromEnv := strings.TrimSpace(os.Getenv("MIGRATIONS_DIR")); fromEnv != "" {
		return fromEnv, nil
	}

	if wd, err := os.Getwd(); err == nil {
		candidate := filepath.Join(wd, "migrations")
		if stat, err := os.Stat(candidate); err == nil && stat.IsDir() {
			return candidate, nil
		}
	}

	exePath, err := os.Executable()
	if err != nil {
		return "", err
	}
	return filepath.Join(filepath.Dir(exePath), "migrations"), nil
}
