package run

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
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

func (r *PostgresRepository) CreateRun(ctx context.Context, session RunSession) error {
	hostSteamID, err := strconv.ParseInt(session.HostSteamID, 10, 64)
	if err != nil {
		return ErrInvalidArgument
	}

	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	_, err = tx.Exec(ctx, `
		INSERT INTO run_sessions (
			run_id, seed, run_token_hash, host_user_id, host_steam_id, mode, difficulty, region, status,
			host_last_heartbeat_at, host_reconnect_deadline_at, host_migration_deadline_at, migration_epoch,
			reconnect_token_hash, reconnect_token_steam_id, reconnect_token_expire_at,
			started_at, created_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $17)
	`, session.RunID, session.Seed, session.RunTokenHash, session.HostUserID, hostSteamID, session.Mode, session.Difficulty, session.Region, statusToDB(session.Status), session.HostLastHeartbeatAt, session.HostReconnectDeadlineAt, session.HostMigrationDeadlineAt, session.MigrationEpoch, nullIfEmpty(session.ReconnectTokenHash), nullSteamInt64(session.ReconnectTokenSteamID), session.ReconnectTokenExpireAt, session.StartedAt)
	if err != nil {
		return err
	}

	for idx, member := range session.Party {
		steamInt, err := strconv.ParseInt(member.SteamID, 10, 64)
		if err != nil {
			return ErrInvalidArgument
		}

		_, err = tx.Exec(ctx, `
			INSERT INTO run_session_members (run_id, steam_id, char_id, slot_no, is_host, member_state, last_seen_at, reconnect_deadline_at, joined_at)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		`, session.RunID, steamInt, member.CharID, idx+1, member.SteamID == session.HostSteamID, memberStateToDB(member.State), member.LastSeenAt, member.ReconnectDeadlineAt, session.StartedAt)
		if err != nil {
			return err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return err
	}
	return nil
}

func (r *PostgresRepository) GetRun(ctx context.Context, runID uuid.UUID) (RunSession, error) {
	var (
		session                 RunSession
		hostSteam               int64
		statusDB                int16
		endedAtRaw              *time.Time
		hostLastHeartbeatAtRaw  *time.Time
		hostReconnectDeadlineAt *time.Time
		hostMigrationDeadlineAt *time.Time
		migrationEpoch          int64
		reconnectTokenHash      *string
		reconnectTokenSteamID   *int64
		reconnectTokenExpireAt  *time.Time
	)

	err := r.pool.QueryRow(ctx, `
		SELECT run_id, seed, run_token_hash, host_user_id, host_steam_id, mode, difficulty, region, status,
		       host_last_heartbeat_at, host_reconnect_deadline_at, host_migration_deadline_at, migration_epoch,
		       reconnect_token_hash, reconnect_token_steam_id, reconnect_token_expire_at,
		       started_at, ended_at
		FROM run_sessions
		WHERE run_id = $1
	`, runID).Scan(
		&session.RunID,
		&session.Seed,
		&session.RunTokenHash,
		&session.HostUserID,
		&hostSteam,
		&session.Mode,
		&session.Difficulty,
		&session.Region,
		&statusDB,
		&hostLastHeartbeatAtRaw,
		&hostReconnectDeadlineAt,
		&hostMigrationDeadlineAt,
		&migrationEpoch,
		&reconnectTokenHash,
		&reconnectTokenSteamID,
		&reconnectTokenExpireAt,
		&session.StartedAt,
		&endedAtRaw,
	)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return RunSession{}, errRecordNotFound
		}
		return RunSession{}, err
	}

	session.HostSteamID = strconv.FormatInt(hostSteam, 10)
	session.Status = statusFromDB(statusDB)
	session.EndedAt = endedAtRaw
	session.HostLastHeartbeatAt = hostLastHeartbeatAtRaw
	session.HostReconnectDeadlineAt = hostReconnectDeadlineAt
	session.HostMigrationDeadlineAt = hostMigrationDeadlineAt
	session.MigrationEpoch = migrationEpoch
	if reconnectTokenHash != nil {
		session.ReconnectTokenHash = *reconnectTokenHash
	}
	if reconnectTokenSteamID != nil {
		session.ReconnectTokenSteamID = strconv.FormatInt(*reconnectTokenSteamID, 10)
	}
	session.ReconnectTokenExpireAt = reconnectTokenExpireAt

	rows, err := r.pool.Query(ctx, `
		SELECT steam_id, char_id, member_state, last_seen_at, reconnect_deadline_at
		FROM run_session_members
		WHERE run_id = $1
		ORDER BY slot_no ASC
	`, runID)
	if err != nil {
		return RunSession{}, err
	}
	defer rows.Close()

	party := make([]RunMember, 0, 4)
	for rows.Next() {
		var steamInt int64
		var member RunMember
		var memberState int16
		var lastSeenAt *time.Time
		var reconnectDeadlineAt *time.Time
		if err := rows.Scan(&steamInt, &member.CharID, &memberState, &lastSeenAt, &reconnectDeadlineAt); err != nil {
			return RunSession{}, err
		}
		member.SteamID = strconv.FormatInt(steamInt, 10)
		member.State = memberStateFromDB(memberState)
		member.LastSeenAt = lastSeenAt
		member.ReconnectDeadlineAt = reconnectDeadlineAt
		party = append(party, member)
	}
	if rows.Err() != nil {
		return RunSession{}, rows.Err()
	}
	session.Party = party
	return session, nil
}

func (r *PostgresRepository) ListRunsByPlayer(ctx context.Context, steamID string, input ListRunsInput) ([]RunHistoryItem, int, error) {
	steamInt, err := strconv.ParseInt(steamID, 10, 64)
	if err != nil {
		return nil, 0, ErrInvalidArgument
	}

	where := []string{"rsm.steam_id = $1"}
	args := []any{steamInt}
	argPos := 2

	if input.Mode != "" {
		where = append(where, fmt.Sprintf("rs.mode = $%d", argPos))
		args = append(args, input.Mode)
		argPos++
	}
	if input.Status != "" {
		where = append(where, fmt.Sprintf("rs.status = $%d", argPos))
		args = append(args, statusToDB(RunStatus(input.Status)))
		argPos++
	}
	if input.Verdict != "" {
		where = append(where, fmt.Sprintf("rr.verdict = $%d", argPos))
		args = append(args, verdictToDB(input.Verdict))
		argPos++
	}
	if input.RewardStatus != "" {
		where = append(where, fmt.Sprintf("rr.reward_status = $%d", argPos))
		args = append(args, rewardStatusToDB(input.RewardStatus))
		argPos++
	}

	orderDir := "DESC"
	if strings.EqualFold(input.Order, "asc") {
		orderDir = "ASC"
	}

	limitPos := argPos
	args = append(args, input.Limit)
	argPos++
	offsetPos := argPos
	args = append(args, input.Offset)

	query := fmt.Sprintf(`
		SELECT
			rs.run_id,
			rs.mode,
			rs.difficulty,
			rs.region,
			rs.status,
			rs.host_steam_id,
			rs.started_at,
			rs.ended_at,
			ps.party_size,
			(rr.run_id IS NOT NULL) AS has_result,
			COALESCE(rr.risk_score, 0) AS risk_score,
			COALESCE(rr.verdict, 0) AS verdict,
			COALESCE(rr.reward_status, 0) AS reward_status,
			COALESCE(rr.created_at, rs.started_at) AS submitted_at,
			COUNT(1) OVER() AS total_count
		FROM run_sessions rs
		JOIN run_session_members rsm ON rsm.run_id = rs.run_id
		LEFT JOIN run_results rr ON rr.run_id = rs.run_id
		LEFT JOIN LATERAL (
			SELECT COUNT(1)::int AS party_size
			FROM run_session_members m
			WHERE m.run_id = rs.run_id
		) ps ON TRUE
		WHERE %s
		ORDER BY rs.started_at %s, rs.run_id %s
		LIMIT $%d OFFSET $%d
	`, strings.Join(where, " AND "), orderDir, orderDir, limitPos, offsetPos)

	rows, err := r.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	items := make([]RunHistoryItem, 0, input.Limit)
	total := 0
	for rows.Next() {
		var (
			runID          uuid.UUID
			mode           string
			difficulty     int
			region         string
			statusDB       int16
			hostSteamID    int64
			startedAt      time.Time
			endedAt        *time.Time
			partySize      int
			hasResult      bool
			riskScore      int
			verdictDB      int16
			rewardStatusDB int16
			submittedAt    time.Time
			totalCount     int
		)
		if err := rows.Scan(
			&runID,
			&mode,
			&difficulty,
			&region,
			&statusDB,
			&hostSteamID,
			&startedAt,
			&endedAt,
			&partySize,
			&hasResult,
			&riskScore,
			&verdictDB,
			&rewardStatusDB,
			&submittedAt,
			&totalCount,
		); err != nil {
			return nil, 0, err
		}
		total = totalCount

		item := RunHistoryItem{
			RunID:      runID.String(),
			Mode:       mode,
			Difficulty: difficulty,
			Region:     region,
			Status:     statusFromDB(statusDB),
			PartySize:  partySize,
			IsHost:     strconv.FormatInt(hostSteamID, 10) == steamID,
			StartedAt:  startedAt,
			EndedAt:    endedAt,
		}
		if hasResult {
			item.Verdict = verdictFromDB(verdictDB)
			item.RewardStatus = rewardStatusFromDB(rewardStatusDB)
			riskScoreCopy := riskScore
			item.RiskScore = &riskScoreCopy
			submittedAtCopy := submittedAt
			item.SubmittedAt = &submittedAtCopy
		}
		items = append(items, item)
	}
	if rows.Err() != nil {
		return nil, 0, rows.Err()
	}

	return items, total, nil
}

func (r *PostgresRepository) AbortExpiredRuns(ctx context.Context, now time.Time, migrationWindow time.Duration) ([]RunSession, error) {
	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	changedRuns := make([]RunSession, 0)
	migrationDeadline := now.Add(migrationWindow)

	promotedRows, err := tx.Query(ctx, `
		UPDATE run_sessions
		SET status = $2,
		    host_migration_deadline_at = $3,
		    migration_epoch = migration_epoch + 1,
		    reconnect_token_hash = NULL,
		    reconnect_token_steam_id = NULL,
		    reconnect_token_expire_at = NULL
		WHERE status = 0
		  AND host_reconnect_deadline_at IS NOT NULL
		  AND host_reconnect_deadline_at < $1
		RETURNING run_id, host_user_id, host_steam_id, started_at, ended_at, host_reconnect_deadline_at, host_migration_deadline_at, migration_epoch, status
	`, now, statusToDB(RunStatusHostMigrationWait), migrationDeadline)
	if err != nil {
		return nil, err
	}
	promoted, err := scanSweepChangedRuns(promotedRows)
	if err != nil {
		return nil, err
	}
	changedRuns = append(changedRuns, promoted...)

	abortedRows, err := tx.Query(ctx, `
		UPDATE run_sessions
		SET status = $2, ended_at = $1
		WHERE status = $3
		  AND host_migration_deadline_at IS NOT NULL
		  AND host_migration_deadline_at < $1
		RETURNING run_id, host_user_id, host_steam_id, started_at, ended_at, host_reconnect_deadline_at, host_migration_deadline_at, migration_epoch, status
	`, now, statusToDB(RunStatusAborted), statusToDB(RunStatusHostMigrationWait))
	if err != nil {
		return nil, err
	}
	aborted, err := scanSweepChangedRuns(abortedRows)
	if err != nil {
		return nil, err
	}
	changedRuns = append(changedRuns, aborted...)

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return changedRuns, nil
}

func (r *PostgresRepository) AbortExpiredRunsByHost(ctx context.Context, hostSteamID string, now time.Time, migrationWindow time.Duration) ([]RunSession, error) {
	hostSteamInt, err := strconv.ParseInt(hostSteamID, 10, 64)
	if err != nil {
		return nil, ErrInvalidArgument
	}

	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	changedRuns := make([]RunSession, 0)
	migrationDeadline := now.Add(migrationWindow)

	promotedRows, err := tx.Query(ctx, `
		UPDATE run_sessions
		SET status = $2,
		    host_migration_deadline_at = $4,
		    migration_epoch = migration_epoch + 1,
		    reconnect_token_hash = NULL,
		    reconnect_token_steam_id = NULL,
		    reconnect_token_expire_at = NULL
		WHERE host_steam_id = $1
		  AND status = 0
		  AND host_reconnect_deadline_at IS NOT NULL
		  AND host_reconnect_deadline_at < $3
		RETURNING run_id, host_user_id, host_steam_id, started_at, ended_at, host_reconnect_deadline_at, host_migration_deadline_at, migration_epoch, status
	`, hostSteamInt, statusToDB(RunStatusHostMigrationWait), now, migrationDeadline)
	if err != nil {
		return nil, err
	}
	promoted, err := scanSweepChangedRuns(promotedRows)
	if err != nil {
		return nil, err
	}
	changedRuns = append(changedRuns, promoted...)

	abortedRows, err := tx.Query(ctx, `
		UPDATE run_sessions
		SET status = $3, ended_at = $2
		WHERE host_steam_id = $1
		  AND status = $4
		  AND host_migration_deadline_at IS NOT NULL
		  AND host_migration_deadline_at < $2
		RETURNING run_id, host_user_id, host_steam_id, started_at, ended_at, host_reconnect_deadline_at, host_migration_deadline_at, migration_epoch, status
	`, hostSteamInt, now, statusToDB(RunStatusAborted), statusToDB(RunStatusHostMigrationWait))
	if err != nil {
		return nil, err
	}
	aborted, err := scanSweepChangedRuns(abortedRows)
	if err != nil {
		return nil, err
	}
	changedRuns = append(changedRuns, aborted...)

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return changedRuns, nil
}

func (r *PostgresRepository) PromoteRunToMigrationWait(ctx context.Context, runID uuid.UUID, now time.Time, migrationWindow time.Duration) (RunSession, error) {
	migrationDeadline := now.Add(migrationWindow)

	cmd, err := r.pool.Exec(ctx, `
		UPDATE run_sessions
		SET status = $2,
		    host_migration_deadline_at = $3,
		    migration_epoch = migration_epoch + 1,
		    reconnect_token_hash = NULL,
		    reconnect_token_steam_id = NULL,
		    reconnect_token_expire_at = NULL
		WHERE run_id = $1
		  AND status = 0
		  AND host_reconnect_deadline_at IS NOT NULL
		  AND host_reconnect_deadline_at < $4
	`, runID, statusToDB(RunStatusHostMigrationWait), migrationDeadline, now)
	if err != nil {
		return RunSession{}, err
	}
	if cmd.RowsAffected() == 0 {
		return r.GetRun(ctx, runID)
	}
	return r.GetRun(ctx, runID)
}

func scanSweepChangedRuns(rows pgx.Rows) ([]RunSession, error) {
	defer rows.Close()

	changedRuns := make([]RunSession, 0)
	for rows.Next() {
		var (
			runID                 uuid.UUID
			hostUserID            int64
			hostSteamID           int64
			startedAt             time.Time
			endedAt               *time.Time
			hostReconnectDeadline *time.Time
			hostMigrationDeadline *time.Time
			migrationEpoch        int64
			statusDB              int16
		)
		if err := rows.Scan(
			&runID,
			&hostUserID,
			&hostSteamID,
			&startedAt,
			&endedAt,
			&hostReconnectDeadline,
			&hostMigrationDeadline,
			&migrationEpoch,
			&statusDB,
		); err != nil {
			return nil, err
		}
		changedRuns = append(changedRuns, RunSession{
			RunID:                   runID,
			HostUserID:              hostUserID,
			HostSteamID:             strconv.FormatInt(hostSteamID, 10),
			Status:                  statusFromDB(statusDB),
			StartedAt:               startedAt,
			EndedAt:                 endedAt,
			HostReconnectDeadlineAt: hostReconnectDeadline,
			HostMigrationDeadlineAt: hostMigrationDeadline,
			MigrationEpoch:          migrationEpoch,
		})
	}
	if rows.Err() != nil {
		return nil, rows.Err()
	}
	return changedRuns, nil
}

func (r *PostgresRepository) UpdateRunHeartbeat(ctx context.Context, runID uuid.UUID, hostSteamID string, onlineSteamIDs []string, hostReconnectWindow time.Duration, playerReconnectWindow time.Duration, hostMigrationWindow time.Duration, now time.Time) (RunSession, error) {
	hostSteamInt, err := strconv.ParseInt(hostSteamID, 10, 64)
	if err != nil {
		return RunSession{}, ErrInvalidArgument
	}

	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return RunSession{}, err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	var (
		statusDB                int16
		dbHostSteamID           int64
		hostReconnectDeadlineAt *time.Time
	)
	if err := tx.QueryRow(ctx, `
		SELECT status, host_steam_id, host_reconnect_deadline_at
		FROM run_sessions
		WHERE run_id = $1
		FOR UPDATE
	`, runID).Scan(&statusDB, &dbHostSteamID, &hostReconnectDeadlineAt); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return RunSession{}, errRecordNotFound
		}
		return RunSession{}, err
	}

	if dbHostSteamID != hostSteamInt {
		return RunSession{}, ErrForbidden
	}
	if statusFromDB(statusDB) != RunStatusRunning {
		return RunSession{}, ErrRunAlreadyFinalized
	}
	if hostReconnectDeadlineAt != nil && hostReconnectDeadlineAt.Before(now) {
		if _, err := tx.Exec(ctx, `
			UPDATE run_sessions
			SET status = $2,
			    host_migration_deadline_at = $4,
			    migration_epoch = migration_epoch + 1,
			    reconnect_token_hash = NULL,
			    reconnect_token_steam_id = NULL,
			    reconnect_token_expire_at = NULL
			WHERE run_id = $1
		`, runID, statusToDB(RunStatusHostMigrationWait), now, now.Add(hostMigrationWindow)); err != nil {
			return RunSession{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return RunSession{}, err
		}
		return RunSession{}, ErrRunAlreadyFinalized
	}

	hostDeadline := now.Add(hostReconnectWindow)
	if _, err := tx.Exec(ctx, `
		UPDATE run_sessions
		SET host_last_heartbeat_at = $2, host_reconnect_deadline_at = $3, host_migration_deadline_at = NULL
		WHERE run_id = $1
	`, runID, now, hostDeadline); err != nil {
		return RunSession{}, err
	}

	onlineSet := make(map[int64]struct{}, len(onlineSteamIDs)+1)
	onlineSet[hostSteamInt] = struct{}{}
	for _, steamID := range onlineSteamIDs {
		steamInt, parseErr := strconv.ParseInt(steamID, 10, 64)
		if parseErr != nil {
			return RunSession{}, ErrInvalidArgument
		}
		onlineSet[steamInt] = struct{}{}
	}

	rows, err := tx.Query(ctx, `
		SELECT steam_id, member_state, reconnect_deadline_at
		FROM run_session_members
		WHERE run_id = $1
		FOR UPDATE
	`, runID)
	if err != nil {
		return RunSession{}, err
	}
	defer rows.Close()

	type memberRow struct {
		steamID             int64
		memberState         int16
		reconnectDeadlineAt *time.Time
	}
	memberRows := make([]memberRow, 0, 4)
	for rows.Next() {
		var row memberRow
		if err := rows.Scan(&row.steamID, &row.memberState, &row.reconnectDeadlineAt); err != nil {
			return RunSession{}, err
		}
		memberRows = append(memberRows, row)
	}
	if rows.Err() != nil {
		return RunSession{}, rows.Err()
	}
	rows.Close()

	for _, row := range memberRows {
		_, online := onlineSet[row.steamID]

		nextState := memberStateFromDB(row.memberState)
		var nextDeadline *time.Time
		var nextLastSeenAt *time.Time
		if online {
			nextState = RunMemberStateOnline
			seen := now
			nextLastSeenAt = &seen
		} else {
			switch nextState {
			case "", RunMemberStateOnline:
				nextState = RunMemberStateReconnecting
				deadline := now.Add(playerReconnectWindow)
				nextDeadline = &deadline
			case RunMemberStateReconnecting:
				if row.reconnectDeadlineAt != nil {
					if row.reconnectDeadlineAt.Before(now) {
						nextState = RunMemberStateTimedOut
					} else {
						deadline := *row.reconnectDeadlineAt
						nextDeadline = &deadline
					}
				} else {
					deadline := now.Add(playerReconnectWindow)
					nextDeadline = &deadline
				}
			case RunMemberStateTimedOut:
				// keep timed_out until back online
			}
		}

		if _, err := tx.Exec(ctx, `
			UPDATE run_session_members
			SET member_state = $3,
			    last_seen_at = COALESCE($4, last_seen_at),
			    reconnect_deadline_at = $5
			WHERE run_id = $1 AND steam_id = $2
		`, runID, row.steamID, memberStateToDB(nextState), nextLastSeenAt, nextDeadline); err != nil {
			return RunSession{}, err
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return RunSession{}, err
	}

	return r.GetRun(ctx, runID)
}

func (r *PostgresRepository) SaveReconnectToken(ctx context.Context, runID uuid.UUID, steamID string, tokenHash string, expireAt time.Time) error {
	steamInt, err := strconv.ParseInt(steamID, 10, 64)
	if err != nil {
		return ErrInvalidArgument
	}

	cmd, err := r.pool.Exec(ctx, `
		UPDATE run_sessions
		SET reconnect_token_hash = $2,
		    reconnect_token_steam_id = $3,
		    reconnect_token_expire_at = $4
		WHERE run_id = $1
		  AND status IN (0,4)
		  AND EXISTS (
			  SELECT 1
			  FROM run_session_members m
			  WHERE m.run_id = $1 AND m.steam_id = $3
		  )
	`, runID, tokenHash, steamInt, expireAt)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		var (
			statusDB int16
			isMember bool
		)
		if err := r.pool.QueryRow(ctx, `
			SELECT rs.status,
			       EXISTS (
				       SELECT 1
				       FROM run_session_members m
				       WHERE m.run_id = rs.run_id AND m.steam_id = $2
			       ) AS is_member
			FROM run_sessions rs
			WHERE rs.run_id = $1
		`, runID, steamInt).Scan(&statusDB, &isMember); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return errRecordNotFound
			}
			return err
		}
		if !isMember {
			return ErrForbidden
		}
		status := statusFromDB(statusDB)
		if status != RunStatusRunning && status != RunStatusHostMigrationWait {
			return ErrRunAlreadyFinalized
		}
		return errRecordNotFound
	}
	return nil
}

func (r *PostgresRepository) ConfirmReconnect(ctx context.Context, runID uuid.UUID, steamID string, tokenHash string, hostReconnectWindow time.Duration, _ time.Duration, hostMigrationWindow time.Duration, now time.Time) (RunSession, error) {
	steamInt, err := strconv.ParseInt(steamID, 10, 64)
	if err != nil {
		return RunSession{}, ErrInvalidArgument
	}

	tx, err := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return RunSession{}, err
	}
	defer func() {
		_ = tx.Rollback(ctx)
	}()

	var (
		statusDB                int16
		hostSteamID             int64
		hostReconnectDeadlineAt *time.Time
		hostMigrationDeadlineAt *time.Time
		tokenHashDB             *string
		tokenSteamIDDB          *int64
		tokenExpireAtDB         *time.Time
	)
	if err := tx.QueryRow(ctx, `
		SELECT status, host_steam_id, host_reconnect_deadline_at, host_migration_deadline_at,
		       reconnect_token_hash, reconnect_token_steam_id, reconnect_token_expire_at
		FROM run_sessions
		WHERE run_id = $1
		FOR UPDATE
	`, runID).Scan(
		&statusDB,
		&hostSteamID,
		&hostReconnectDeadlineAt,
		&hostMigrationDeadlineAt,
		&tokenHashDB,
		&tokenSteamIDDB,
		&tokenExpireAtDB,
	); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return RunSession{}, errRecordNotFound
		}
		return RunSession{}, err
	}

	status := statusFromDB(statusDB)
	if status != RunStatusRunning && status != RunStatusHostMigrationWait {
		return RunSession{}, ErrRunAlreadyFinalized
	}
	if status == RunStatusRunning && hostReconnectDeadlineAt != nil && hostReconnectDeadlineAt.Before(now) {
		if _, err := tx.Exec(ctx, `
			UPDATE run_sessions
			SET status = $2,
			    host_migration_deadline_at = $3,
			    migration_epoch = migration_epoch + 1,
			    reconnect_token_hash = NULL,
			    reconnect_token_steam_id = NULL,
			    reconnect_token_expire_at = NULL
			WHERE run_id = $1
		`, runID, statusToDB(RunStatusHostMigrationWait), now.Add(hostMigrationWindow)); err != nil {
			return RunSession{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return RunSession{}, err
		}
		return RunSession{}, ErrRunAlreadyFinalized
	}
	if status == RunStatusHostMigrationWait && hostMigrationDeadlineAt != nil && hostMigrationDeadlineAt.Before(now) {
		if _, err := tx.Exec(ctx, `
			UPDATE run_sessions
			SET status = $2, ended_at = $3,
			    reconnect_token_hash = NULL,
			    reconnect_token_steam_id = NULL,
			    reconnect_token_expire_at = NULL
			WHERE run_id = $1
		`, runID, statusToDB(RunStatusAborted), now); err != nil {
			return RunSession{}, err
		}
		if err := tx.Commit(ctx); err != nil {
			return RunSession{}, err
		}
		return RunSession{}, ErrReconnectWindowExpired
	}

	if tokenHashDB == nil || tokenSteamIDDB == nil || tokenExpireAtDB == nil {
		return RunSession{}, ErrReconnectTokenInvalid
	}
	if *tokenHashDB != tokenHash || *tokenSteamIDDB != steamInt || !tokenExpireAtDB.After(now) {
		return RunSession{}, ErrReconnectTokenInvalid
	}

	if status == RunStatusHostMigrationWait {
		hostDeadline := now.Add(hostReconnectWindow)
		if _, err := tx.Exec(ctx, `
			UPDATE run_sessions
			SET host_steam_id = $2,
			    status = $3,
			    host_last_heartbeat_at = $4,
			    host_reconnect_deadline_at = $5,
			    host_migration_deadline_at = NULL,
			    reconnect_token_hash = NULL,
			    reconnect_token_steam_id = NULL,
			    reconnect_token_expire_at = NULL
			WHERE run_id = $1
		`, runID, steamInt, statusToDB(RunStatusRunning), now, hostDeadline); err != nil {
			return RunSession{}, err
		}
	} else if hostSteamID == steamInt {
		hostDeadline := now.Add(hostReconnectWindow)
		if _, err := tx.Exec(ctx, `
			UPDATE run_sessions
			SET host_last_heartbeat_at = $2,
			    host_reconnect_deadline_at = $3,
			    host_migration_deadline_at = NULL,
			    reconnect_token_hash = NULL,
			    reconnect_token_steam_id = NULL,
			    reconnect_token_expire_at = NULL
			WHERE run_id = $1
		`, runID, now, hostDeadline); err != nil {
			return RunSession{}, err
		}
	} else {
		var (
			memberStateDB       int16
			reconnectDeadlineAt *time.Time
		)
		if err := tx.QueryRow(ctx, `
			SELECT member_state, reconnect_deadline_at
			FROM run_session_members
			WHERE run_id = $1 AND steam_id = $2
			FOR UPDATE
		`, runID, steamInt).Scan(&memberStateDB, &reconnectDeadlineAt); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return RunSession{}, ErrForbidden
			}
			return RunSession{}, err
		}
		if memberStateFromDB(memberStateDB) == RunMemberStateTimedOut {
			return RunSession{}, ErrReconnectWindowExpired
		}
		if reconnectDeadlineAt != nil && reconnectDeadlineAt.Before(now) {
			return RunSession{}, ErrReconnectWindowExpired
		}

		if _, err := tx.Exec(ctx, `
			UPDATE run_sessions
			SET reconnect_token_hash = NULL,
			    reconnect_token_steam_id = NULL,
			    reconnect_token_expire_at = NULL
			WHERE run_id = $1
		`, runID); err != nil {
			return RunSession{}, err
		}
	}

	cmd, err := tx.Exec(ctx, `
		UPDATE run_session_members
		SET member_state = 0,
		    last_seen_at = $3,
		    reconnect_deadline_at = NULL
		WHERE run_id = $1 AND steam_id = $2
	`, runID, steamInt, now)
	if err != nil {
		return RunSession{}, err
	}
	if cmd.RowsAffected() == 0 {
		return RunSession{}, ErrForbidden
	}

	if err := tx.Commit(ctx); err != nil {
		return RunSession{}, err
	}

	return r.GetRun(ctx, runID)
}

func (r *PostgresRepository) GetActiveRunCountByHost(ctx context.Context, hostSteamID string) (int, error) {
	hostSteamInt, err := strconv.ParseInt(hostSteamID, 10, 64)
	if err != nil {
		return 0, ErrInvalidArgument
	}

	var count int
	err = r.pool.QueryRow(ctx, `
		SELECT COUNT(1)
		FROM run_sessions
		WHERE host_steam_id = $1 AND status IN (0,4)
	`, hostSteamInt).Scan(&count)
	if err != nil {
		return 0, err
	}
	return count, nil
}

func (r *PostgresRepository) SaveRunResult(ctx context.Context, result StoredRunResult) error {
	submittedSteamID, err := strconv.ParseInt(result.SubmittedBySteamID, 10, 64)
	if err != nil {
		return ErrInvalidArgument
	}

	proofPayload, err := json.Marshal(result.Payload.Proof)
	if err != nil {
		return err
	}
	resultPayload, err := json.Marshal(result.Payload)
	if err != nil {
		return err
	}
	riskReasonsPayload, err := json.Marshal(result.RiskReasons)
	if err != nil {
		return err
	}

	_, err = r.pool.Exec(ctx, `
		INSERT INTO run_results (
			run_id, submitted_by_steam_id, clear_time_sec, rooms_cleared, team_score, deaths,
			proof_payload, result_payload, risk_reasons, risk_score, verdict, reward_status, created_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9::jsonb, $10, $11, $12, $13)
		ON CONFLICT (run_id)
		DO UPDATE SET
			submitted_by_steam_id = EXCLUDED.submitted_by_steam_id,
			clear_time_sec = EXCLUDED.clear_time_sec,
			rooms_cleared = EXCLUDED.rooms_cleared,
			team_score = EXCLUDED.team_score,
			deaths = EXCLUDED.deaths,
			proof_payload = EXCLUDED.proof_payload,
			result_payload = EXCLUDED.result_payload,
			risk_reasons = EXCLUDED.risk_reasons,
			risk_score = EXCLUDED.risk_score,
			verdict = EXCLUDED.verdict,
			reward_status = EXCLUDED.reward_status,
			created_at = EXCLUDED.created_at
	`, result.RunID, submittedSteamID, result.Payload.Final.ClearTimeSec, result.Payload.Final.RoomsCleared, result.Payload.Final.TeamScore, result.Payload.Final.Deaths, proofPayload, resultPayload, riskReasonsPayload, result.RiskScore, verdictToDB(result.Verdict), rewardStatusToDB(result.RewardStatus), result.CreatedAt)
	return err
}

func (r *PostgresRepository) GetRunResult(ctx context.Context, runID uuid.UUID) (StoredRunResult, error) {
	var (
		submittedSteamID int64
		riskScore        int
		verdictDB        int16
		rewardStatusDB   int16
		resultPayloadRaw []byte
		riskReasonsRaw   []byte
		createdAt        time.Time
	)
	err := r.pool.QueryRow(ctx, `
		SELECT submitted_by_steam_id, risk_score, verdict, reward_status, result_payload, risk_reasons, created_at
		FROM run_results
		WHERE run_id = $1
	`, runID).Scan(&submittedSteamID, &riskScore, &verdictDB, &rewardStatusDB, &resultPayloadRaw, &riskReasonsRaw, &createdAt)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return StoredRunResult{}, errRecordNotFound
		}
		return StoredRunResult{}, err
	}

	var payload FinishRunInput
	if len(resultPayloadRaw) > 0 {
		if err := json.Unmarshal(resultPayloadRaw, &payload); err != nil {
			return StoredRunResult{}, err
		}
	}
	riskReasons := []string{}
	if len(riskReasonsRaw) > 0 {
		if err := json.Unmarshal(riskReasonsRaw, &riskReasons); err != nil {
			return StoredRunResult{}, err
		}
	}

	verdict := verdictFromDB(verdictDB)
	return StoredRunResult{
		RunID:              runID,
		SubmittedBySteamID: strconv.FormatInt(submittedSteamID, 10),
		RiskScore:          riskScore,
		RiskReasons:        riskReasons,
		Verdict:            verdict,
		RewardStatus:       rewardStatusFromDB(rewardStatusDB),
		Payload:            payload,
		CreatedAt:          createdAt,
	}, nil
}

func (r *PostgresRepository) UpdateRunRewardStatus(ctx context.Context, runID uuid.UUID, rewardStatus string, reviewedAt time.Time) error {
	cmd, err := r.pool.Exec(ctx, `
		UPDATE run_results
		SET reward_status = $2, reviewed_at = $3
		WHERE run_id = $1
	`, runID, rewardStatusToDB(rewardStatus), reviewedAt)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return errRecordNotFound
	}
	return nil
}

func (r *PostgresRepository) UpdateRunStatus(ctx context.Context, runID uuid.UUID, status RunStatus, endedAt time.Time) error {
	cmd, err := r.pool.Exec(ctx, `
		UPDATE run_sessions
		SET status = $2, ended_at = $3
		WHERE run_id = $1
	`, runID, statusToDB(status), endedAt)
	if err != nil {
		return err
	}
	if cmd.RowsAffected() == 0 {
		return errRecordNotFound
	}
	return nil
}

func nullIfEmpty(value string) any {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return value
}

func nullSteamInt64(steamID string) any {
	trimmed := strings.TrimSpace(steamID)
	if trimmed == "" {
		return nil
	}
	parsed, err := strconv.ParseInt(trimmed, 10, 64)
	if err != nil {
		return nil
	}
	return parsed
}

func statusToDB(status RunStatus) int16 {
	switch status {
	case RunStatusRunning:
		return 0
	case RunStatusHostMigrationWait:
		return 4
	case RunStatusCompleted:
		return 1
	case RunStatusAborted:
		return 2
	default:
		return 3
	}
}

func statusFromDB(status int16) RunStatus {
	switch status {
	case 0:
		return RunStatusRunning
	case 4:
		return RunStatusHostMigrationWait
	case 1:
		return RunStatusCompleted
	case 2:
		return RunStatusAborted
	default:
		return RunStatusInvalid
	}
}

func memberStateToDB(state string) int16 {
	switch state {
	case RunMemberStateReconnecting:
		return 1
	case RunMemberStateTimedOut:
		return 2
	default:
		return 0
	}
}

func memberStateFromDB(state int16) string {
	switch state {
	case 1:
		return RunMemberStateReconnecting
	case 2:
		return RunMemberStateTimedOut
	default:
		return RunMemberStateOnline
	}
}

func verdictToDB(verdict string) int16 {
	switch verdict {
	case VerdictAccepted:
		return 1
	case VerdictRejected:
		return 2
	default:
		return 0
	}
}

func verdictFromDB(verdict int16) string {
	switch verdict {
	case 1:
		return VerdictAccepted
	case 2:
		return VerdictRejected
	default:
		return VerdictPendingReview
	}
}

func rewardStatusToDB(status string) int16 {
	switch status {
	case RewardStatusGranted:
		return 1
	case RewardStatusDenied:
		return 3
	default:
		return 2
	}
}

func rewardStatusFromDB(status int16) string {
	switch status {
	case 1:
		return RewardStatusGranted
	case 3:
		return RewardStatusDenied
	default:
		return RewardStatusDelayed
	}
}
