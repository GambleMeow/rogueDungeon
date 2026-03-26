package run

import (
	"context"
	"strings"
	"testing"

	"github.com/google/uuid"
)

func TestVerifyProofChain_ValidChain(t *testing.T) {
	runID := uuid.New()
	segments := []ProofSegment{
		{Kills: 12, GoldGain: 80, DamageOut: 16000, DamageIn: 120},
		{Kills: 10, GoldGain: 75, DamageOut: 15000, DamageIn: 130},
		{Kills: 9, GoldGain: 90, DamageOut: 14800, DamageIn: 100},
	}
	proof := buildProofFromSegments(runID, "head-proof-ok", segments)

	if err := verifyProofChain(runID, proof); err != nil {
		t.Fatalf("expected valid proof, got error: %v", err)
	}
}

func TestVerifyProofChain_TamperedPayloadRejected(t *testing.T) {
	runID := uuid.New()
	segments := []ProofSegment{
		{Kills: 12, GoldGain: 80, DamageOut: 16000, DamageIn: 120},
		{Kills: 10, GoldGain: 75, DamageOut: 15000, DamageIn: 130},
		{Kills: 9, GoldGain: 90, DamageOut: 14800, DamageIn: 100},
	}
	proof := buildProofFromSegments(runID, "head-proof-bad", segments)

	// Tamper one counter without re-signing hash chain.
	proof.Segments[1].GoldGain++

	err := verifyProofChain(runID, proof)
	if err == nil {
		t.Fatal("expected tampered proof to be rejected, got nil")
	}
	if err != ErrProofInvalid {
		t.Fatalf("expected ErrProofInvalid, got %v", err)
	}
}

func TestBasicRiskEngine_ScoreLowRiskInput(t *testing.T) {
	engine := NewBasicRiskEngine()
	runID := uuid.New()
	run := RunSession{
		RunID:      runID,
		Difficulty: 2,
	}
	req := buildValidFinishInput(runID, "rtk_test", []string{testHostSteamID, testPeerSteamID})

	score, reasons, err := engine.Score(context.Background(), run, req)
	if err != nil {
		t.Fatalf("score returned error: %v", err)
	}
	if score != 0 {
		t.Fatalf("expected low-risk score 0, got %d with reasons %v", score, reasons)
	}
	if len(reasons) != 0 {
		t.Fatalf("expected no risk reasons, got %v", reasons)
	}
}

func TestBasicRiskEngine_ScoreHighRiskInput(t *testing.T) {
	engine := NewBasicRiskEngine()
	runID := uuid.New()
	run := RunSession{
		RunID:      runID,
		Difficulty: 3,
	}

	req := FinishRunInput{
		RunToken: "rtk_test",
		Final: FinalStats{
			Result:       "win",
			ClearTimeSec: 1000,
			RoomsCleared: 2,
			TeamScore:    999999,
			Deaths:       0,
		},
		Members: []FinishMember{
			{
				SteamID:     testHostSteamID,
				DamageDone:  5000000,
				DownCount:   0,
				ReviveCount: 10,
				RewardDraft: []RewardDraft{
					{
						Type:   "debug_illegal",
						ID:     "dev_drop",
						Amount: 1,
					},
				},
			},
		},
		Proof: ProofPayload{
			SegmentSec: 30,
			HeadHash:   "same-hash",
			TailHash:   "same-hash",
			Segments: []ProofSegment{
				{Idx: 0, Kills: 1000, GoldGain: 50000, DamageOut: 900000, DamageIn: 0, Hash: "dummyhash"},
			},
		},
		ClientMeta: ClientMeta{
			Build:         "dev-test",
			Platform:      "windows",
			AvgRTTMs:      120,
			PacketLossPct: 80,
		},
	}

	score, reasons, err := engine.Score(context.Background(), run, req)
	if err != nil {
		t.Fatalf("score returned error: %v", err)
	}
	if score < 60 {
		t.Fatalf("expected high-risk score >=60, got %d with reasons %v", score, reasons)
	}

	joined := strings.Join(reasons, ",")
	expectedReasonCodes := []string{
		"R002_SCORE_OVER_CAP",
		"R003_GOLD_RATE_SPIKE",
		"R004_DPS_OVER_CAP",
		"R008_REWARD_NOT_IN_DROPTABLE",
		"R010_DUPLICATE_FINGERPRINT",
	}
	for _, code := range expectedReasonCodes {
		if !strings.Contains(joined, code) {
			t.Fatalf("expected reason %s in reasons %v", code, reasons)
		}
	}
}
