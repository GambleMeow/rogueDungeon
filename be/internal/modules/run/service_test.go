package run

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestServiceFinishRun_AcceptedWithP2PParty(t *testing.T) {
	risk := &stubRiskEngine{score: 12}
	reward := &stubRewardService{}
	reporter := &stubRiskReporter{}
	svc, repo, _, actor := newTestServiceHarness(risk, reward, reporter)

	party := []string{testHostSteamID, testPeerSteamID, testPeer2SteamID, testPeer3SteamID}
	runID, runToken := startRunForTest(t, svc, actor, party)
	req := buildValidFinishInput(runID, runToken, party)

	out, err := svc.FinishRun(context.Background(), actor, runID, "idem-accepted", req)
	if err != nil {
		t.Fatalf("finish run failed: %v", err)
	}
	if out.Verdict != VerdictAccepted {
		t.Fatalf("expected verdict %q, got %q", VerdictAccepted, out.Verdict)
	}
	if out.RewardStatus != RewardStatusGranted {
		t.Fatalf("expected reward status %q, got %q", RewardStatusGranted, out.RewardStatus)
	}
	if reward.grantNowCalls != 1 || reward.enqueueRetryCalls != 0 || reward.enqueueReviewCalls != 0 {
		t.Fatalf("unexpected reward calls: grant=%d retry=%d review=%d",
			reward.grantNowCalls, reward.enqueueRetryCalls, reward.enqueueReviewCalls)
	}
	if len(reporter.reports) != 0 {
		t.Fatalf("expected no risk report for accepted run, got %d", len(reporter.reports))
	}

	session, err := repo.GetRun(context.Background(), runID)
	if err != nil {
		t.Fatalf("get run failed: %v", err)
	}
	if session.Status != RunStatusCompleted {
		t.Fatalf("expected run status %q, got %q", RunStatusCompleted, session.Status)
	}

	result, err := repo.GetRunResult(context.Background(), runID)
	if err != nil {
		t.Fatalf("get run result failed: %v", err)
	}
	if result.Verdict != VerdictAccepted || result.RewardStatus != RewardStatusGranted {
		t.Fatalf("unexpected stored result: verdict=%q rewardStatus=%q", result.Verdict, result.RewardStatus)
	}
}

func TestServiceFinishRun_GrantFailureFallsBackToRetryQueue(t *testing.T) {
	risk := &stubRiskEngine{score: 8}
	reward := &stubRewardService{grantNowErr: errors.New("inventory write failed")}
	svc, repo, _, actor := newTestServiceHarness(risk, reward, &stubRiskReporter{})

	runID, runToken := startRunForTest(t, svc, actor, []string{testHostSteamID, testPeerSteamID})
	req := buildValidFinishInput(runID, runToken, []string{testHostSteamID, testPeerSteamID})

	out, err := svc.FinishRun(context.Background(), actor, runID, "idem-retry", req)
	if err != nil {
		t.Fatalf("finish run failed: %v", err)
	}
	if out.Verdict != VerdictAccepted {
		t.Fatalf("expected accepted verdict, got %q", out.Verdict)
	}
	if out.RewardStatus != RewardStatusDelayed {
		t.Fatalf("expected delayed reward when immediate grant fails, got %q", out.RewardStatus)
	}
	if out.NextPollAfterSec != 10 {
		t.Fatalf("expected next poll 10 sec, got %d", out.NextPollAfterSec)
	}
	if reward.grantNowCalls != 1 || reward.enqueueRetryCalls != 1 {
		t.Fatalf("unexpected reward fallback calls: grant=%d retry=%d",
			reward.grantNowCalls, reward.enqueueRetryCalls)
	}

	result, err := repo.GetRunResult(context.Background(), runID)
	if err != nil {
		t.Fatalf("get run result failed: %v", err)
	}
	if result.RewardStatus != RewardStatusDelayed {
		t.Fatalf("expected stored delayed reward status, got %q", result.RewardStatus)
	}
}

func TestServiceFinishRun_PendingReviewEnqueueAndRiskReport(t *testing.T) {
	risk := &stubRiskEngine{
		score:   45,
		reasons: []string{"R001_DURATION_ANOMALY"},
	}
	reward := &stubRewardService{}
	reporter := &stubRiskReporter{}
	svc, repo, _, actor := newTestServiceHarness(risk, reward, reporter)

	runID, runToken := startRunForTest(t, svc, actor, []string{testHostSteamID, testPeerSteamID})
	req := buildValidFinishInput(runID, runToken, []string{testHostSteamID, testPeerSteamID})

	out, err := svc.FinishRun(context.Background(), actor, runID, "idem-review", req)
	if err != nil {
		t.Fatalf("finish run failed: %v", err)
	}
	if out.Verdict != VerdictPendingReview {
		t.Fatalf("expected verdict %q, got %q", VerdictPendingReview, out.Verdict)
	}
	if out.RewardStatus != RewardStatusDelayed {
		t.Fatalf("expected delayed reward status, got %q", out.RewardStatus)
	}
	if reward.enqueueReviewCalls != 1 || reward.grantNowCalls != 0 {
		t.Fatalf("unexpected reward calls: grant=%d review=%d",
			reward.grantNowCalls, reward.enqueueReviewCalls)
	}
	if len(reporter.reports) != 1 {
		t.Fatalf("expected one risk report, got %d", len(reporter.reports))
	}

	session, err := repo.GetRun(context.Background(), runID)
	if err != nil {
		t.Fatalf("get run failed: %v", err)
	}
	if session.Status != RunStatusCompleted {
		t.Fatalf("expected completed status for pending review, got %q", session.Status)
	}
}

func TestServiceFinishRun_RejectedRunInvalidatesSession(t *testing.T) {
	risk := &stubRiskEngine{
		score:   92,
		reasons: []string{"R001_DURATION_ANOMALY", "R002_SCORE_OVER_CAP"},
	}
	reward := &stubRewardService{}
	reporter := &stubRiskReporter{}
	svc, repo, _, actor := newTestServiceHarness(risk, reward, reporter)

	runID, runToken := startRunForTest(t, svc, actor, []string{testHostSteamID, testPeerSteamID})
	req := buildValidFinishInput(runID, runToken, []string{testHostSteamID, testPeerSteamID})

	out, err := svc.FinishRun(context.Background(), actor, runID, "idem-reject", req)
	if err != nil {
		t.Fatalf("finish run failed: %v", err)
	}
	if out.Verdict != VerdictRejected {
		t.Fatalf("expected rejected verdict, got %q", out.Verdict)
	}
	if out.RewardStatus != RewardStatusDenied {
		t.Fatalf("expected denied reward status, got %q", out.RewardStatus)
	}
	if reward.grantNowCalls != 0 || reward.enqueueRetryCalls != 0 || reward.enqueueReviewCalls != 0 {
		t.Fatalf("expected no reward execution for rejected run, got grant=%d retry=%d review=%d",
			reward.grantNowCalls, reward.enqueueRetryCalls, reward.enqueueReviewCalls)
	}
	if len(reporter.reports) != 1 {
		t.Fatalf("expected risk report for rejected run, got %d", len(reporter.reports))
	}

	session, err := repo.GetRun(context.Background(), runID)
	if err != nil {
		t.Fatalf("get run failed: %v", err)
	}
	if session.Status != RunStatusInvalid {
		t.Fatalf("expected invalid run status, got %q", session.Status)
	}
}

func TestServiceFinishRun_IdempotencyReplayAndMismatch(t *testing.T) {
	risk := &stubRiskEngine{score: 10}
	reward := &stubRewardService{}
	svc, _, _, actor := newTestServiceHarness(risk, reward, &stubRiskReporter{})

	runID, runToken := startRunForTest(t, svc, actor, []string{testHostSteamID, testPeerSteamID})
	req := buildValidFinishInput(runID, runToken, []string{testHostSteamID, testPeerSteamID})

	out1, err := svc.FinishRun(context.Background(), actor, runID, "idem-replay", req)
	if err != nil {
		t.Fatalf("first finish failed: %v", err)
	}
	out2, err := svc.FinishRun(context.Background(), actor, runID, "idem-replay", req)
	if err != nil {
		t.Fatalf("idempotent replay failed: %v", err)
	}
	if out1 != out2 {
		t.Fatalf("expected replay output to match original output, got %+v vs %+v", out1, out2)
	}
	if reward.grantNowCalls != 1 {
		t.Fatalf("expected one grant call due to idempotency replay, got %d", reward.grantNowCalls)
	}

	reqConflict := req
	reqConflict.Final.TeamScore++
	_, err = svc.FinishRun(context.Background(), actor, runID, "idem-replay", reqConflict)
	if err != ErrIdempotencyReplayMismatch {
		t.Fatalf("expected %v, got %v", ErrIdempotencyReplayMismatch, err)
	}
}

func TestServiceFinishRun_RejectsMemberSetMismatch(t *testing.T) {
	risk := &stubRiskEngine{score: 10}
	reward := &stubRewardService{}
	svc, _, _, actor := newTestServiceHarness(risk, reward, &stubRiskReporter{})

	runID, runToken := startRunForTest(t, svc, actor, []string{testHostSteamID, testPeerSteamID})
	req := buildValidFinishInput(runID, runToken, []string{testHostSteamID})

	_, err := svc.FinishRun(context.Background(), actor, runID, "idem-member-mismatch", req)
	if err != ErrMemberSetMismatch {
		t.Fatalf("expected %v, got %v", ErrMemberSetMismatch, err)
	}
}

func TestServiceFinishRun_RejectsTamperedProof(t *testing.T) {
	risk := &stubRiskEngine{score: 10}
	reward := &stubRewardService{}
	svc, _, _, actor := newTestServiceHarness(risk, reward, &stubRiskReporter{})

	runID, runToken := startRunForTest(t, svc, actor, []string{testHostSteamID, testPeerSteamID})
	req := buildValidFinishInput(runID, runToken, []string{testHostSteamID, testPeerSteamID})
	req.Proof.Segments[0].Kills++

	_, err := svc.FinishRun(context.Background(), actor, runID, "idem-proof-invalid", req)
	if err != ErrProofInvalid {
		t.Fatalf("expected %v, got %v", ErrProofInvalid, err)
	}
}

func TestServiceStartRun_SingleActiveRunPerHost(t *testing.T) {
	svc, _, _, actor := newTestServiceHarness(&stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{})

	_, _ = startRunForTest(t, svc, actor, []string{testHostSteamID, testPeerSteamID})
	_, err := svc.StartRun(context.Background(), actor, StartRunInput{
		Mode:        ModeRogueCoopV1,
		Difficulty:  2,
		Region:      "asia-east",
		HostSteamID: actor.SteamID,
		Party: []PartyMember{
			{SteamID: testHostSteamID, CharID: "char_1"},
			{SteamID: testPeerSteamID, CharID: "char_2"},
		},
		ClientBuild: "dev-test",
	})
	if err != ErrConflict {
		t.Fatalf("expected %v for second active run, got %v", ErrConflict, err)
	}
}

func TestServiceHostMigrationClaimConfirm_SuccessPromotesNewHost(t *testing.T) {
	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{}, cfg)
	hostActor := UserRef{UserID: 1001, SteamID: testHostSteamID}
	peerActor := UserRef{UserID: 1002, SteamID: testPeerSteamID}

	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID, testPeer2SteamID})
	promoted, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow)
	if err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}
	if promoted.Status != RunStatusHostMigrationWait {
		t.Fatalf("expected status %q after promote, got %q", RunStatusHostMigrationWait, promoted.Status)
	}

	claimOut, err := svc.HostMigrationClaim(context.Background(), peerActor, runID)
	if err != nil {
		t.Fatalf("host migration claim failed: %v", err)
	}
	if claimOut.CandidateSteamID != testPeerSteamID {
		t.Fatalf("expected candidate %s, got %s", testPeerSteamID, claimOut.CandidateSteamID)
	}
	if claimOut.ClaimToken == "" {
		t.Fatal("expected non-empty claim token")
	}

	confirmOut, err := svc.HostMigrationConfirm(context.Background(), peerActor, runID, RunHostMigrationConfirmInput{
		ClaimToken: claimOut.ClaimToken,
	})
	if err != nil {
		t.Fatalf("host migration confirm failed: %v", err)
	}
	if confirmOut.Status != RunStatusRunning {
		t.Fatalf("expected status %q after confirm, got %q", RunStatusRunning, confirmOut.Status)
	}
	if confirmOut.CurrentHostSteamID != testPeerSteamID {
		t.Fatalf("expected new host %s, got %s", testPeerSteamID, confirmOut.CurrentHostSteamID)
	}

	session, err := repo.GetRun(context.Background(), runID)
	if err != nil {
		t.Fatalf("get run failed: %v", err)
	}
	if session.HostSteamID != testPeerSteamID {
		t.Fatalf("expected persisted host %s, got %s", testPeerSteamID, session.HostSteamID)
	}
	if session.Status != RunStatusRunning {
		t.Fatalf("expected persisted status %q, got %q", RunStatusRunning, session.Status)
	}
}

func TestServiceHostMigrationClaim_RejectsNonCandidate(t *testing.T) {
	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{}, cfg)
	hostActor := UserRef{UserID: 1001, SteamID: testHostSteamID}
	nonCandidate := UserRef{UserID: 1003, SteamID: testPeer2SteamID}

	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID, testPeer2SteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	_, err := svc.HostMigrationClaim(context.Background(), nonCandidate, runID)
	if err != ErrForbidden {
		t.Fatalf("expected %v for non-candidate claim, got %v", ErrForbidden, err)
	}
}

func TestServiceStartRun_ConflictWhenHostInMigrationWait(t *testing.T) {
	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{}, cfg)
	hostActor := UserRef{UserID: 1001, SteamID: testHostSteamID}

	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	_, err := svc.StartRun(context.Background(), hostActor, StartRunInput{
		Mode:        ModeRogueCoopV1,
		Difficulty:  2,
		Region:      "asia-east",
		HostSteamID: hostActor.SteamID,
		Party: []PartyMember{
			{SteamID: testHostSteamID, CharID: "char_1"},
			{SteamID: testPeerSteamID, CharID: "char_2"},
		},
		ClientBuild: "dev-test",
	})
	if err != ErrConflict {
		t.Fatalf("expected %v while host is in migration wait, got %v", ErrConflict, err)
	}
}

func TestServiceHostMigrationClaim_WhenMigrationTimeoutReturnsConflict(t *testing.T) {
	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	reporter := &stubRiskReporter{}
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, reporter, cfg)
	hostActor := UserRef{UserID: 1001, SteamID: testHostSteamID}
	peerActor := UserRef{UserID: 1002, SteamID: testPeerSteamID}

	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	repo.mu.Lock()
	run := repo.runs[runID]
	expired := time.Now().UTC().Add(-2 * time.Second)
	run.HostMigrationDeadlineAt = &expired
	repo.runs[runID] = run
	repo.mu.Unlock()

	_, err := svc.HostMigrationClaim(context.Background(), peerActor, runID)
	if err != ErrConflict {
		t.Fatalf("expected %v when migration window expired, got %v", ErrConflict, err)
	}

	session, err := repo.GetRun(context.Background(), runID)
	if err != nil {
		t.Fatalf("get run failed: %v", err)
	}
	if session.Status != RunStatusAborted {
		t.Fatalf("expected status %q after timeout finalize, got %q", RunStatusAborted, session.Status)
	}
	if len(reporter.reports) == 0 {
		t.Fatal("expected reconnect timeout risk report")
	}
	last := reporter.reports[len(reporter.reports)-1]
	if len(last.Reasons) == 0 || last.Reasons[0] != RiskReasonHostReconnectTimeout {
		t.Fatalf("expected reason %s, got %+v", RiskReasonHostReconnectTimeout, last.Reasons)
	}
}

func TestServiceHostMigrationConfirm_InvalidTokenReportsRisk(t *testing.T) {
	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	reporter := &stubRiskReporter{}
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, reporter, cfg)
	hostActor := UserRef{UserID: 1001, SteamID: testHostSteamID}
	peerActor := UserRef{UserID: 1002, SteamID: testPeerSteamID}

	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID, testPeer2SteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	if _, err := svc.HostMigrationClaim(context.Background(), peerActor, runID); err != nil {
		t.Fatalf("host migration claim failed: %v", err)
	}

	_, err := svc.HostMigrationConfirm(context.Background(), peerActor, runID, RunHostMigrationConfirmInput{
		ClaimToken: "rrt_invalid_token_value",
	})
	if err != ErrReconnectTokenInvalid {
		t.Fatalf("expected %v, got %v", ErrReconnectTokenInvalid, err)
	}
	if len(reporter.reports) == 0 {
		t.Fatal("expected risk report for invalid token")
	}
	last := reporter.reports[len(reporter.reports)-1]
	if last.Source != "run_host_migration" {
		t.Fatalf("expected source run_host_migration, got %s", last.Source)
	}
	if len(last.Reasons) == 0 || last.Reasons[0] != RiskReasonReconnectTokenInvalid {
		t.Fatalf("expected reason %s, got %+v", RiskReasonReconnectTokenInvalid, last.Reasons)
	}
}

func TestServiceHostMigrationConfirm_ExpiredTokenReportsRisk(t *testing.T) {
	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	reporter := &stubRiskReporter{}
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, reporter, cfg)
	hostActor := UserRef{UserID: 1001, SteamID: testHostSteamID}
	peerActor := UserRef{UserID: 1002, SteamID: testPeerSteamID}

	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID, testPeer2SteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	claimOut, err := svc.HostMigrationClaim(context.Background(), peerActor, runID)
	if err != nil {
		t.Fatalf("host migration claim failed: %v", err)
	}

	repo.mu.Lock()
	run := repo.runs[runID]
	expired := time.Now().UTC().Add(-2 * time.Second)
	run.ReconnectTokenExpireAt = &expired
	repo.runs[runID] = run
	repo.mu.Unlock()

	_, err = svc.HostMigrationConfirm(context.Background(), peerActor, runID, RunHostMigrationConfirmInput{
		ClaimToken: claimOut.ClaimToken,
	})
	if err != ErrReconnectTokenInvalid {
		t.Fatalf("expected %v, got %v", ErrReconnectTokenInvalid, err)
	}
	if len(reporter.reports) == 0 {
		t.Fatal("expected risk report for expired token")
	}
	last := reporter.reports[len(reporter.reports)-1]
	if last.Source != "run_host_migration" {
		t.Fatalf("expected source run_host_migration, got %s", last.Source)
	}
	if len(last.Reasons) == 0 || last.Reasons[0] != RiskReasonReconnectTokenInvalid {
		t.Fatalf("expected reason %s, got %+v", RiskReasonReconnectTokenInvalid, last.Reasons)
	}
}

func TestServiceHostMigrationConfirm_TimedOutMemberReportsWindowExpiredRisk(t *testing.T) {
	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	reporter := &stubRiskReporter{}
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, reporter, cfg)
	hostActor := UserRef{UserID: 1001, SteamID: testHostSteamID}
	peerActor := UserRef{UserID: 1002, SteamID: testPeerSteamID}

	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID, testPeer2SteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	claimOut, err := svc.HostMigrationClaim(context.Background(), peerActor, runID)
	if err != nil {
		t.Fatalf("host migration claim failed: %v", err)
	}

	repo.mu.Lock()
	run := repo.runs[runID]
	for idx := range run.Party {
		if run.Party[idx].SteamID == testPeerSteamID {
			run.Party[idx].State = RunMemberStateTimedOut
			expired := time.Now().UTC().Add(-2 * time.Second)
			run.Party[idx].ReconnectDeadlineAt = &expired
			break
		}
	}
	repo.runs[runID] = run
	repo.mu.Unlock()

	_, err = svc.HostMigrationConfirm(context.Background(), peerActor, runID, RunHostMigrationConfirmInput{
		ClaimToken: claimOut.ClaimToken,
	})
	if err != ErrReconnectWindowExpired {
		t.Fatalf("expected %v, got %v", ErrReconnectWindowExpired, err)
	}
	if len(reporter.reports) == 0 {
		t.Fatal("expected risk report for reconnect window expired")
	}
	last := reporter.reports[len(reporter.reports)-1]
	if last.Source != "run_host_migration" {
		t.Fatalf("expected source run_host_migration, got %s", last.Source)
	}
	if len(last.Reasons) == 0 || last.Reasons[0] != RiskReasonReconnectWindowExpired {
		t.Fatalf("expected reason %s, got %+v", RiskReasonReconnectWindowExpired, last.Reasons)
	}
}
