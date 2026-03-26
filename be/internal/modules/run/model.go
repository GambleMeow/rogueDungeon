package run

import (
	"time"

	"github.com/google/uuid"

	"rogue-dungeon-backend/internal/common/identity"
)

const (
	ModeRogueCoopV1 = "rogue_coop_v1"
)

const (
	VerdictAccepted      = "accepted"
	VerdictPendingReview = "pending_review"
	VerdictRejected      = "rejected"
)

const (
	RewardStatusGranted = "granted"
	RewardStatusDelayed = "delayed"
	RewardStatusDenied  = "denied"
)

type RunStatus string

const (
	RunStatusRunning           RunStatus = "running"
	RunStatusHostMigrationWait RunStatus = "host_migration_wait"
	RunStatusCompleted         RunStatus = "completed"
	RunStatusAborted           RunStatus = "aborted"
	RunStatusInvalid           RunStatus = "invalid"
)

const (
	RunMemberStateOnline       = "online"
	RunMemberStateReconnecting = "reconnecting"
	RunMemberStateTimedOut     = "timed_out"
)

type UserRef = identity.Actor

type PartyMember struct {
	SteamID string `json:"steamId" binding:"required,len=17,numeric"`
	CharID  string `json:"charId" binding:"required,min=1,max=32"`
}

type StartRunInput struct {
	Mode        string        `json:"mode" binding:"required,oneof=rogue_coop_v1"`
	Difficulty  int           `json:"difficulty" binding:"required,min=1,max=5"`
	Region      string        `json:"region" binding:"required,min=2,max=32"`
	HostSteamID string        `json:"hostSteamId" binding:"required,len=17,numeric"`
	Party       []PartyMember `json:"party" binding:"required,min=1,max=4,dive"`
	ClientBuild string        `json:"clientBuild" binding:"required,min=1,max=32"`
	DLCContext  []string      `json:"dlcContext"`
}

type ProofRule struct {
	Version          string   `json:"version"`
	SegmentSec       int      `json:"segmentSec"`
	HashAlgo         string   `json:"hashAlgo"`
	RequiredCounters []string `json:"requiredCounters"`
}

type StartRunOutput struct {
	RunID             string    `json:"runId"`
	Seed              string    `json:"seed"`
	RunToken          string    `json:"runToken"`
	TokenExpireAt     time.Time `json:"tokenExpireAt"`
	SubmitDeadlineSec int       `json:"submitDeadlineSec"`
	ProofRule         ProofRule `json:"proofRule"`
}

type RewardDraft struct {
	Type   string `json:"type" binding:"required,min=1,max=32"`
	ID     string `json:"id" binding:"required,min=1,max=64"`
	Amount int    `json:"amount" binding:"required,min=1"`
}

type FinishMember struct {
	SteamID     string        `json:"steamId" binding:"required,len=17,numeric"`
	DamageDone  int64         `json:"damageDone" binding:"min=0"`
	DownCount   int           `json:"downCount" binding:"min=0"`
	ReviveCount int           `json:"reviveCount" binding:"min=0"`
	RewardDraft []RewardDraft `json:"rewardDraft" binding:"required,dive"`
}

type FinalStats struct {
	Result       string `json:"result" binding:"required,oneof=win lose abort"`
	ClearTimeSec int    `json:"clearTimeSec" binding:"min=0"`
	RoomsCleared int    `json:"roomsCleared" binding:"min=0"`
	TeamScore    int    `json:"teamScore" binding:"min=0"`
	Deaths       int    `json:"deaths" binding:"min=0"`
}

type ProofSegment struct {
	Idx       int    `json:"idx" binding:"min=0"`
	Kills     int    `json:"kills" binding:"min=0"`
	GoldGain  int    `json:"goldGain" binding:"min=0"`
	DamageOut int64  `json:"damageOut" binding:"min=0"`
	DamageIn  int64  `json:"damageIn" binding:"min=0"`
	Hash      string `json:"hash" binding:"required,min=8"`
}

type ProofPayload struct {
	SegmentSec int            `json:"segmentSec" binding:"required,eq=30"`
	HeadHash   string         `json:"headHash" binding:"required,min=8"`
	TailHash   string         `json:"tailHash" binding:"required,min=8"`
	Segments   []ProofSegment `json:"segments" binding:"required,min=1,dive"`
}

type ClientMeta struct {
	Build         string  `json:"build" binding:"required,min=1,max=32"`
	Platform      string  `json:"platform" binding:"required,min=1,max=32"`
	AvgRTTMs      int     `json:"avgRttMs" binding:"min=0"`
	PacketLossPct float64 `json:"packetLossPct" binding:"gte=0,lte=100"`
}

type FinishRunInput struct {
	RunToken   string         `json:"runToken" binding:"required,min=8,max=256"`
	Final      FinalStats     `json:"final" binding:"required"`
	Members    []FinishMember `json:"members" binding:"required,min=1,max=4,dive"`
	Proof      ProofPayload   `json:"proof" binding:"required"`
	ClientMeta ClientMeta     `json:"clientMeta" binding:"required"`
}

type FinishRunOutput struct {
	RunID            string `json:"runId"`
	Verdict          string `json:"verdict"`
	RiskScore        int    `json:"riskScore"`
	RewardStatus     string `json:"rewardStatus"`
	NextPollAfterSec int    `json:"nextPollAfterSec,omitempty"`
}

type GetRunOutput struct {
	RunID        string     `json:"runId"`
	Status       RunStatus  `json:"status"`
	StartedAt    time.Time  `json:"startedAt"`
	EndedAt      *time.Time `json:"endedAt,omitempty"`
	Verdict      string     `json:"verdict,omitempty"`
	RiskScore    int        `json:"riskScore,omitempty"`
	RewardStatus string     `json:"rewardStatus,omitempty"`
}

type RunPartyMemberDetail struct {
	SteamID             string     `json:"steamId"`
	CharID              string     `json:"charId"`
	State               string     `json:"state,omitempty"`
	LastSeenAt          *time.Time `json:"lastSeenAt,omitempty"`
	ReconnectDeadlineAt *time.Time `json:"reconnectDeadlineAt,omitempty"`
}

type RunProofSummary struct {
	SegmentSec   int    `json:"segmentSec"`
	SegmentCount int    `json:"segmentCount"`
	HeadHash     string `json:"headHash"`
	TailHash     string `json:"tailHash"`
}

type RunResultDetail struct {
	SubmittedBySteamID string          `json:"submittedBySteamId"`
	SubmittedAt        time.Time       `json:"submittedAt"`
	Verdict            string          `json:"verdict"`
	RiskScore          int             `json:"riskScore"`
	RewardStatus       string          `json:"rewardStatus"`
	Final              FinalStats      `json:"final"`
	Members            []FinishMember  `json:"members"`
	ClientMeta         ClientMeta      `json:"clientMeta"`
	Proof              RunProofSummary `json:"proof"`
}

type GetRunDetailOutput struct {
	RunID      string                 `json:"runId"`
	Mode       string                 `json:"mode"`
	Difficulty int                    `json:"difficulty"`
	Region     string                 `json:"region"`
	Status     RunStatus              `json:"status"`
	IsHost     bool                   `json:"isHost"`
	Party      []RunPartyMemberDetail `json:"party"`
	StartedAt  time.Time              `json:"startedAt"`
	EndedAt    *time.Time             `json:"endedAt,omitempty"`
	Result     *RunResultDetail       `json:"result,omitempty"`
}

type RunReasonItem struct {
	Code        string `json:"code"`
	Severity    string `json:"severity"`
	Weight      int    `json:"weight"`
	Title       string `json:"title"`
	Description string `json:"description"`
}

type GetRunReasonsOutput struct {
	RunID     string          `json:"runId"`
	Status    RunStatus       `json:"status"`
	Verdict   string          `json:"verdict,omitempty"`
	RiskScore int             `json:"riskScore"`
	Reasons   []RunReasonItem `json:"reasons"`
	Total     int             `json:"total"`
}

type RunHeartbeatInput struct {
	OnlineSteamIDs []string `json:"onlineSteamIds" binding:"max=4,dive,len=17,numeric"`
}

type RunHeartbeatMember struct {
	SteamID             string     `json:"steamId"`
	State               string     `json:"state"`
	LastSeenAt          *time.Time `json:"lastSeenAt,omitempty"`
	ReconnectDeadlineAt *time.Time `json:"reconnectDeadlineAt,omitempty"`
}

type RunHeartbeatOutput struct {
	RunID                    string               `json:"runId"`
	CurrentHostSteamID       string               `json:"currentHostSteamId"`
	Status                   RunStatus            `json:"status"`
	MigrationEpoch           int64                `json:"migrationEpoch"`
	HostLastHeartbeatAt      *time.Time           `json:"hostLastHeartbeatAt,omitempty"`
	HostReconnectDeadlineAt  *time.Time           `json:"hostReconnectDeadlineAt,omitempty"`
	HostMigrationDeadlineAt  *time.Time           `json:"hostMigrationDeadlineAt,omitempty"`
	HostReconnectWindowSec   int                  `json:"hostReconnectWindowSec"`
	PlayerReconnectWindowSec int                  `json:"playerReconnectWindowSec"`
	Members                  []RunHeartbeatMember `json:"members"`
}

type RunReconnectRequestOutput struct {
	RunID                   string     `json:"runId"`
	ResumeToken             string     `json:"resumeToken"`
	ExpireAt                time.Time  `json:"expireAt"`
	HostReconnectDeadlineAt *time.Time `json:"hostReconnectDeadlineAt,omitempty"`
}

type RunReconnectConfirmInput struct {
	ResumeToken string `json:"resumeToken" binding:"required,min=16,max=256"`
}

type RunHostMigrationClaimOutput struct {
	RunID                   string     `json:"runId"`
	Status                  RunStatus  `json:"status"`
	MigrationEpoch          int64      `json:"migrationEpoch"`
	CandidateSteamID        string     `json:"candidateSteamId"`
	ClaimToken              string     `json:"claimToken"`
	ClaimTokenExpireAt      time.Time  `json:"claimTokenExpireAt"`
	HostMigrationDeadlineAt *time.Time `json:"hostMigrationDeadlineAt,omitempty"`
}

type RunHostMigrationConfirmInput struct {
	ClaimToken string `json:"claimToken" binding:"required,min=16,max=256"`
}

type ListRunsInput struct {
	Status       string `form:"status"`
	Verdict      string `form:"verdict"`
	RewardStatus string `form:"rewardStatus"`
	Mode         string `form:"mode"`
	Order        string `form:"order"`
	Limit        int    `form:"limit"`
	Offset       int    `form:"offset"`
}

type RunHistoryItem struct {
	RunID        string     `json:"runId"`
	Mode         string     `json:"mode"`
	Difficulty   int        `json:"difficulty"`
	Region       string     `json:"region"`
	Status       RunStatus  `json:"status"`
	PartySize    int        `json:"partySize"`
	IsHost       bool       `json:"isHost"`
	StartedAt    time.Time  `json:"startedAt"`
	EndedAt      *time.Time `json:"endedAt,omitempty"`
	SubmittedAt  *time.Time `json:"submittedAt,omitempty"`
	Verdict      string     `json:"verdict,omitempty"`
	RiskScore    *int       `json:"riskScore,omitempty"`
	RewardStatus string     `json:"rewardStatus,omitempty"`
}

type ListRunsOutput struct {
	Items []RunHistoryItem `json:"items"`
	Total int              `json:"total"`
}

type RunMember struct {
	SteamID             string
	CharID              string
	State               string
	LastSeenAt          *time.Time
	ReconnectDeadlineAt *time.Time
}

type RunSession struct {
	RunID                   uuid.UUID
	Seed                    int64
	RunTokenHash            string
	HostUserID              int64
	HostSteamID             string
	Mode                    string
	Difficulty              int
	Region                  string
	Party                   []RunMember
	Status                  RunStatus
	StartedAt               time.Time
	EndedAt                 *time.Time
	HostLastHeartbeatAt     *time.Time
	HostReconnectDeadlineAt *time.Time
	HostMigrationDeadlineAt *time.Time
	MigrationEpoch          int64
	ReconnectTokenHash      string
	ReconnectTokenSteamID   string
	ReconnectTokenExpireAt  *time.Time
}

type StoredRunResult struct {
	RunID              uuid.UUID
	SubmittedBySteamID string
	RiskScore          int
	RiskReasons        []string
	Verdict            string
	RewardStatus       string
	Payload            FinishRunInput
	CreatedAt          time.Time
}

type IdempotencyRecord struct {
	Key         string
	RequestHash string
	Response    FinishRunOutput
	CreatedAt   time.Time
}
