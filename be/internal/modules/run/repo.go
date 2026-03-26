package run

import (
	"context"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

var errRecordNotFound = errors.New("record not found")

type Repository interface {
	CreateRun(ctx context.Context, session RunSession) error
	GetRun(ctx context.Context, runID uuid.UUID) (RunSession, error)
	ListRunsByPlayer(ctx context.Context, steamID string, input ListRunsInput) ([]RunHistoryItem, int, error)
	AbortExpiredRuns(ctx context.Context, now time.Time, migrationWindow time.Duration) ([]RunSession, error)
	AbortExpiredRunsByHost(ctx context.Context, hostSteamID string, now time.Time, migrationWindow time.Duration) ([]RunSession, error)
	PromoteRunToMigrationWait(ctx context.Context, runID uuid.UUID, now time.Time, migrationWindow time.Duration) (RunSession, error)
	UpdateRunHeartbeat(ctx context.Context, runID uuid.UUID, hostSteamID string, onlineSteamIDs []string, hostReconnectWindow time.Duration, playerReconnectWindow time.Duration, hostMigrationWindow time.Duration, now time.Time) (RunSession, error)
	SaveReconnectToken(ctx context.Context, runID uuid.UUID, steamID string, tokenHash string, expireAt time.Time) error
	ConfirmReconnect(ctx context.Context, runID uuid.UUID, steamID string, tokenHash string, hostReconnectWindow time.Duration, playerReconnectWindow time.Duration, hostMigrationWindow time.Duration, now time.Time) (RunSession, error)
	GetActiveRunCountByHost(ctx context.Context, hostSteamID string) (int, error)
	SaveRunResult(ctx context.Context, result StoredRunResult) error
	GetRunResult(ctx context.Context, runID uuid.UUID) (StoredRunResult, error)
	UpdateRunRewardStatus(ctx context.Context, runID uuid.UUID, rewardStatus string, reviewedAt time.Time) error
	UpdateRunStatus(ctx context.Context, runID uuid.UUID, status RunStatus, endedAt time.Time) error
}

type IdempotencyStore interface {
	Get(ctx context.Context, key string) (*IdempotencyRecord, error)
	Put(ctx context.Context, record IdempotencyRecord) error
}

type MemoryRepository struct {
	mu      sync.RWMutex
	runs    map[uuid.UUID]RunSession
	results map[uuid.UUID]StoredRunResult
}

func NewMemoryRepository() *MemoryRepository {
	return &MemoryRepository{
		runs:    make(map[uuid.UUID]RunSession),
		results: make(map[uuid.UUID]StoredRunResult),
	}
}

func (r *MemoryRepository) CreateRun(_ context.Context, session RunSession) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	if _, exists := r.runs[session.RunID]; exists {
		return ErrConflict
	}

	r.runs[session.RunID] = session
	return nil
}

func (r *MemoryRepository) GetRun(_ context.Context, runID uuid.UUID) (RunSession, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	run, ok := r.runs[runID]
	if !ok {
		return RunSession{}, errRecordNotFound
	}
	return cloneRunSession(run), nil
}

func (r *MemoryRepository) ListRunsByPlayer(_ context.Context, steamID string, input ListRunsInput) ([]RunHistoryItem, int, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	items := make([]RunHistoryItem, 0, len(r.runs))
	for _, run := range r.runs {
		if !runContainsSteamID(run.Party, steamID) {
			continue
		}
		if input.Mode != "" && run.Mode != input.Mode {
			continue
		}
		if input.Status != "" && run.Status != RunStatus(input.Status) {
			continue
		}

		result, hasResult := r.results[run.RunID]
		if input.Verdict != "" {
			if !hasResult || result.Verdict != input.Verdict {
				continue
			}
		}
		if input.RewardStatus != "" {
			if !hasResult || result.RewardStatus != input.RewardStatus {
				continue
			}
		}

		item := RunHistoryItem{
			RunID:      run.RunID.String(),
			Mode:       run.Mode,
			Difficulty: run.Difficulty,
			Region:     run.Region,
			Status:     run.Status,
			PartySize:  len(run.Party),
			IsHost:     strings.EqualFold(run.HostSteamID, steamID),
			StartedAt:  run.StartedAt,
			EndedAt:    run.EndedAt,
		}
		if hasResult {
			item.Verdict = result.Verdict
			item.RewardStatus = result.RewardStatus
			riskScore := result.RiskScore
			item.RiskScore = &riskScore
			submittedAt := result.CreatedAt
			item.SubmittedAt = &submittedAt
		}
		items = append(items, item)
	}

	orderAsc := strings.EqualFold(input.Order, "asc")
	sort.Slice(items, func(i, j int) bool {
		if items[i].StartedAt.Equal(items[j].StartedAt) {
			if orderAsc {
				return items[i].RunID < items[j].RunID
			}
			return items[i].RunID > items[j].RunID
		}
		if orderAsc {
			return items[i].StartedAt.Before(items[j].StartedAt)
		}
		return items[i].StartedAt.After(items[j].StartedAt)
	})

	total := len(items)
	start := input.Offset
	if start > total {
		start = total
	}
	end := start + input.Limit
	if end > total {
		end = total
	}
	paged := make([]RunHistoryItem, 0, end-start)
	for _, item := range items[start:end] {
		paged = append(paged, item)
	}
	return paged, total, nil
}

func (r *MemoryRepository) AbortExpiredRunsByHost(_ context.Context, hostSteamID string, now time.Time, migrationWindow time.Duration) ([]RunSession, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	changedRuns := make([]RunSession, 0)
	for runID, run := range r.runs {
		if run.HostSteamID != hostSteamID {
			continue
		}

		switch run.Status {
		case RunStatusRunning:
			if run.HostReconnectDeadlineAt == nil || !run.HostReconnectDeadlineAt.Before(now) {
				continue
			}
			run.Status = RunStatusHostMigrationWait
			deadline := now.Add(migrationWindow)
			run.HostMigrationDeadlineAt = &deadline
			run.MigrationEpoch++
			run.ReconnectTokenHash = ""
			run.ReconnectTokenSteamID = ""
			run.ReconnectTokenExpireAt = nil
		case RunStatusHostMigrationWait:
			if run.HostMigrationDeadlineAt == nil || !run.HostMigrationDeadlineAt.Before(now) {
				continue
			}
			run.Status = RunStatusAborted
			endedAt := now
			run.EndedAt = &endedAt
		default:
			continue
		}
		r.runs[runID] = run
		changedRuns = append(changedRuns, cloneRunSession(run))
	}
	return changedRuns, nil
}

func (r *MemoryRepository) AbortExpiredRuns(_ context.Context, now time.Time, migrationWindow time.Duration) ([]RunSession, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	changedRuns := make([]RunSession, 0)
	for runID, run := range r.runs {
		switch run.Status {
		case RunStatusRunning:
			if run.HostReconnectDeadlineAt == nil || !run.HostReconnectDeadlineAt.Before(now) {
				continue
			}
			run.Status = RunStatusHostMigrationWait
			deadline := now.Add(migrationWindow)
			run.HostMigrationDeadlineAt = &deadline
			run.MigrationEpoch++
			run.ReconnectTokenHash = ""
			run.ReconnectTokenSteamID = ""
			run.ReconnectTokenExpireAt = nil
		case RunStatusHostMigrationWait:
			if run.HostMigrationDeadlineAt == nil || !run.HostMigrationDeadlineAt.Before(now) {
				continue
			}
			run.Status = RunStatusAborted
			endedAt := now
			run.EndedAt = &endedAt
		default:
			continue
		}
		r.runs[runID] = run
		changedRuns = append(changedRuns, cloneRunSession(run))
	}
	return changedRuns, nil
}

func (r *MemoryRepository) PromoteRunToMigrationWait(_ context.Context, runID uuid.UUID, now time.Time, migrationWindow time.Duration) (RunSession, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	run, ok := r.runs[runID]
	if !ok {
		return RunSession{}, errRecordNotFound
	}
	if run.Status != RunStatusRunning {
		return cloneRunSession(run), nil
	}
	if run.HostReconnectDeadlineAt == nil || !run.HostReconnectDeadlineAt.Before(now) {
		return cloneRunSession(run), nil
	}

	run.Status = RunStatusHostMigrationWait
	deadline := now.Add(migrationWindow)
	run.HostMigrationDeadlineAt = &deadline
	run.MigrationEpoch++
	run.ReconnectTokenHash = ""
	run.ReconnectTokenSteamID = ""
	run.ReconnectTokenExpireAt = nil
	r.runs[runID] = run
	return cloneRunSession(run), nil
}

func (r *MemoryRepository) UpdateRunHeartbeat(_ context.Context, runID uuid.UUID, hostSteamID string, onlineSteamIDs []string, hostReconnectWindow time.Duration, playerReconnectWindow time.Duration, hostMigrationWindow time.Duration, now time.Time) (RunSession, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	run, ok := r.runs[runID]
	if !ok {
		return RunSession{}, errRecordNotFound
	}
	if run.HostSteamID != hostSteamID {
		return RunSession{}, ErrForbidden
	}
	if run.Status != RunStatusRunning {
		return RunSession{}, ErrRunAlreadyFinalized
	}
	if run.HostReconnectDeadlineAt != nil && run.HostReconnectDeadlineAt.Before(now) {
		run.Status = RunStatusHostMigrationWait
		migrationDeadline := now.Add(hostMigrationWindow)
		run.HostMigrationDeadlineAt = &migrationDeadline
		run.MigrationEpoch++
		run.ReconnectTokenHash = ""
		run.ReconnectTokenSteamID = ""
		run.ReconnectTokenExpireAt = nil
		r.runs[runID] = run
		return RunSession{}, ErrRunAlreadyFinalized
	}

	onlineSet := make(map[string]struct{}, len(onlineSteamIDs)+1)
	for _, steamID := range onlineSteamIDs {
		onlineSet[steamID] = struct{}{}
	}
	onlineSet[hostSteamID] = struct{}{}

	hostSeen := now
	hostDeadline := now.Add(hostReconnectWindow)
	run.HostLastHeartbeatAt = &hostSeen
	run.HostReconnectDeadlineAt = &hostDeadline

	for idx := range run.Party {
		member := run.Party[idx]
		if _, online := onlineSet[member.SteamID]; online {
			member.State = RunMemberStateOnline
			seen := now
			member.LastSeenAt = &seen
			member.ReconnectDeadlineAt = nil
			run.Party[idx] = member
			continue
		}

		switch member.State {
		case "", RunMemberStateOnline:
			member.State = RunMemberStateReconnecting
			deadline := now.Add(playerReconnectWindow)
			member.ReconnectDeadlineAt = &deadline
		case RunMemberStateReconnecting:
			if member.ReconnectDeadlineAt != nil && member.ReconnectDeadlineAt.Before(now) {
				member.State = RunMemberStateTimedOut
			}
		case RunMemberStateTimedOut:
			// keep timed_out until explicitly back online.
		}
		run.Party[idx] = member
	}

	r.runs[runID] = run
	return cloneRunSession(run), nil
}

func (r *MemoryRepository) SaveReconnectToken(_ context.Context, runID uuid.UUID, steamID string, tokenHash string, expireAt time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	run, ok := r.runs[runID]
	if !ok {
		return errRecordNotFound
	}
	if run.Status != RunStatusRunning && run.Status != RunStatusHostMigrationWait {
		return ErrRunAlreadyFinalized
	}
	if !runContainsSteamID(run.Party, steamID) {
		return ErrForbidden
	}

	run.ReconnectTokenHash = tokenHash
	run.ReconnectTokenSteamID = steamID
	expireAtCopy := expireAt
	run.ReconnectTokenExpireAt = &expireAtCopy
	r.runs[runID] = run
	return nil
}

func (r *MemoryRepository) ConfirmReconnect(_ context.Context, runID uuid.UUID, steamID string, tokenHash string, hostReconnectWindow time.Duration, _ time.Duration, hostMigrationWindow time.Duration, now time.Time) (RunSession, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	run, ok := r.runs[runID]
	if !ok {
		return RunSession{}, errRecordNotFound
	}
	if run.Status != RunStatusRunning && run.Status != RunStatusHostMigrationWait {
		return RunSession{}, ErrRunAlreadyFinalized
	}
	if run.Status == RunStatusRunning && run.HostReconnectDeadlineAt != nil && run.HostReconnectDeadlineAt.Before(now) {
		run.Status = RunStatusHostMigrationWait
		migrationDeadline := now.Add(hostMigrationWindow)
		run.HostMigrationDeadlineAt = &migrationDeadline
		run.MigrationEpoch++
		run.ReconnectTokenHash = ""
		run.ReconnectTokenSteamID = ""
		run.ReconnectTokenExpireAt = nil
		r.runs[runID] = run
		return RunSession{}, ErrRunAlreadyFinalized
	}
	if run.Status == RunStatusHostMigrationWait && run.HostMigrationDeadlineAt != nil && run.HostMigrationDeadlineAt.Before(now) {
		run.Status = RunStatusAborted
		endedAt := now
		run.EndedAt = &endedAt
		r.runs[runID] = run
		return RunSession{}, ErrReconnectWindowExpired
	}
	if run.ReconnectTokenHash == "" || run.ReconnectTokenSteamID == "" || run.ReconnectTokenExpireAt == nil {
		return RunSession{}, ErrReconnectTokenInvalid
	}
	if run.ReconnectTokenHash != tokenHash || run.ReconnectTokenSteamID != steamID || !run.ReconnectTokenExpireAt.After(now) {
		return RunSession{}, ErrReconnectTokenInvalid
	}

	participantFound := false
	for idx := range run.Party {
		member := run.Party[idx]
		if member.SteamID != steamID {
			continue
		}
		participantFound = true
		if member.State == RunMemberStateTimedOut {
			return RunSession{}, ErrReconnectWindowExpired
		}
		if member.ReconnectDeadlineAt != nil && member.ReconnectDeadlineAt.Before(now) {
			return RunSession{}, ErrReconnectWindowExpired
		}
		member.State = RunMemberStateOnline
		seen := now
		member.LastSeenAt = &seen
		member.ReconnectDeadlineAt = nil
		run.Party[idx] = member
		break
	}
	if !participantFound {
		return RunSession{}, ErrForbidden
	}

	if run.Status == RunStatusHostMigrationWait {
		run.HostSteamID = steamID
		run.Status = RunStatusRunning
		run.HostMigrationDeadlineAt = nil
	} else if steamID == run.HostSteamID {
		hostSeen := now
		hostDeadline := now.Add(hostReconnectWindow)
		run.HostLastHeartbeatAt = &hostSeen
		run.HostReconnectDeadlineAt = &hostDeadline
	}
	hostSeen := now
	hostDeadline := now.Add(hostReconnectWindow)
	run.HostLastHeartbeatAt = &hostSeen
	run.HostReconnectDeadlineAt = &hostDeadline

	run.ReconnectTokenHash = ""
	run.ReconnectTokenSteamID = ""
	run.ReconnectTokenExpireAt = nil
	r.runs[runID] = run
	return cloneRunSession(run), nil
}

func (r *MemoryRepository) GetActiveRunCountByHost(_ context.Context, hostSteamID string) (int, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	count := 0
	for _, run := range r.runs {
		if run.HostSteamID == hostSteamID && (run.Status == RunStatusRunning || run.Status == RunStatusHostMigrationWait) {
			count++
		}
	}
	return count, nil
}

func runContainsSteamID(party []RunMember, steamID string) bool {
	for _, member := range party {
		if member.SteamID == steamID {
			return true
		}
	}
	return false
}

func cloneRunSession(run RunSession) RunSession {
	cloned := run

	if run.EndedAt != nil {
		endedAt := *run.EndedAt
		cloned.EndedAt = &endedAt
	}
	if run.HostLastHeartbeatAt != nil {
		hostSeen := *run.HostLastHeartbeatAt
		cloned.HostLastHeartbeatAt = &hostSeen
	}
	if run.HostReconnectDeadlineAt != nil {
		hostDeadline := *run.HostReconnectDeadlineAt
		cloned.HostReconnectDeadlineAt = &hostDeadline
	}
	if run.HostMigrationDeadlineAt != nil {
		migrationDeadline := *run.HostMigrationDeadlineAt
		cloned.HostMigrationDeadlineAt = &migrationDeadline
	}
	if run.ReconnectTokenExpireAt != nil {
		tokenExpireAt := *run.ReconnectTokenExpireAt
		cloned.ReconnectTokenExpireAt = &tokenExpireAt
	}

	party := make([]RunMember, 0, len(run.Party))
	for _, member := range run.Party {
		copied := member
		if member.LastSeenAt != nil {
			seen := *member.LastSeenAt
			copied.LastSeenAt = &seen
		}
		if member.ReconnectDeadlineAt != nil {
			deadline := *member.ReconnectDeadlineAt
			copied.ReconnectDeadlineAt = &deadline
		}
		party = append(party, copied)
	}
	cloned.Party = party

	return cloned
}

func (r *MemoryRepository) SaveRunResult(_ context.Context, result StoredRunResult) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	r.results[result.RunID] = result
	return nil
}

func (r *MemoryRepository) GetRunResult(_ context.Context, runID uuid.UUID) (StoredRunResult, error) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	result, ok := r.results[runID]
	if !ok {
		return StoredRunResult{}, errRecordNotFound
	}
	return result, nil
}

func (r *MemoryRepository) UpdateRunRewardStatus(_ context.Context, runID uuid.UUID, rewardStatus string, _ time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	result, ok := r.results[runID]
	if !ok {
		return errRecordNotFound
	}

	result.RewardStatus = rewardStatus
	r.results[runID] = result
	return nil
}

func (r *MemoryRepository) UpdateRunStatus(_ context.Context, runID uuid.UUID, status RunStatus, endedAt time.Time) error {
	r.mu.Lock()
	defer r.mu.Unlock()

	run, ok := r.runs[runID]
	if !ok {
		return errRecordNotFound
	}

	run.Status = status
	run.EndedAt = &endedAt
	r.runs[runID] = run
	return nil
}

type MemoryIdempotencyStore struct {
	mu      sync.RWMutex
	records map[string]IdempotencyRecord
}

func NewMemoryIdempotencyStore() *MemoryIdempotencyStore {
	return &MemoryIdempotencyStore{
		records: make(map[string]IdempotencyRecord),
	}
}

func (s *MemoryIdempotencyStore) Get(_ context.Context, key string) (*IdempotencyRecord, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	record, ok := s.records[key]
	if !ok {
		return nil, nil
	}

	copied := record
	return &copied, nil
}

func (s *MemoryIdempotencyStore) Put(_ context.Context, record IdempotencyRecord) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.records[record.Key] = record
	return nil
}
