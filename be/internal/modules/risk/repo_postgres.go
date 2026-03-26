package risk

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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

func (r *PostgresRepository) CreateFlags(ctx context.Context, input CreateFlagsInput) error {
	if len(input.Reasons) == 0 {
		return nil
	}

	scorePerReason := max(1, input.RiskScore/len(input.Reasons))
	evidenceRaw, err := json.Marshal(input.Evidence)
	if err != nil {
		return err
	}
	if len(evidenceRaw) == 0 {
		evidenceRaw = []byte("{}")
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	for _, reason := range input.Reasons {
		if reason == "" {
			continue
		}
		_, err := tx.Exec(ctx, `
			INSERT INTO risk_flags (user_id, run_id, rule_code, score, evidence, action, status, created_at)
			VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8)
		`, input.UserID, input.RunID, reason, scorePerReason, evidenceRaw, actionToDB(ActionObserve), statusToDB(StatusPending), time.Now().UTC())
		if err != nil {
			return err
		}
	}

	return tx.Commit(ctx)
}

func (r *PostgresRepository) ListFlags(ctx context.Context, input ListFlagsInput) ([]RiskFlag, int, error) {
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

	args := make([]any, 0, 6)
	whereParts := make([]string, 0, 4)
	argPos := 1
	if input.Status != "" {
		whereParts = append(whereParts, fmt.Sprintf("status = $%d", argPos))
		args = append(args, statusToDB(input.Status))
		argPos++
	}
	if input.RuleCode != "" {
		whereParts = append(whereParts, fmt.Sprintf("rule_code = $%d", argPos))
		args = append(args, input.RuleCode)
		argPos++
	}
	if input.Source != "" {
		whereParts = append(whereParts, fmt.Sprintf("evidence->>'source' = $%d", argPos))
		args = append(args, input.Source)
		argPos++
	}
	if input.Event != "" {
		codes := reconnectEventRuleCodes(input.Event)
		if len(codes) > 0 {
			whereParts = append(whereParts, fmt.Sprintf("rule_code = ANY($%d)", argPos))
			args = append(args, codes)
			argPos++
		}
	}

	where := ""
	if len(whereParts) > 0 {
		where = " WHERE " + strings.Join(whereParts, " AND ")
	}

	countSQL := "SELECT COUNT(1) FROM risk_flags" + where
	var total int
	if err := r.pool.QueryRow(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	listSQL := fmt.Sprintf(`
		SELECT id, user_id, run_id::text, rule_code, score, evidence, action, status, note, created_at, handled_at
		FROM risk_flags
		%s
		ORDER BY created_at DESC, id DESC
		LIMIT $%d OFFSET $%d
	`, where, argPos, argPos+1)
	listArgs := make([]any, 0, len(args)+2)
	listArgs = append(listArgs, args...)
	listArgs = append(listArgs, limit, offset)

	rows, err := r.pool.Query(ctx, listSQL, listArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]RiskFlag, 0, limit)
	for rows.Next() {
		flag, err := scanRiskFlag(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, flag)
	}
	if rows.Err() != nil {
		return nil, 0, rows.Err()
	}

	return items, total, nil
}

func (r *PostgresRepository) ApplyAction(ctx context.Context, id int64, input ApplyActionInput, handledAt time.Time) (RiskFlag, error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE risk_flags
		SET action = $2, status = $3, note = $4, handled_at = $5
		WHERE id = $1
		RETURNING id, user_id, run_id::text, rule_code, score, evidence, action, status, note, created_at, handled_at
	`, id, actionToDB(input.Action), statusToDB(StatusProcessed), input.Note, handledAt)

	flag, err := scanRiskFlag(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return RiskFlag{}, ErrFlagNotFound
		}
		return RiskFlag{}, err
	}
	return flag, nil
}

type rowScanner interface {
	Scan(dest ...any) error
}

func scanRiskFlag(row rowScanner) (RiskFlag, error) {
	var (
		flag      RiskFlag
		runID     *string
		evidence  []byte
		actionDB  int16
		statusDB  int16
		note      *string
		handledAt *time.Time
	)

	err := row.Scan(
		&flag.ID,
		&flag.UserID,
		&runID,
		&flag.RuleCode,
		&flag.Score,
		&evidence,
		&actionDB,
		&statusDB,
		&note,
		&flag.CreatedAt,
		&handledAt,
	)
	if err != nil {
		return RiskFlag{}, err
	}

	if runID != nil {
		flag.RunID = *runID
	}
	if note != nil {
		flag.Note = *note
	}
	flag.HandledAt = handledAt
	flag.Action = actionFromDB(actionDB)
	flag.Status = statusFromDB(statusDB)

	flag.Evidence = map[string]any{}
	if len(evidence) > 0 {
		if err := json.Unmarshal(evidence, &flag.Evidence); err != nil {
			return RiskFlag{}, err
		}
	}

	return flag, nil
}

func actionToDB(action string) int16 {
	switch action {
	case ActionLimitReward:
		return 1
	case ActionRollback:
		return 2
	case ActionBan:
		return 3
	default:
		return 0
	}
}

func actionFromDB(action int16) string {
	switch action {
	case 1:
		return ActionLimitReward
	case 2:
		return ActionRollback
	case 3:
		return ActionBan
	default:
		return ActionObserve
	}
}

func statusToDB(status string) int16 {
	switch status {
	case StatusProcessed:
		return 1
	case StatusFalsePositive:
		return 2
	case StatusIgnored:
		return 3
	default:
		return 0
	}
}

func statusFromDB(status int16) string {
	switch status {
	case 1:
		return StatusProcessed
	case 2:
		return StatusFalsePositive
	case 3:
		return StatusIgnored
	default:
		return StatusPending
	}
}

func MustStatus(status string) error {
	switch status {
	case "", StatusPending, StatusProcessed, StatusFalsePositive, StatusIgnored:
		return nil
	default:
		return fmt.Errorf("invalid status")
	}
}

func MustEvent(event string) error {
	switch event {
	case "", EventReconnect, EventReconnectFailed, EventReconnectTimeout:
		return nil
	default:
		return fmt.Errorf("invalid event")
	}
}
