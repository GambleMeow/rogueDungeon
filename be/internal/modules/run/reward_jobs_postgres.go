package run

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRewardJobStore struct {
	pool *pgxpool.Pool
}

func NewPostgresRewardJobStore(pool *pgxpool.Pool) *PostgresRewardJobStore {
	return &PostgresRewardJobStore{pool: pool}
}

func (s *PostgresRewardJobStore) EnqueueDelayed(ctx context.Context, runID uuid.UUID, members []FinishMember, availableAt time.Time, manualOnly bool) error {
	jobMembers := toRewardJobMembers(members)
	if len(jobMembers) == 0 {
		return nil
	}

	payloadRaw, err := json.Marshal(jobMembers)
	if err != nil {
		return err
	}
	if availableAt.IsZero() {
		availableAt = time.Now().UTC()
	}

	_, err = s.pool.Exec(ctx, `
		INSERT INTO reward_jobs (run_id, payload, manual_only, status, attempts, next_retry_at, created_at, updated_at)
		VALUES ($1, $2::jsonb, $3, $4, 0, $5, $5, $5)
		ON CONFLICT (run_id) DO NOTHING
	`, runID, payloadRaw, manualOnly, rewardJobStatusToDB(RewardJobStatusPending), availableAt)
	return err
}

func (s *PostgresRewardJobStore) List(ctx context.Context, input ListRewardJobsInput) ([]RewardJob, int, error) {
	status := normalizeRewardJobStatus(input.Status)
	if !isRewardJobStatusValid(status) {
		return nil, 0, ErrInvalidArgument
	}
	filterRunID, hasRunID, err := parseOptionalRunID(input.RunID)
	if err != nil {
		return nil, 0, err
	}
	filterManualOnly, hasManualOnly, err := parseOptionalManualOnly(input.ManualOnly)
	if err != nil {
		return nil, 0, err
	}
	filterCreatedFrom, hasCreatedFrom, err := parseOptionalRFC3339Time(input.CreatedFrom)
	if err != nil {
		return nil, 0, err
	}
	filterCreatedTo, hasCreatedTo, err := parseOptionalRFC3339Time(input.CreatedTo)
	if err != nil {
		return nil, 0, err
	}
	if hasCreatedFrom && hasCreatedTo && filterCreatedFrom.After(filterCreatedTo) {
		return nil, 0, ErrInvalidArgument
	}
	sortField, sortAsc, err := parseRewardJobSort(input.OrderBy, input.Order)
	if err != nil {
		return nil, 0, err
	}

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

	filters := make([]string, 0, 3)
	args := make([]any, 0, 5)
	if status != "" {
		args = append(args, rewardJobStatusToDB(status))
		filters = append(filters, fmt.Sprintf("status = $%d", len(args)))
	}
	if hasRunID {
		args = append(args, filterRunID)
		filters = append(filters, fmt.Sprintf("run_id = $%d", len(args)))
	}
	if hasManualOnly {
		args = append(args, filterManualOnly)
		filters = append(filters, fmt.Sprintf("manual_only = $%d", len(args)))
	}
	if hasCreatedFrom {
		args = append(args, filterCreatedFrom)
		filters = append(filters, fmt.Sprintf("created_at >= $%d", len(args)))
	}
	if hasCreatedTo {
		args = append(args, filterCreatedTo)
		filters = append(filters, fmt.Sprintf("created_at <= $%d", len(args)))
	}

	whereClause := ""
	if len(filters) > 0 {
		whereClause = " WHERE " + strings.Join(filters, " AND ")
	}

	var total int
	countSQL := "SELECT COUNT(1) FROM reward_jobs" + whereClause
	if err := s.pool.QueryRow(ctx, countSQL, args...).Scan(&total); err != nil {
		return nil, 0, err
	}

	listArgs := append([]any{}, args...)
	listArgs = append(listArgs, limit, offset)
	limitPos := len(args) + 1
	offsetPos := len(args) + 2

	orderByClause := "created_at DESC, id DESC"
	if sortField == "id" {
		if sortAsc {
			orderByClause = "id ASC"
		} else {
			orderByClause = "id DESC"
		}
	} else if sortAsc {
		orderByClause = "created_at ASC, id ASC"
	}

	listSQL := fmt.Sprintf(`
		SELECT id, run_id, payload, manual_only, status, attempts, last_error, next_retry_at, created_at, updated_at
		FROM reward_jobs%s
		ORDER BY %s
		LIMIT $%d OFFSET $%d
	`, whereClause, orderByClause, limitPos, offsetPos)
	rows, err := s.pool.Query(ctx, listSQL, listArgs...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]RewardJob, 0, limit)
	for rows.Next() {
		job, err := scanRewardJobRow(rows)
		if err != nil {
			return nil, 0, err
		}
		items = append(items, job)
	}
	if rows.Err() != nil {
		return nil, 0, rows.Err()
	}

	return items, total, nil
}

func (s *PostgresRewardJobStore) Stats(ctx context.Context, input RewardJobStatsInput) (RewardJobStatsOutput, error) {
	status := normalizeRewardJobStatus(input.Status)
	if !isRewardJobStatusValid(status) {
		return RewardJobStatsOutput{}, ErrInvalidArgument
	}
	filterRunID, hasRunID, err := parseOptionalRunID(input.RunID)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	filterManualOnly, hasManualOnly, err := parseOptionalManualOnly(input.ManualOnly)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	filterCreatedFrom, hasCreatedFrom, err := parseOptionalRFC3339Time(input.CreatedFrom)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	filterCreatedTo, hasCreatedTo, err := parseOptionalRFC3339Time(input.CreatedTo)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	if hasCreatedFrom && hasCreatedTo && filterCreatedFrom.After(filterCreatedTo) {
		return RewardJobStatsOutput{}, ErrInvalidArgument
	}
	groupBy, err := parseRewardJobGroupBy(input.GroupBy)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	timezoneName, _, err := parseRewardJobTimezone(input.TZ)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}

	filters := make([]string, 0, 5)
	args := make([]any, 0, 5)
	if status != "" {
		args = append(args, rewardJobStatusToDB(status))
		filters = append(filters, fmt.Sprintf("status = $%d", len(args)))
	}
	if hasRunID {
		args = append(args, filterRunID)
		filters = append(filters, fmt.Sprintf("run_id = $%d", len(args)))
	}
	if hasManualOnly {
		args = append(args, filterManualOnly)
		filters = append(filters, fmt.Sprintf("manual_only = $%d", len(args)))
	}
	if hasCreatedFrom {
		args = append(args, filterCreatedFrom)
		filters = append(filters, fmt.Sprintf("created_at >= $%d", len(args)))
	}
	if hasCreatedTo {
		args = append(args, filterCreatedTo)
		filters = append(filters, fmt.Sprintf("created_at <= $%d", len(args)))
	}

	whereClause := ""
	if len(filters) > 0 {
		whereClause = " WHERE " + strings.Join(filters, " AND ")
	}

	sql := `
		SELECT
			COUNT(1) AS total,
			COUNT(1) FILTER (WHERE status = 0) AS pending,
			COUNT(1) FILTER (WHERE status = 1) AS processing,
			COUNT(1) FILTER (WHERE status = 2) AS completed,
			COUNT(1) FILTER (WHERE status = 3) AS failed,
			COUNT(1) FILTER (WHERE manual_only = TRUE) AS manual_only_true,
			COUNT(1) FILTER (WHERE manual_only = FALSE) AS manual_only_false
		FROM reward_jobs` + whereClause

	var (
		total          int64
		pending        int64
		processing     int64
		completed      int64
		failed         int64
		manualOnlyTrue int64
		manualOnlyFalse int64
	)
	if err := s.pool.QueryRow(ctx, sql, args...).Scan(
		&total,
		&pending,
		&processing,
		&completed,
		&failed,
		&manualOnlyTrue,
		&manualOnlyFalse,
	); err != nil {
		return RewardJobStatsOutput{}, err
	}

	out := RewardJobStatsOutput{
		Total:           int(total),
		Pending:         int(pending),
		Processing:      int(processing),
		Completed:       int(completed),
		Failed:          int(failed),
		ManualOnlyTrue:  int(manualOnlyTrue),
		ManualOnlyFalse: int(manualOnlyFalse),
		Timezone:        timezoneName,
	}
	if groupBy == "" {
		return out, nil
	}

	trendArgs := append([]any{}, args...)
	trendArgs = append(trendArgs, timezoneName)
	tzPos := len(trendArgs)

	var (
		bucketExpr        string
		bucketLabel       string
		bucketDisplayLabel string
	)
	switch groupBy {
	case "day":
		bucketExpr = fmt.Sprintf("(timezone($%d, created_at))::date", tzPos)
		bucketLabel = fmt.Sprintf("TO_CHAR((timezone($%d, created_at))::date, 'YYYY-MM-DD')", tzPos)
		bucketDisplayLabel = fmt.Sprintf("TO_CHAR((timezone($%d, created_at))::date, 'MM-DD')", tzPos)
	case "hour":
		bucketExpr = fmt.Sprintf("date_trunc('hour', timezone($%d, created_at))", tzPos)
		if timezoneName == "UTC" {
			bucketLabel = fmt.Sprintf("TO_CHAR(date_trunc('hour', timezone($%d, created_at)), 'YYYY-MM-DD\"T\"HH24:00:00\"Z\"')", tzPos)
		} else {
			bucketLabel = fmt.Sprintf("TO_CHAR(date_trunc('hour', timezone($%d, created_at)), 'YYYY-MM-DD\"T\"HH24:00:00')", tzPos)
		}
		bucketDisplayLabel = fmt.Sprintf("TO_CHAR(date_trunc('hour', timezone($%d, created_at)), 'MM-DD HH24:00')", tzPos)
	default:
		return RewardJobStatsOutput{}, ErrInvalidArgument
	}

	trendSQL := `
		SELECT
			` + bucketLabel + ` AS day,
			` + bucketDisplayLabel + ` AS label,
			COUNT(1) AS total,
			COUNT(1) FILTER (WHERE status = 0) AS pending,
			COUNT(1) FILTER (WHERE status = 1) AS processing,
			COUNT(1) FILTER (WHERE status = 2) AS completed,
			COUNT(1) FILTER (WHERE status = 3) AS failed,
			COUNT(1) FILTER (WHERE manual_only = TRUE) AS manual_only_true,
			COUNT(1) FILTER (WHERE manual_only = FALSE) AS manual_only_false
		FROM reward_jobs` + whereClause + `
		GROUP BY ` + bucketExpr + `
		ORDER BY ` + bucketExpr + ` ASC`

	rows, err := s.pool.Query(ctx, trendSQL, trendArgs...)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	defer rows.Close()

	out.Trend = make([]RewardJobStatsTrendItem, 0, 8)
	for rows.Next() {
		var (
			item            RewardJobStatsTrendItem
			bucket          string
			label           string
			rowTotal        int64
			rowPending      int64
			rowProcessing   int64
			rowCompleted    int64
			rowFailed       int64
			rowManualTrue   int64
			rowManualFalse  int64
		)
		if err := rows.Scan(
			&bucket,
			&label,
			&rowTotal,
			&rowPending,
			&rowProcessing,
			&rowCompleted,
			&rowFailed,
			&rowManualTrue,
			&rowManualFalse,
		); err != nil {
			return RewardJobStatsOutput{}, err
		}
		item.Bucket = bucket
		item.Day = bucket
		item.Label = label
		item.Total = int(rowTotal)
		item.Pending = int(rowPending)
		item.Processing = int(rowProcessing)
		item.Completed = int(rowCompleted)
		item.Failed = int(rowFailed)
		item.ManualOnlyTrue = int(rowManualTrue)
		item.ManualOnlyFalse = int(rowManualFalse)
		out.Trend = append(out.Trend, item)
	}
	if rows.Err() != nil {
		return RewardJobStatsOutput{}, rows.Err()
	}

	return out, nil
}

func (s *PostgresRewardJobStore) GetByID(ctx context.Context, id int64) (RewardJob, error) {
	row := s.pool.QueryRow(ctx, `
		SELECT id, run_id, payload, manual_only, status, attempts, last_error, next_retry_at, created_at, updated_at
		FROM reward_jobs
		WHERE id = $1
	`, id)
	job, err := scanRewardJobRow(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return RewardJob{}, ErrRewardJobNotFound
		}
		return RewardJob{}, err
	}
	return job, nil
}

func (s *PostgresRewardJobStore) RetryNow(ctx context.Context, id int64, at time.Time) (RewardJob, error) {
	if at.IsZero() {
		at = time.Now().UTC()
	}

	row := s.pool.QueryRow(ctx, `
		UPDATE reward_jobs
		SET status = $2,
		    manual_only = FALSE,
		    next_retry_at = $3,
		    last_error = NULL,
		    updated_at = $3
		WHERE id = $1
		RETURNING id, run_id, payload, manual_only, status, attempts, last_error, next_retry_at, created_at, updated_at
	`, id, rewardJobStatusToDB(RewardJobStatusPending), at)

	job, err := scanRewardJobRow(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return RewardJob{}, ErrRewardJobNotFound
		}
		return RewardJob{}, err
	}
	return job, nil
}

func (s *PostgresRewardJobStore) DenyNow(ctx context.Context, id int64, reason string, at time.Time) (RewardJob, error) {
	if at.IsZero() {
		at = time.Now().UTC()
	}
	reason = truncateString(reason, 512)
	if strings.TrimSpace(reason) == "" {
		reason = "denied_by_admin"
	}

	row := s.pool.QueryRow(ctx, `
		UPDATE reward_jobs
		SET status = $2,
		    manual_only = TRUE,
		    last_error = $3,
		    updated_at = $4
		WHERE id = $1
		RETURNING id, run_id, payload, manual_only, status, attempts, last_error, next_retry_at, created_at, updated_at
	`, id, rewardJobStatusToDB(RewardJobStatusFailed), reason, at)

	job, err := scanRewardJobRow(row)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return RewardJob{}, ErrRewardJobNotFound
		}
		return RewardJob{}, err
	}
	return job, nil
}

func (s *PostgresRewardJobStore) ClaimDue(ctx context.Context, limit int, now time.Time) ([]RewardJob, error) {
	if limit <= 0 {
		limit = 20
	}
	if now.IsZero() {
		now = time.Now().UTC()
	}

	rows, err := s.pool.Query(ctx, `
		WITH claimed AS (
			SELECT id
			FROM reward_jobs
			WHERE status = $1
			  AND manual_only = FALSE
			  AND next_retry_at <= $2
			ORDER BY next_retry_at ASC, id ASC
			LIMIT $3
			FOR UPDATE SKIP LOCKED
		)
		UPDATE reward_jobs j
		SET status = $4, updated_at = $2
		FROM claimed
		WHERE j.id = claimed.id
		RETURNING j.id, j.run_id, j.payload, j.manual_only, j.status, j.attempts, j.last_error, j.next_retry_at, j.created_at, j.updated_at
	`, rewardJobStatusToDB(RewardJobStatusPending), now, limit, rewardJobStatusToDB(RewardJobStatusProcessing))
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	jobs := make([]RewardJob, 0, limit)
	for rows.Next() {
		job, err := scanRewardJobRow(rows)
		if err != nil {
			return nil, err
		}
		jobs = append(jobs, job)
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	return jobs, nil
}

func (s *PostgresRewardJobStore) MarkCompleted(ctx context.Context, id int64, at time.Time) error {
	if at.IsZero() {
		at = time.Now().UTC()
	}

	cmd, err := s.pool.Exec(ctx, `
		UPDATE reward_jobs
		SET status = $2,
		    last_error = NULL,
		    updated_at = $3
		WHERE id = $1
	`, id, rewardJobStatusToDB(RewardJobStatusCompleted), at)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return ErrRewardJobNotFound
	}
	return nil
}

func (s *PostgresRewardJobStore) MarkRetry(ctx context.Context, id int64, nextRetryAt time.Time, lastError string, at time.Time) error {
	if at.IsZero() {
		at = time.Now().UTC()
	}
	if nextRetryAt.IsZero() {
		nextRetryAt = at.Add(30 * time.Second)
	}

	cmd, err := s.pool.Exec(ctx, `
		UPDATE reward_jobs
		SET status = $2,
		    attempts = attempts + 1,
		    last_error = $3,
		    next_retry_at = $4,
		    updated_at = $5
		WHERE id = $1
	`, id, rewardJobStatusToDB(RewardJobStatusPending), truncateString(lastError, 512), nextRetryAt, at)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return ErrRewardJobNotFound
	}
	return nil
}

func (s *PostgresRewardJobStore) MarkFailed(ctx context.Context, id int64, lastError string, at time.Time) error {
	if at.IsZero() {
		at = time.Now().UTC()
	}

	cmd, err := s.pool.Exec(ctx, `
		UPDATE reward_jobs
		SET status = $2,
		    attempts = attempts + 1,
		    last_error = $3,
		    updated_at = $4
		WHERE id = $1
	`, id, rewardJobStatusToDB(RewardJobStatusFailed), truncateString(lastError, 512), at)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return ErrRewardJobNotFound
	}
	return nil
}

type rewardJobRowScanner interface {
	Scan(dest ...any) error
}

func scanRewardJobRow(row rewardJobRowScanner) (RewardJob, error) {
	var (
		job       RewardJob
		runID     uuid.UUID
		payload   []byte
		manualOnly bool
		statusDB  int16
		lastError *string
	)

	err := row.Scan(
		&job.ID,
		&runID,
		&payload,
		&manualOnly,
		&statusDB,
		&job.Attempts,
		&lastError,
		&job.NextRetryAt,
		&job.CreatedAt,
		&job.UpdatedAt,
	)
	if err != nil {
		return RewardJob{}, err
	}

	job.RunID = runID.String()
	job.ManualOnly = manualOnly
	job.Status = rewardJobStatusFromDB(statusDB)
	if lastError != nil {
		job.LastError = *lastError
	}

	job.Members = []RewardJobMember{}
	if len(payload) > 0 {
		if err := json.Unmarshal(payload, &job.Members); err != nil {
			return RewardJob{}, err
		}
	}
	return job, nil
}

func rewardJobStatusToDB(status string) int16 {
	switch normalizeRewardJobStatus(status) {
	case RewardJobStatusProcessing:
		return 1
	case RewardJobStatusCompleted:
		return 2
	case RewardJobStatusFailed:
		return 3
	default:
		return 0
	}
}

func rewardJobStatusFromDB(status int16) string {
	switch status {
	case 1:
		return RewardJobStatusProcessing
	case 2:
		return RewardJobStatusCompleted
	case 3:
		return RewardJobStatusFailed
	default:
		return RewardJobStatusPending
	}
}

func truncateString(raw string, limit int) string {
	raw = strings.TrimSpace(raw)
	if limit <= 0 || len(raw) <= limit {
		return raw
	}
	return raw[:limit]
}
