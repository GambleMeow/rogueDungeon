package run

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"slices"
	"strings"
	"time"

	"github.com/google/uuid"
)

var (
	ErrInvalidArgument           = errors.New("INVALID_ARGUMENT")
	ErrUnauthorized              = errors.New("UNAUTHORIZED")
	ErrForbidden                 = errors.New("FORBIDDEN")
	ErrConflict                  = errors.New("CONFLICT")
	ErrInternal                  = errors.New("INTERNAL_ERROR")
	ErrRunNotFound               = errors.New("RUN_NOT_FOUND")
	ErrRunTokenInvalid           = errors.New("RUN_TOKEN_INVALID")
	ErrRunAlreadyFinalized       = errors.New("RUN_ALREADY_FINALIZED")
	ErrMemberSetMismatch         = errors.New("MEMBER_SET_MISMATCH")
	ErrProofInvalid              = errors.New("PROOF_INVALID")
	ErrIdempotencyReplayMismatch = errors.New("IDEMPOTENCY_REPLAY_MISMATCH")
	ErrReconnectTokenInvalid     = errors.New("RECONNECT_TOKEN_INVALID")
	ErrReconnectWindowExpired    = errors.New("RECONNECT_WINDOW_EXPIRED")
)

const (
	RiskReasonHostReconnectTimeout   = "R013_HOST_RECONNECT_TIMEOUT"
	RiskReasonReconnectTokenInvalid  = "R014_RECONNECT_TOKEN_INVALID"
	RiskReasonReconnectWindowExpired = "R015_RECONNECT_WINDOW_EXPIRED"
)

type RiskEngine interface {
	Score(ctx context.Context, run RunSession, req FinishRunInput) (int, []string, error)
}

type RewardService interface {
	GrantNow(ctx context.Context, actor UserRef, runID uuid.UUID, req FinishRunInput) error
	EnqueueRetry(ctx context.Context, actor UserRef, runID uuid.UUID, req FinishRunInput) error
	EnqueueReview(ctx context.Context, actor UserRef, runID uuid.UUID, req FinishRunInput) error
}

type RiskReport struct {
	UserID    int64
	RunID     uuid.UUID
	RiskScore int
	Reasons   []string
	Source    string
	Evidence  map[string]any
}

type RiskReporter interface {
	Report(ctx context.Context, report RiskReport) error
}

type Service interface {
	StartRun(ctx context.Context, actor UserRef, req StartRunInput) (StartRunOutput, error)
	FinishRun(ctx context.Context, actor UserRef, runID uuid.UUID, idemKey string, req FinishRunInput) (FinishRunOutput, error)
	AbortRun(ctx context.Context, actor UserRef, runID uuid.UUID) (GetRunOutput, error)
	Heartbeat(ctx context.Context, actor UserRef, runID uuid.UUID, input RunHeartbeatInput) (RunHeartbeatOutput, error)
	HostMigrationClaim(ctx context.Context, actor UserRef, runID uuid.UUID) (RunHostMigrationClaimOutput, error)
	HostMigrationConfirm(ctx context.Context, actor UserRef, runID uuid.UUID, input RunHostMigrationConfirmInput) (RunHeartbeatOutput, error)
	ReconnectRequest(ctx context.Context, actor UserRef, runID uuid.UUID) (RunReconnectRequestOutput, error)
	ReconnectConfirm(ctx context.Context, actor UserRef, runID uuid.UUID, input RunReconnectConfirmInput) (RunHeartbeatOutput, error)
	GetSessionState(ctx context.Context, actor UserRef, runID uuid.UUID) (RunHeartbeatOutput, error)
	GetRun(ctx context.Context, actor UserRef, runID uuid.UUID) (GetRunOutput, error)
	ListRuns(ctx context.Context, actor UserRef, input ListRunsInput) (ListRunsOutput, error)
	GetRunDetail(ctx context.Context, actor UserRef, runID uuid.UUID) (GetRunDetailOutput, error)
	GetRunReasons(ctx context.Context, actor UserRef, runID uuid.UUID) (GetRunReasonsOutput, error)
}

type ServiceConfig struct {
	HostReconnectWindow   time.Duration
	PlayerReconnectWindow time.Duration
	HostMigrationWindow   time.Duration
	ReconnectTokenTTL     time.Duration
}

type service struct {
	repo     Repository
	idem     IdempotencyStore
	risk     RiskEngine
	reward   RewardService
	reporter RiskReporter
	cfg      ServiceConfig
}

func NewService(repo Repository, idem IdempotencyStore, risk RiskEngine, reward RewardService, reporter RiskReporter) Service {
	return NewServiceWithConfig(repo, idem, risk, reward, reporter, ServiceConfig{})
}

func NewServiceWithConfig(repo Repository, idem IdempotencyStore, risk RiskEngine, reward RewardService, reporter RiskReporter, cfg ServiceConfig) Service {
	if reporter == nil {
		reporter = NewNoopRiskReporter()
	}
	if cfg.HostReconnectWindow <= 0 {
		cfg.HostReconnectWindow = 3 * time.Minute
	}
	if cfg.PlayerReconnectWindow <= 0 {
		cfg.PlayerReconnectWindow = 3 * time.Minute
	}
	if cfg.HostMigrationWindow <= 0 {
		cfg.HostMigrationWindow = 90 * time.Second
	}
	if cfg.ReconnectTokenTTL <= 0 {
		cfg.ReconnectTokenTTL = 60 * time.Second
	}
	return &service{
		repo:     repo,
		idem:     idem,
		risk:     risk,
		reward:   reward,
		reporter: reporter,
		cfg:      cfg,
	}
}

func (s *service) StartRun(ctx context.Context, actor UserRef, req StartRunInput) (StartRunOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return StartRunOutput{}, ErrUnauthorized
	}
	if req.Mode != ModeRogueCoopV1 {
		return StartRunOutput{}, ErrInvalidArgument
	}
	if req.HostSteamID != actor.SteamID {
		return StartRunOutput{}, ErrForbidden
	}
	if req.Difficulty < 1 || req.Difficulty > 5 || len(req.Party) < 1 || len(req.Party) > 4 {
		return StartRunOutput{}, ErrInvalidArgument
	}

	steamSet := make(map[string]struct{}, len(req.Party))
	hostInParty := false
	for _, member := range req.Party {
		if _, exists := steamSet[member.SteamID]; exists {
			return StartRunOutput{}, ErrInvalidArgument
		}
		steamSet[member.SteamID] = struct{}{}
		if member.SteamID == req.HostSteamID {
			hostInParty = true
		}
	}
	if !hostInParty {
		return StartRunOutput{}, ErrInvalidArgument
	}

	now := time.Now().UTC()
	changedRuns, err := s.repo.AbortExpiredRunsByHost(ctx, req.HostSteamID, now, s.cfg.HostMigrationWindow)
	if err != nil {
		if errors.Is(err, ErrInvalidArgument) {
			return StartRunOutput{}, ErrInvalidArgument
		}
		return StartRunOutput{}, ErrInternal
	}
	for _, changedRun := range changedRuns {
		score := 55
		stage := "start_run_promote_migration_wait"
		if changedRun.Status == RunStatusAborted {
			score = 70
			stage = "start_run_abort_after_migration_wait"
		}
		s.reportReconnectRisk(ctx, RiskReport{
			UserID:    changedRun.HostUserID,
			RunID:     changedRun.RunID,
			RiskScore: score,
			Reasons:   []string{RiskReasonHostReconnectTimeout},
			Source:    "run_reconnect",
			Evidence: map[string]any{
				"stage":                   stage,
				"expiredAt":               changedRun.HostReconnectDeadlineAt,
				"hostMigrationDeadlineAt": changedRun.HostMigrationDeadlineAt,
			},
		})
	}

	activeCount, err := s.repo.GetActiveRunCountByHost(ctx, req.HostSteamID)
	if err != nil {
		return StartRunOutput{}, ErrInternal
	}
	if activeCount >= 1 {
		return StartRunOutput{}, ErrConflict
	}

	runID := uuid.New()
	seed, err := randomInt64()
	if err != nil {
		return StartRunOutput{}, ErrInternal
	}

	runToken, err := generateRunToken()
	if err != nil {
		return StartRunOutput{}, ErrInternal
	}

	party := make([]RunMember, 0, len(req.Party))
	for _, member := range req.Party {
		lastSeen := now
		party = append(party, RunMember{
			SteamID:    member.SteamID,
			CharID:     member.CharID,
			State:      RunMemberStateOnline,
			LastSeenAt: &lastSeen,
		})
	}
	hostLastSeen := now
	hostReconnectDeadline := now.Add(s.cfg.HostReconnectWindow)

	session := RunSession{
		RunID:                   runID,
		Seed:                    seed,
		RunTokenHash:            sha256Hex(runToken),
		HostUserID:              actor.UserID,
		HostSteamID:             req.HostSteamID,
		Mode:                    req.Mode,
		Difficulty:              req.Difficulty,
		Region:                  req.Region,
		Party:                   party,
		Status:                  RunStatusRunning,
		StartedAt:               now,
		HostLastHeartbeatAt:     &hostLastSeen,
		HostReconnectDeadlineAt: &hostReconnectDeadline,
	}
	if err := s.repo.CreateRun(ctx, session); err != nil {
		if errors.Is(err, ErrConflict) {
			return StartRunOutput{}, ErrConflict
		}
		return StartRunOutput{}, ErrInternal
	}

	return StartRunOutput{
		RunID:             runID.String(),
		Seed:              fmt.Sprintf("%d", seed),
		RunToken:          runToken,
		TokenExpireAt:     now.Add(2 * time.Hour),
		SubmitDeadlineSec: 900,
		ProofRule: ProofRule{
			Version:          "proof_v1",
			SegmentSec:       30,
			HashAlgo:         "sha256",
			RequiredCounters: []string{"kills", "goldGain", "damageOut", "damageIn"},
		},
	}, nil
}

func (s *service) FinishRun(ctx context.Context, actor UserRef, runID uuid.UUID, idemKey string, req FinishRunInput) (FinishRunOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return FinishRunOutput{}, ErrUnauthorized
	}
	if idemKey == "" {
		return FinishRunOutput{}, ErrInvalidArgument
	}

	requestHash, err := hashRequest(req)
	if err != nil {
		return FinishRunOutput{}, ErrInternal
	}

	existing, err := s.idem.Get(ctx, idemKey)
	if err != nil {
		return FinishRunOutput{}, ErrInternal
	}
	if existing != nil {
		if existing.RequestHash != requestHash {
			return FinishRunOutput{}, ErrIdempotencyReplayMismatch
		}
		return existing.Response, nil
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return FinishRunOutput{}, ErrRunNotFound
		}
		return FinishRunOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return FinishRunOutput{}, err
	}
	if session.Status != RunStatusRunning {
		return FinishRunOutput{}, ErrRunAlreadyFinalized
	}
	if sha256Hex(req.RunToken) != session.RunTokenHash {
		return FinishRunOutput{}, ErrRunTokenInvalid
	}

	if err := validateMemberSet(session.Party, req.Members); err != nil {
		return FinishRunOutput{}, err
	}
	if err := verifyProofChain(runID, req.Proof); err != nil {
		return FinishRunOutput{}, err
	}

	riskScore, reasons, err := s.risk.Score(ctx, session, req)
	if err != nil {
		return FinishRunOutput{}, ErrInternal
	}

	output := FinishRunOutput{
		RunID:     runID.String(),
		RiskScore: riskScore,
	}

	status := RunStatusCompleted
	switch {
	case riskScore < 30:
		output.Verdict = VerdictAccepted
		output.RewardStatus = RewardStatusGranted
		if err := s.reward.GrantNow(ctx, actor, runID, req); err != nil {
			output.RewardStatus = RewardStatusDelayed
			output.NextPollAfterSec = 10
			if err := s.reward.EnqueueRetry(ctx, actor, runID, req); err != nil {
				return FinishRunOutput{}, ErrInternal
			}
		}
	case riskScore < 60:
		output.Verdict = VerdictPendingReview
		output.RewardStatus = RewardStatusDelayed
		output.NextPollAfterSec = 10
		if err := s.reward.EnqueueReview(ctx, actor, runID, req); err != nil {
			return FinishRunOutput{}, ErrInternal
		}
	default:
		output.Verdict = VerdictRejected
		output.RewardStatus = RewardStatusDenied
		status = RunStatusInvalid
	}

	if err := s.repo.SaveRunResult(ctx, StoredRunResult{
		RunID:              runID,
		SubmittedBySteamID: actor.SteamID,
		RiskScore:          riskScore,
		RiskReasons:        reasons,
		Verdict:            output.Verdict,
		RewardStatus:       output.RewardStatus,
		Payload:            req,
		CreatedAt:          time.Now().UTC(),
	}); err != nil {
		return FinishRunOutput{}, ErrInternal
	}

	if riskScore >= 30 && len(reasons) > 0 {
		if err := s.reporter.Report(ctx, RiskReport{
			UserID:    actor.UserID,
			RunID:     runID,
			RiskScore: riskScore,
			Reasons:   reasons,
		}); err != nil {
			return FinishRunOutput{}, ErrInternal
		}
	}

	if err := s.repo.UpdateRunStatus(ctx, runID, status, time.Now().UTC()); err != nil {
		return FinishRunOutput{}, ErrInternal
	}

	if err := s.idem.Put(ctx, IdempotencyRecord{
		Key:         idemKey,
		RequestHash: requestHash,
		Response:    output,
		CreatedAt:   time.Now().UTC(),
	}); err != nil {
		if errors.Is(err, ErrIdempotencyReplayMismatch) {
			return FinishRunOutput{}, ErrIdempotencyReplayMismatch
		}
		return FinishRunOutput{}, ErrInternal
	}

	return output, nil
}

func (s *service) AbortRun(ctx context.Context, actor UserRef, runID uuid.UUID) (GetRunOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return GetRunOutput{}, ErrUnauthorized
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return GetRunOutput{}, ErrRunNotFound
		}
		return GetRunOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return GetRunOutput{}, err
	}
	if session.Status != RunStatusRunning {
		return GetRunOutput{}, ErrRunAlreadyFinalized
	}
	if session.HostSteamID != actor.SteamID {
		return GetRunOutput{}, ErrForbidden
	}

	endedAt := time.Now().UTC()
	if err := s.repo.UpdateRunStatus(ctx, runID, RunStatusAborted, endedAt); err != nil {
		if errors.Is(err, errRecordNotFound) {
			return GetRunOutput{}, ErrRunNotFound
		}
		return GetRunOutput{}, ErrInternal
	}

	return GetRunOutput{
		RunID:     runID.String(),
		Status:    RunStatusAborted,
		StartedAt: session.StartedAt,
		EndedAt:   &endedAt,
	}, nil
}

func (s *service) Heartbeat(ctx context.Context, actor UserRef, runID uuid.UUID, input RunHeartbeatInput) (RunHeartbeatOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return RunHeartbeatOutput{}, ErrUnauthorized
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return RunHeartbeatOutput{}, ErrRunNotFound
		}
		return RunHeartbeatOutput{}, ErrInternal
	}
	if session.Status != RunStatusRunning {
		return RunHeartbeatOutput{}, ErrRunAlreadyFinalized
	}
	if session.HostSteamID != actor.SteamID {
		return RunHeartbeatOutput{}, ErrForbidden
	}

	onlineSet := make(map[string]struct{}, len(input.OnlineSteamIDs)+1)
	onlineSet[actor.SteamID] = struct{}{}
	for _, raw := range input.OnlineSteamIDs {
		steamID := strings.TrimSpace(raw)
		if steamID == "" {
			continue
		}
		if !runContainsSteamID(session.Party, steamID) {
			return RunHeartbeatOutput{}, ErrInvalidArgument
		}
		onlineSet[steamID] = struct{}{}
	}

	onlineSteamIDs := make([]string, 0, len(onlineSet))
	for steamID := range onlineSet {
		onlineSteamIDs = append(onlineSteamIDs, steamID)
	}

	updatedSession, err := s.repo.UpdateRunHeartbeat(ctx, runID, actor.SteamID, onlineSteamIDs, s.cfg.HostReconnectWindow, s.cfg.PlayerReconnectWindow, s.cfg.HostMigrationWindow, time.Now().UTC())
	if err != nil {
		switch {
		case errors.Is(err, errRecordNotFound):
			return RunHeartbeatOutput{}, ErrRunNotFound
		case errors.Is(err, ErrForbidden):
			return RunHeartbeatOutput{}, ErrForbidden
		case errors.Is(err, ErrInvalidArgument):
			return RunHeartbeatOutput{}, ErrInvalidArgument
		case errors.Is(err, ErrRunAlreadyFinalized):
			return RunHeartbeatOutput{}, ErrRunAlreadyFinalized
		default:
			return RunHeartbeatOutput{}, ErrInternal
		}
	}

	return buildRunHeartbeatOutput(updatedSession, s.cfg), nil
}

func (s *service) HostMigrationClaim(ctx context.Context, actor UserRef, runID uuid.UUID) (RunHostMigrationClaimOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return RunHostMigrationClaimOutput{}, ErrUnauthorized
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return RunHostMigrationClaimOutput{}, ErrRunNotFound
		}
		return RunHostMigrationClaimOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return RunHostMigrationClaimOutput{}, err
	}
	if session.Status != RunStatusHostMigrationWait {
		return RunHostMigrationClaimOutput{}, ErrConflict
	}
	if !runContainsSteamID(session.Party, actor.SteamID) {
		return RunHostMigrationClaimOutput{}, ErrForbidden
	}
	now := time.Now().UTC()
	candidate, ok := selectMigrationCandidate(session, now)
	if !ok {
		return RunHostMigrationClaimOutput{}, ErrConflict
	}
	if actor.SteamID != candidate.SteamID {
		return RunHostMigrationClaimOutput{}, ErrForbidden
	}

	claimToken, err := generateReconnectToken()
	if err != nil {
		return RunHostMigrationClaimOutput{}, ErrInternal
	}
	expireAt := now.Add(s.cfg.ReconnectTokenTTL)
	if err := s.repo.SaveReconnectToken(ctx, runID, actor.SteamID, sha256Hex(claimToken), expireAt); err != nil {
		switch {
		case errors.Is(err, errRecordNotFound):
			return RunHostMigrationClaimOutput{}, ErrRunNotFound
		case errors.Is(err, ErrInvalidArgument):
			return RunHostMigrationClaimOutput{}, ErrInvalidArgument
		case errors.Is(err, ErrForbidden):
			return RunHostMigrationClaimOutput{}, ErrForbidden
		case errors.Is(err, ErrRunAlreadyFinalized):
			return RunHostMigrationClaimOutput{}, ErrRunAlreadyFinalized
		default:
			return RunHostMigrationClaimOutput{}, ErrInternal
		}
	}

	return RunHostMigrationClaimOutput{
		RunID:                   runID.String(),
		Status:                  session.Status,
		MigrationEpoch:          session.MigrationEpoch,
		CandidateSteamID:        candidate.SteamID,
		ClaimToken:              claimToken,
		ClaimTokenExpireAt:      expireAt,
		HostMigrationDeadlineAt: session.HostMigrationDeadlineAt,
	}, nil
}

func (s *service) HostMigrationConfirm(ctx context.Context, actor UserRef, runID uuid.UUID, input RunHostMigrationConfirmInput) (RunHeartbeatOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return RunHeartbeatOutput{}, ErrUnauthorized
	}
	token := strings.TrimSpace(input.ClaimToken)
	if token == "" {
		return RunHeartbeatOutput{}, ErrInvalidArgument
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return RunHeartbeatOutput{}, ErrRunNotFound
		}
		return RunHeartbeatOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return RunHeartbeatOutput{}, err
	}
	if session.Status != RunStatusHostMigrationWait {
		return RunHeartbeatOutput{}, ErrConflict
	}
	if !runContainsSteamID(session.Party, actor.SteamID) {
		return RunHeartbeatOutput{}, ErrForbidden
	}

	updated, err := s.repo.ConfirmReconnect(ctx, runID, actor.SteamID, sha256Hex(token), s.cfg.HostReconnectWindow, s.cfg.PlayerReconnectWindow, s.cfg.HostMigrationWindow, time.Now().UTC())
	if err != nil {
		switch {
		case errors.Is(err, errRecordNotFound):
			return RunHeartbeatOutput{}, ErrRunNotFound
		case errors.Is(err, ErrInvalidArgument):
			return RunHeartbeatOutput{}, ErrInvalidArgument
		case errors.Is(err, ErrForbidden):
			return RunHeartbeatOutput{}, ErrForbidden
		case errors.Is(err, ErrRunAlreadyFinalized):
			return RunHeartbeatOutput{}, ErrRunAlreadyFinalized
		case errors.Is(err, ErrReconnectWindowExpired):
			s.reportReconnectRisk(ctx, RiskReport{
				UserID:    actor.UserID,
				RunID:     runID,
				RiskScore: 55,
				Reasons:   []string{RiskReasonReconnectWindowExpired},
				Source:    "run_host_migration",
				Evidence: map[string]any{
					"stage": "confirm",
				},
			})
			return RunHeartbeatOutput{}, ErrReconnectWindowExpired
		case errors.Is(err, ErrReconnectTokenInvalid), errors.Is(err, ErrRunTokenInvalid):
			s.reportReconnectRisk(ctx, RiskReport{
				UserID:    actor.UserID,
				RunID:     runID,
				RiskScore: 65,
				Reasons:   []string{RiskReasonReconnectTokenInvalid},
				Source:    "run_host_migration",
				Evidence: map[string]any{
					"stage": "confirm",
				},
			})
			return RunHeartbeatOutput{}, ErrReconnectTokenInvalid
		default:
			return RunHeartbeatOutput{}, ErrInternal
		}
	}

	return buildRunHeartbeatOutput(updated, s.cfg), nil
}

func (s *service) ReconnectRequest(ctx context.Context, actor UserRef, runID uuid.UUID) (RunReconnectRequestOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return RunReconnectRequestOutput{}, ErrUnauthorized
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return RunReconnectRequestOutput{}, ErrRunNotFound
		}
		return RunReconnectRequestOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return RunReconnectRequestOutput{}, err
	}
	if session.Status != RunStatusRunning {
		return RunReconnectRequestOutput{}, ErrRunAlreadyFinalized
	}
	if !runContainsSteamID(session.Party, actor.SteamID) {
		return RunReconnectRequestOutput{}, ErrForbidden
	}

	now := time.Now().UTC()
	if actor.SteamID == session.HostSteamID {
		if session.HostReconnectDeadlineAt != nil && session.HostReconnectDeadlineAt.Before(now) {
			s.reportReconnectRisk(ctx, RiskReport{
				UserID:    actor.UserID,
				RunID:     runID,
				RiskScore: 50,
				Reasons:   []string{RiskReasonReconnectWindowExpired},
				Source:    "run_reconnect",
				Evidence: map[string]any{
					"stage":     "request",
					"role":      "host",
					"expiredAt": session.HostReconnectDeadlineAt,
				},
			})
			return RunReconnectRequestOutput{}, ErrReconnectWindowExpired
		}
	} else {
		member, found := findRunMember(session.Party, actor.SteamID)
		if !found {
			return RunReconnectRequestOutput{}, ErrForbidden
		}
		if member.State == RunMemberStateTimedOut {
			s.reportReconnectRisk(ctx, RiskReport{
				UserID:    actor.UserID,
				RunID:     runID,
				RiskScore: 45,
				Reasons:   []string{RiskReasonReconnectWindowExpired},
				Source:    "run_reconnect",
				Evidence: map[string]any{
					"stage": "request",
					"role":  "member",
					"state": member.State,
				},
			})
			return RunReconnectRequestOutput{}, ErrReconnectWindowExpired
		}
		if member.ReconnectDeadlineAt != nil && member.ReconnectDeadlineAt.Before(now) {
			s.reportReconnectRisk(ctx, RiskReport{
				UserID:    actor.UserID,
				RunID:     runID,
				RiskScore: 45,
				Reasons:   []string{RiskReasonReconnectWindowExpired},
				Source:    "run_reconnect",
				Evidence: map[string]any{
					"stage":     "request",
					"role":      "member",
					"expiredAt": member.ReconnectDeadlineAt,
				},
			})
			return RunReconnectRequestOutput{}, ErrReconnectWindowExpired
		}
	}

	resumeToken, err := generateReconnectToken()
	if err != nil {
		return RunReconnectRequestOutput{}, ErrInternal
	}
	expireAt := now.Add(s.cfg.ReconnectTokenTTL)
	if err := s.repo.SaveReconnectToken(ctx, runID, actor.SteamID, sha256Hex(resumeToken), expireAt); err != nil {
		switch {
		case errors.Is(err, errRecordNotFound):
			return RunReconnectRequestOutput{}, ErrRunNotFound
		case errors.Is(err, ErrInvalidArgument):
			return RunReconnectRequestOutput{}, ErrInvalidArgument
		case errors.Is(err, ErrForbidden):
			return RunReconnectRequestOutput{}, ErrForbidden
		case errors.Is(err, ErrRunAlreadyFinalized):
			return RunReconnectRequestOutput{}, ErrRunAlreadyFinalized
		default:
			return RunReconnectRequestOutput{}, ErrInternal
		}
	}

	return RunReconnectRequestOutput{
		RunID:                   runID.String(),
		ResumeToken:             resumeToken,
		ExpireAt:                expireAt,
		HostReconnectDeadlineAt: session.HostReconnectDeadlineAt,
	}, nil
}

func (s *service) ReconnectConfirm(ctx context.Context, actor UserRef, runID uuid.UUID, input RunReconnectConfirmInput) (RunHeartbeatOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return RunHeartbeatOutput{}, ErrUnauthorized
	}

	token := strings.TrimSpace(input.ResumeToken)
	if token == "" {
		return RunHeartbeatOutput{}, ErrInvalidArgument
	}

	session, err := s.repo.ConfirmReconnect(ctx, runID, actor.SteamID, sha256Hex(token), s.cfg.HostReconnectWindow, s.cfg.PlayerReconnectWindow, s.cfg.HostMigrationWindow, time.Now().UTC())
	if err != nil {
		switch {
		case errors.Is(err, errRecordNotFound):
			return RunHeartbeatOutput{}, ErrRunNotFound
		case errors.Is(err, ErrInvalidArgument):
			return RunHeartbeatOutput{}, ErrInvalidArgument
		case errors.Is(err, ErrForbidden):
			return RunHeartbeatOutput{}, ErrForbidden
		case errors.Is(err, ErrRunAlreadyFinalized):
			return RunHeartbeatOutput{}, ErrRunAlreadyFinalized
		case errors.Is(err, ErrReconnectWindowExpired):
			s.reportReconnectRisk(ctx, RiskReport{
				UserID:    actor.UserID,
				RunID:     runID,
				RiskScore: 55,
				Reasons:   []string{RiskReasonReconnectWindowExpired},
				Source:    "run_reconnect",
				Evidence: map[string]any{
					"stage": "confirm",
				},
			})
			return RunHeartbeatOutput{}, ErrReconnectWindowExpired
		case errors.Is(err, ErrRunTokenInvalid), errors.Is(err, ErrReconnectTokenInvalid):
			s.reportReconnectRisk(ctx, RiskReport{
				UserID:    actor.UserID,
				RunID:     runID,
				RiskScore: 65,
				Reasons:   []string{RiskReasonReconnectTokenInvalid},
				Source:    "run_reconnect",
				Evidence: map[string]any{
					"stage": "confirm",
				},
			})
			return RunHeartbeatOutput{}, ErrReconnectTokenInvalid
		default:
			return RunHeartbeatOutput{}, ErrInternal
		}
	}

	return buildRunHeartbeatOutput(session, s.cfg), nil
}

func (s *service) GetSessionState(ctx context.Context, actor UserRef, runID uuid.UUID) (RunHeartbeatOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return RunHeartbeatOutput{}, ErrUnauthorized
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return RunHeartbeatOutput{}, ErrRunNotFound
		}
		return RunHeartbeatOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return RunHeartbeatOutput{}, err
	}
	if !runContainsSteamID(session.Party, actor.SteamID) {
		return RunHeartbeatOutput{}, ErrForbidden
	}

	return buildRunHeartbeatOutput(session, s.cfg), nil
}

func (s *service) GetRun(ctx context.Context, actor UserRef, runID uuid.UUID) (GetRunOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return GetRunOutput{}, ErrUnauthorized
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return GetRunOutput{}, ErrRunNotFound
		}
		return GetRunOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return GetRunOutput{}, err
	}

	isParticipant := false
	for _, member := range session.Party {
		if member.SteamID == actor.SteamID {
			isParticipant = true
			break
		}
	}
	if !isParticipant {
		return GetRunOutput{}, ErrForbidden
	}

	output := GetRunOutput{
		RunID:     runID.String(),
		Status:    session.Status,
		StartedAt: session.StartedAt,
		EndedAt:   session.EndedAt,
	}

	result, err := s.repo.GetRunResult(ctx, runID)
	if err == nil {
		output.Verdict = result.Verdict
		output.RiskScore = result.RiskScore
		output.RewardStatus = result.RewardStatus
	} else if !errors.Is(err, errRecordNotFound) {
		return GetRunOutput{}, ErrInternal
	}

	return output, nil
}

func (s *service) GetRunDetail(ctx context.Context, actor UserRef, runID uuid.UUID) (GetRunDetailOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return GetRunDetailOutput{}, ErrUnauthorized
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return GetRunDetailOutput{}, ErrRunNotFound
		}
		return GetRunDetailOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return GetRunDetailOutput{}, err
	}
	if !runContainsSteamID(session.Party, actor.SteamID) {
		return GetRunDetailOutput{}, ErrForbidden
	}

	party := make([]RunPartyMemberDetail, 0, len(session.Party))
	for _, member := range session.Party {
		party = append(party, RunPartyMemberDetail{
			SteamID:             member.SteamID,
			CharID:              member.CharID,
			State:               member.State,
			LastSeenAt:          member.LastSeenAt,
			ReconnectDeadlineAt: member.ReconnectDeadlineAt,
		})
	}

	output := GetRunDetailOutput{
		RunID:      runID.String(),
		Mode:       session.Mode,
		Difficulty: session.Difficulty,
		Region:     session.Region,
		Status:     session.Status,
		IsHost:     session.HostSteamID == actor.SteamID,
		Party:      party,
		StartedAt:  session.StartedAt,
		EndedAt:    session.EndedAt,
	}

	result, err := s.repo.GetRunResult(ctx, runID)
	if err == nil {
		detail := buildRunResultDetail(result)
		output.Result = &detail
	} else if !errors.Is(err, errRecordNotFound) {
		return GetRunDetailOutput{}, ErrInternal
	}

	return output, nil
}

func (s *service) GetRunReasons(ctx context.Context, actor UserRef, runID uuid.UUID) (GetRunReasonsOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return GetRunReasonsOutput{}, ErrUnauthorized
	}

	session, err := s.repo.GetRun(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return GetRunReasonsOutput{}, ErrRunNotFound
		}
		return GetRunReasonsOutput{}, ErrInternal
	}
	session, err = s.finalizeTimedOutRun(ctx, session)
	if err != nil {
		return GetRunReasonsOutput{}, err
	}
	if !runContainsSteamID(session.Party, actor.SteamID) {
		return GetRunReasonsOutput{}, ErrForbidden
	}

	output := GetRunReasonsOutput{
		RunID:     runID.String(),
		Status:    session.Status,
		RiskScore: 0,
		Reasons:   []RunReasonItem{},
		Total:     0,
	}

	result, err := s.repo.GetRunResult(ctx, runID)
	if err != nil {
		if errors.Is(err, errRecordNotFound) {
			return output, nil
		}
		return GetRunReasonsOutput{}, ErrInternal
	}

	output.Verdict = result.Verdict
	output.RiskScore = result.RiskScore
	uniqueCodes := uniqueRiskReasonCodes(result.RiskReasons)
	reasons := make([]RunReasonItem, 0, len(uniqueCodes))
	for _, code := range uniqueCodes {
		reasons = append(reasons, buildRunReasonItem(code))
	}
	output.Reasons = reasons
	output.Total = len(reasons)
	return output, nil
}

func (s *service) ListRuns(ctx context.Context, actor UserRef, input ListRunsInput) (ListRunsOutput, error) {
	if actor.SteamID == "" || actor.UserID <= 0 {
		return ListRunsOutput{}, ErrUnauthorized
	}

	normalized, err := normalizeListRunsInput(input)
	if err != nil {
		return ListRunsOutput{}, err
	}

	items, total, err := s.repo.ListRunsByPlayer(ctx, actor.SteamID, normalized)
	if err != nil {
		if errors.Is(err, ErrInvalidArgument) {
			return ListRunsOutput{}, ErrInvalidArgument
		}
		return ListRunsOutput{}, ErrInternal
	}

	return ListRunsOutput{
		Items: items,
		Total: total,
	}, nil
}

func buildRunHeartbeatOutput(session RunSession, cfg ServiceConfig) RunHeartbeatOutput {
	members := make([]RunHeartbeatMember, 0, len(session.Party))
	for _, member := range session.Party {
		state := member.State
		if state == "" {
			state = RunMemberStateOnline
		}
		members = append(members, RunHeartbeatMember{
			SteamID:             member.SteamID,
			State:               state,
			LastSeenAt:          member.LastSeenAt,
			ReconnectDeadlineAt: member.ReconnectDeadlineAt,
		})
	}

	return RunHeartbeatOutput{
		RunID:                    session.RunID.String(),
		CurrentHostSteamID:       session.HostSteamID,
		Status:                   session.Status,
		MigrationEpoch:           session.MigrationEpoch,
		HostLastHeartbeatAt:      session.HostLastHeartbeatAt,
		HostReconnectDeadlineAt:  session.HostReconnectDeadlineAt,
		HostMigrationDeadlineAt:  session.HostMigrationDeadlineAt,
		HostReconnectWindowSec:   int(cfg.HostReconnectWindow / time.Second),
		PlayerReconnectWindowSec: int(cfg.PlayerReconnectWindow / time.Second),
		Members:                  members,
	}
}

func (s *service) finalizeTimedOutRun(ctx context.Context, session RunSession) (RunSession, error) {
	now := time.Now().UTC()

	if session.Status == RunStatusRunning && session.HostReconnectDeadlineAt != nil && session.HostReconnectDeadlineAt.Before(now) {
		updated, err := s.repo.PromoteRunToMigrationWait(ctx, session.RunID, now, s.cfg.HostMigrationWindow)
		if err != nil {
			if errors.Is(err, errRecordNotFound) {
				return RunSession{}, ErrRunNotFound
			}
			return RunSession{}, ErrInternal
		}
		if updated.Status == RunStatusHostMigrationWait {
			s.reportReconnectRisk(ctx, RiskReport{
				UserID:    updated.HostUserID,
				RunID:     updated.RunID,
				RiskScore: 55,
				Reasons:   []string{RiskReasonHostReconnectTimeout},
				Source:    "run_reconnect",
				Evidence: map[string]any{
					"stage":                   "host_timeout_promote_migration_wait",
					"expiredAt":               updated.HostReconnectDeadlineAt,
					"hostMigrationDeadlineAt": updated.HostMigrationDeadlineAt,
				},
			})
		}
		session = updated
	}

	if session.Status == RunStatusHostMigrationWait && session.HostMigrationDeadlineAt != nil && session.HostMigrationDeadlineAt.Before(now) {
		if err := s.repo.UpdateRunStatus(ctx, session.RunID, RunStatusAborted, now); err != nil {
			if errors.Is(err, errRecordNotFound) {
				return RunSession{}, ErrRunNotFound
			}
			return RunSession{}, ErrInternal
		}

		s.reportReconnectRisk(ctx, RiskReport{
			UserID:    session.HostUserID,
			RunID:     session.RunID,
			RiskScore: 70,
			Reasons:   []string{RiskReasonHostReconnectTimeout},
			Source:    "run_reconnect",
			Evidence: map[string]any{
				"stage":                   "host_migration_wait_timeout_abort",
				"hostMigrationDeadlineAt": session.HostMigrationDeadlineAt,
			},
		})

		session.Status = RunStatusAborted
		session.EndedAt = &now
	}
	return session, nil
}

func (s *service) reportReconnectRisk(ctx context.Context, report RiskReport) {
	if len(report.Reasons) == 0 || report.UserID <= 0 {
		return
	}
	_ = s.reporter.Report(ctx, report)
}

func findRunMember(party []RunMember, steamID string) (RunMember, bool) {
	for _, member := range party {
		if member.SteamID == steamID {
			return member, true
		}
	}
	return RunMember{}, false
}

func selectMigrationCandidate(session RunSession, now time.Time) (RunMember, bool) {
	candidates := make([]RunMember, 0, len(session.Party))
	for _, member := range session.Party {
		if member.SteamID == session.HostSteamID {
			continue
		}
		state := member.State
		if state == "" {
			state = RunMemberStateOnline
		}
		if state == RunMemberStateTimedOut {
			continue
		}
		if member.ReconnectDeadlineAt != nil && member.ReconnectDeadlineAt.Before(now) {
			continue
		}
		if state != RunMemberStateOnline && state != RunMemberStateReconnecting {
			continue
		}
		candidates = append(candidates, member)
	}
	if len(candidates) == 0 {
		return RunMember{}, false
	}
	slices.SortFunc(candidates, func(a, b RunMember) int {
		ar := migrationStateRank(a.State)
		br := migrationStateRank(b.State)
		if ar != br {
			return ar - br
		}
		return strings.Compare(a.SteamID, b.SteamID)
	})
	return candidates[0], true
}

func migrationStateRank(state string) int {
	switch state {
	case "", RunMemberStateOnline:
		return 0
	case RunMemberStateReconnecting:
		return 1
	default:
		return 2
	}
}

func validateMemberSet(runMembers []RunMember, submitted []FinishMember) error {
	if len(runMembers) != len(submitted) {
		return ErrMemberSetMismatch
	}

	expected := make([]string, 0, len(runMembers))
	for _, member := range runMembers {
		expected = append(expected, member.SteamID)
	}

	actual := make([]string, 0, len(submitted))
	for _, member := range submitted {
		actual = append(actual, member.SteamID)
	}

	slices.Sort(expected)
	slices.Sort(actual)
	for idx := range expected {
		if expected[idx] != actual[idx] {
			return ErrMemberSetMismatch
		}
	}

	return nil
}

func hashRequest(req FinishRunInput) (string, error) {
	raw, err := json.Marshal(req)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:]), nil
}

func generateRunToken() (string, error) {
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return "rtk_" + hex.EncodeToString(buf), nil
}

func generateReconnectToken() (string, error) {
	buf := make([]byte, 20)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return "rrt_" + hex.EncodeToString(buf), nil
}

func randomInt64() (int64, error) {
	maxInt := big.NewInt(1<<62 - 1)
	n, err := rand.Int(rand.Reader, maxInt)
	if err != nil {
		return 0, err
	}
	return n.Int64(), nil
}

func sha256Hex(raw string) string {
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:])
}

func normalizeListRunsInput(input ListRunsInput) (ListRunsInput, error) {
	output := ListRunsInput{
		Mode: strings.TrimSpace(input.Mode),
	}

	if output.Mode != "" && output.Mode != ModeRogueCoopV1 {
		return ListRunsInput{}, ErrInvalidArgument
	}

	status := strings.ToLower(strings.TrimSpace(input.Status))
	switch status {
	case "":
	case string(RunStatusRunning), string(RunStatusHostMigrationWait), string(RunStatusCompleted), string(RunStatusAborted), string(RunStatusInvalid):
		output.Status = status
	default:
		return ListRunsInput{}, ErrInvalidArgument
	}

	verdict := strings.ToLower(strings.TrimSpace(input.Verdict))
	switch verdict {
	case "":
	case VerdictAccepted, VerdictPendingReview, VerdictRejected:
		output.Verdict = verdict
	default:
		return ListRunsInput{}, ErrInvalidArgument
	}

	rewardStatus := strings.ToLower(strings.TrimSpace(input.RewardStatus))
	switch rewardStatus {
	case "":
	case RewardStatusGranted, RewardStatusDelayed, RewardStatusDenied:
		output.RewardStatus = rewardStatus
	default:
		return ListRunsInput{}, ErrInvalidArgument
	}

	order := strings.ToLower(strings.TrimSpace(input.Order))
	switch order {
	case "", "desc":
		output.Order = "desc"
	case "asc":
		output.Order = "asc"
	default:
		return ListRunsInput{}, ErrInvalidArgument
	}

	if input.Offset < 0 {
		return ListRunsInput{}, ErrInvalidArgument
	}
	output.Offset = input.Offset

	limit := input.Limit
	if limit <= 0 {
		limit = 20
	}
	if limit > 100 {
		limit = 100
	}
	output.Limit = limit

	return output, nil
}

func buildRunResultDetail(result StoredRunResult) RunResultDetail {
	members := make([]FinishMember, 0, len(result.Payload.Members))
	for _, member := range result.Payload.Members {
		rewardDraft := make([]RewardDraft, 0, len(member.RewardDraft))
		for _, reward := range member.RewardDraft {
			rewardDraft = append(rewardDraft, RewardDraft{
				Type:   reward.Type,
				ID:     reward.ID,
				Amount: reward.Amount,
			})
		}

		members = append(members, FinishMember{
			SteamID:     member.SteamID,
			DamageDone:  member.DamageDone,
			DownCount:   member.DownCount,
			ReviveCount: member.ReviveCount,
			RewardDraft: rewardDraft,
		})
	}

	return RunResultDetail{
		SubmittedBySteamID: result.SubmittedBySteamID,
		SubmittedAt:        result.CreatedAt,
		Verdict:            result.Verdict,
		RiskScore:          result.RiskScore,
		RewardStatus:       result.RewardStatus,
		Final:              result.Payload.Final,
		Members:            members,
		ClientMeta:         result.Payload.ClientMeta,
		Proof: RunProofSummary{
			SegmentSec:   result.Payload.Proof.SegmentSec,
			SegmentCount: len(result.Payload.Proof.Segments),
			HeadHash:     result.Payload.Proof.HeadHash,
			TailHash:     result.Payload.Proof.TailHash,
		},
	}
}

func uniqueRiskReasonCodes(codes []string) []string {
	set := make(map[string]struct{}, len(codes))
	out := make([]string, 0, len(codes))
	for _, code := range codes {
		normalized := strings.TrimSpace(code)
		if normalized == "" {
			continue
		}
		if _, exists := set[normalized]; exists {
			continue
		}
		set[normalized] = struct{}{}
		out = append(out, normalized)
	}
	return out
}

type runRiskReasonMeta struct {
	Weight      int
	Title       string
	Description string
}

var runRiskReasonMetaMap = map[string]runRiskReasonMeta{
	"R001_DURATION_ANOMALY": {
		Weight:      16,
		Title:       "通关时长异常",
		Description: "实战耗时与关卡规模、难度的统计区间明显不符。",
	},
	"R002_SCORE_OVER_CAP": {
		Weight:      18,
		Title:       "队伍得分超上限",
		Description: "总得分超过当前房间数与难度下的合理上限。",
	},
	"R003_GOLD_RATE_SPIKE": {
		Weight:      12,
		Title:       "金币获取速率异常",
		Description: "单位时间金币增长速率超出历史与规则阈值。",
	},
	"R004_DPS_OVER_CAP": {
		Weight:      14,
		Title:       "成员输出异常",
		Description: "存在成员的秒伤显著高于当前难度阈值。",
	},
	"R005_KILL_ROOM_MISMATCH": {
		Weight:      10,
		Title:       "击杀与房间规模不匹配",
		Description: "累计击杀量与已通关房间数比例异常。",
	},
	"R006_ZERO_DAMAGE_IN_LONG_RUN": {
		Weight:      8,
		Title:       "长局几乎无受伤",
		Description: "长时对局中承受伤害值极低，偏离常规分布。",
	},
	"R007_DOWN_REVIVE_INCONSISTENT": {
		Weight:      8,
		Title:       "倒地复活计数异常",
		Description: "倒地与复活次数关系不合理，可能存在统计异常。",
	},
	"R008_REWARD_NOT_IN_DROPTABLE": {
		Weight:      12,
		Title:       "奖励类型不在掉落池",
		Description: "提交奖励包含不受支持或不在配置池内的类型。",
	},
	"R009_PROOF_SEGMENT_TOO_SPARSE": {
		Weight:      6,
		Title:       "Proof 分段过稀疏",
		Description: "Proof 数据分段数量偏少，链路可信度下降。",
	},
	"R010_DUPLICATE_FINGERPRINT": {
		Weight:      6,
		Title:       "指纹重复信号",
		Description: "Proof 头尾哈希重复，疑似复用或伪造上报。",
	},
	"R011_MEMBER_SET_MISMATCH": {
		Weight:      20,
		Title:       "成员集合不匹配",
		Description: "提交成员集合与开局成员集合不一致。",
	},
	"R012_BUILD_OR_ENV_ABNORMAL": {
		Weight:      5,
		Title:       "构建或网络环境异常",
		Description: "客户端构建信息或网络环境参数超出合理范围。",
	},
	"R013_HOST_RECONNECT_TIMEOUT": {
		Weight:      12,
		Title:       "房主重连超时",
		Description: "房主超过重连窗口仍未恢复，进入主机迁移或中止流程。",
	},
	"R014_RECONNECT_TOKEN_INVALID": {
		Weight:      14,
		Title:       "重连凭证异常",
		Description: "重连确认使用了无效、过期或不匹配的凭证。",
	},
	"R015_RECONNECT_WINDOW_EXPIRED": {
		Weight:      10,
		Title:       "重连窗口过期",
		Description: "玩家在允许的重连窗口之后才尝试恢复连接。",
	},
}

func buildRunReasonItem(code string) RunReasonItem {
	meta, ok := runRiskReasonMetaMap[code]
	if !ok {
		meta = runRiskReasonMeta{
			Weight:      0,
			Title:       "未知风险规则",
			Description: "该规则暂未提供可读说明，请联系后台查看详细 evidence。",
		}
	}

	return RunReasonItem{
		Code:        code,
		Severity:    riskSeverityFromWeight(meta.Weight),
		Weight:      meta.Weight,
		Title:       meta.Title,
		Description: meta.Description,
	}
}

func riskSeverityFromWeight(weight int) string {
	switch {
	case weight >= 16:
		return "high"
	case weight >= 10:
		return "medium"
	default:
		return "low"
	}
}
