package run

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"

	"github.com/google/uuid"
)

func verifyProofChain(runID uuid.UUID, proof ProofPayload) error {
	if proof.SegmentSec != 30 || len(proof.Segments) == 0 {
		return ErrProofInvalid
	}

	segments := make([]ProofSegment, len(proof.Segments))
	copy(segments, proof.Segments)
	sort.Slice(segments, func(i, j int) bool {
		return segments[i].Idx < segments[j].Idx
	})

	prev := proof.HeadHash
	for idx, segment := range segments {
		if segment.Idx != idx {
			return ErrProofInvalid
		}

		payload := fmt.Sprintf("%s:%d:%d:%d:%d:%d:%s",
			runID.String(),
			segment.Idx,
			segment.Kills,
			segment.GoldGain,
			segment.DamageOut,
			segment.DamageIn,
			prev,
		)
		expected := sha256Hex(payload)
		if !strings.EqualFold(expected, segment.Hash) {
			return ErrProofInvalid
		}
		prev = expected
	}

	if !strings.EqualFold(prev, proof.TailHash) {
		return ErrProofInvalid
	}
	return nil
}

type BasicRiskEngine struct{}

func NewBasicRiskEngine() *BasicRiskEngine {
	return &BasicRiskEngine{}
}

func (e *BasicRiskEngine) Score(_ context.Context, run RunSession, req FinishRunInput) (int, []string, error) {
	score := 0
	reasons := make([]string, 0, 8)
	addReason := func(code string, value int) {
		score += value
		reasons = append(reasons, code)
	}

	// R001: duration anomaly
	minSec := max(120, req.Final.RoomsCleared*(40-run.Difficulty*2))
	maxSec := req.Final.RoomsCleared*420 + run.Difficulty*120
	if req.Final.ClearTimeSec < minSec || req.Final.ClearTimeSec > maxSec {
		addReason("R001_DURATION_ANOMALY", 16)
	}

	// R002: score over expected cap
	scoreCap := req.Final.RoomsCleared * (3200 + run.Difficulty*600)
	if req.Final.TeamScore > scoreCap {
		addReason("R002_SCORE_OVER_CAP", 18)
	}

	// R003: gold gain rate spike
	totalGold := 0
	for _, seg := range req.Proof.Segments {
		totalGold += seg.GoldGain
	}
	minutes := max(1.0, float64(req.Final.ClearTimeSec)/60.0)
	goldPerMin := float64(totalGold) / minutes
	if goldPerMin > float64(1200+run.Difficulty*180) {
		addReason("R003_GOLD_RATE_SPIKE", 12)
	}

	// R004: member DPS over cap
	dpsLimit := float64(2800 + run.Difficulty*450)
	for _, member := range req.Members {
		dps := float64(member.DamageDone) / max(1.0, float64(req.Final.ClearTimeSec))
		if dps > dpsLimit {
			addReason("R004_DPS_OVER_CAP", 14)
			break
		}
	}

	// R005: kill and room count mismatch
	totalKills := 0
	for _, seg := range req.Proof.Segments {
		totalKills += seg.Kills
	}
	if totalKills > req.Final.RoomsCleared*220 {
		addReason("R005_KILL_ROOM_MISMATCH", 10)
	}

	// R006: near-zero incoming damage in long run
	totalDamageIn := int64(0)
	for _, seg := range req.Proof.Segments {
		totalDamageIn += seg.DamageIn
	}
	if req.Final.ClearTimeSec > 900 && totalDamageIn < 100 {
		addReason("R006_ZERO_DAMAGE_IN_LONG_RUN", 8)
	}

	// R007: down and revive counters inconsistent
	totalDown := 0
	totalRevive := 0
	for _, member := range req.Members {
		totalDown += member.DownCount
		totalRevive += member.ReviveCount
	}
	if totalRevive > totalDown+4 {
		addReason("R007_DOWN_REVIVE_INCONSISTENT", 8)
	}

	// R008: reward type outside allowed drop categories
	allowedRewardType := map[string]struct{}{
		"soft_currency": {},
		"item":          {},
		"cosmetic":      {},
	}
	for _, member := range req.Members {
		for _, reward := range member.RewardDraft {
			if _, ok := allowedRewardType[reward.Type]; !ok {
				addReason("R008_REWARD_NOT_IN_DROPTABLE", 12)
				goto rewardTypeCheckDone
			}
		}
	}
rewardTypeCheckDone:

	// R009: sparse proof segments (chain validity checked elsewhere)
	if len(req.Proof.Segments) < int(math.Ceil(float64(req.Final.ClearTimeSec)/45.0)) {
		addReason("R009_PROOF_SEGMENT_TOO_SPARSE", 6)
	}

	// R010: duplicate fingerprint signal (same head and tail hash)
	if strings.EqualFold(req.Proof.HeadHash, req.Proof.TailHash) {
		addReason("R010_DUPLICATE_FINGERPRINT", 6)
	}

	// R011: invalid member count
	if len(req.Members) > 4 || len(req.Members) == 0 {
		addReason("R011_MEMBER_SET_MISMATCH", 20)
	}

	// R012: abnormal client environment
	if req.ClientMeta.PacketLossPct > 70 || strings.TrimSpace(req.ClientMeta.Build) == "" {
		addReason("R012_BUILD_OR_ENV_ABNORMAL", 5)
	}

	return score, reasons, nil
}
