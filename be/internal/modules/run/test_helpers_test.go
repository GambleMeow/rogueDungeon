package run

import (
	"context"
	"fmt"
	"testing"

	"github.com/google/uuid"
)

const (
	testHostSteamID  = "76561198000000001"
	testPeerSteamID  = "76561198000000002"
	testPeer2SteamID = "76561198000000003"
	testPeer3SteamID = "76561198000000004"
)

type stubRiskEngine struct {
	score   int
	reasons []string
	err     error
	calls   int
}

func (s *stubRiskEngine) Score(_ context.Context, _ RunSession, _ FinishRunInput) (int, []string, error) {
	s.calls++
	if s.err != nil {
		return 0, nil, s.err
	}
	return s.score, append([]string(nil), s.reasons...), nil
}

type stubRewardService struct {
	grantNowErr     error
	enqueueRetryErr error
	enqueueReviewErr error

	grantNowCalls     int
	enqueueRetryCalls int
	enqueueReviewCalls int

	grantNowRunID     uuid.UUID
	enqueueRetryRunID uuid.UUID
	enqueueReviewRunID uuid.UUID
}

func (s *stubRewardService) GrantNow(_ context.Context, _ UserRef, runID uuid.UUID, _ FinishRunInput) error {
	s.grantNowCalls++
	s.grantNowRunID = runID
	return s.grantNowErr
}

func (s *stubRewardService) EnqueueRetry(_ context.Context, _ UserRef, runID uuid.UUID, _ FinishRunInput) error {
	s.enqueueRetryCalls++
	s.enqueueRetryRunID = runID
	return s.enqueueRetryErr
}

func (s *stubRewardService) EnqueueReview(_ context.Context, _ UserRef, runID uuid.UUID, _ FinishRunInput) error {
	s.enqueueReviewCalls++
	s.enqueueReviewRunID = runID
	return s.enqueueReviewErr
}

type stubRiskReporter struct {
	reports []RiskReport
	err     error
}

func (s *stubRiskReporter) Report(_ context.Context, report RiskReport) error {
	if s.err != nil {
		return s.err
	}
	s.reports = append(s.reports, report)
	return nil
}

func newTestServiceHarness(risk RiskEngine, reward RewardService, reporter RiskReporter) (Service, *MemoryRepository, *MemoryIdempotencyStore, UserRef) {
	if risk == nil {
		risk = &stubRiskEngine{score: 0}
	}
	if reward == nil {
		reward = NewNoopRewardService()
	}
	if reporter == nil {
		reporter = NewNoopRiskReporter()
	}

	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	svc := NewService(repo, idem, risk, reward, reporter)

	actor := UserRef{
		UserID:  1001,
		SteamID: testHostSteamID,
	}
	return svc, repo, idem, actor
}

func startRunForTest(t *testing.T, svc Service, actor UserRef, partySteamIDs []string) (uuid.UUID, string) {
	t.Helper()

	if len(partySteamIDs) == 0 {
		partySteamIDs = []string{testHostSteamID, testPeerSteamID}
	}
	party := make([]PartyMember, 0, len(partySteamIDs))
	for idx, steamID := range partySteamIDs {
		party = append(party, PartyMember{
			SteamID: steamID,
			CharID:  fmt.Sprintf("char_%d", idx+1),
		})
	}

	out, err := svc.StartRun(context.Background(), actor, StartRunInput{
		Mode:        ModeRogueCoopV1,
		Difficulty:  2,
		Region:      "asia-east",
		HostSteamID: actor.SteamID,
		Party:       party,
		ClientBuild: "dev-test",
	})
	if err != nil {
		t.Fatalf("start run failed: %v", err)
	}

	runID, err := uuid.Parse(out.RunID)
	if err != nil {
		t.Fatalf("invalid run id: %v", err)
	}
	return runID, out.RunToken
}

func buildValidFinishInput(runID uuid.UUID, runToken string, partySteamIDs []string) FinishRunInput {
	if len(partySteamIDs) == 0 {
		partySteamIDs = []string{testHostSteamID, testPeerSteamID}
	}

	members := make([]FinishMember, 0, len(partySteamIDs))
	for _, steamID := range partySteamIDs {
		members = append(members, FinishMember{
			SteamID:     steamID,
			DamageDone:  120000,
			DownCount:   1,
			ReviveCount: 1,
			RewardDraft: []RewardDraft{
				{
					Type:   "soft_currency",
					ID:     "gold",
					Amount: 120,
				},
				{
					Type:   "item",
					ID:     "shard_alpha",
					Amount: 1,
				},
			},
		})
	}

	segments := make([]ProofSegment, 0, 10)
	for i := 0; i < 10; i++ {
		segments = append(segments, ProofSegment{
			Idx:       i,
			Kills:     10 + i,
			GoldGain:  90,
			DamageOut: 16000 + int64(i*500),
			DamageIn:  120 + int64(i*5),
		})
	}

	headHash := "proof-head-test"
	proof := buildProofFromSegments(runID, headHash, segments)

	return FinishRunInput{
		RunToken: runToken,
		Final: FinalStats{
			Result:       "win",
			ClearTimeSec: 420,
			RoomsCleared: 10,
			TeamScore:    16000,
			Deaths:       2,
		},
		Members: members,
		Proof:   proof,
		ClientMeta: ClientMeta{
			Build:         "dev-test",
			Platform:      "windows",
			AvgRTTMs:      48,
			PacketLossPct: 1.2,
		},
	}
}

func buildProofFromSegments(runID uuid.UUID, headHash string, segments []ProofSegment) ProofPayload {
	copied := make([]ProofSegment, len(segments))
	copy(copied, segments)

	prev := headHash
	for idx := range copied {
		copied[idx].Idx = idx
		payload := fmt.Sprintf("%s:%d:%d:%d:%d:%d:%s",
			runID.String(),
			copied[idx].Idx,
			copied[idx].Kills,
			copied[idx].GoldGain,
			copied[idx].DamageOut,
			copied[idx].DamageIn,
			prev,
		)
		current := sha256Hex(payload)
		copied[idx].Hash = current
		prev = current
	}

	return ProofPayload{
		SegmentSec: 30,
		HeadHash:   headHash,
		TailHash:   prev,
		Segments:   copied,
	}
}
