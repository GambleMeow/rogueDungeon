package risk

import (
	"time"

	"github.com/google/uuid"
)

const (
	StatusPending       = "pending"
	StatusProcessed     = "processed"
	StatusFalsePositive = "false_positive"
	StatusIgnored       = "ignored"
)

const (
	ActionObserve     = "observe"
	ActionLimitReward = "limit_reward"
	ActionRollback    = "rollback"
	ActionBan         = "ban"
)

const (
	EventReconnect        = "reconnect"
	EventReconnectFailed  = "reconnect_failed"
	EventReconnectTimeout = "reconnect_timeout"
)

type ListFlagsInput struct {
	Status   string `form:"status"`
	RuleCode string `form:"ruleCode"`
	Source   string `form:"source"`
	Event    string `form:"event"`
	Limit    int    `form:"limit"`
	Offset   int    `form:"offset"`
}

type ApplyActionInput struct {
	Action string `json:"action" binding:"required,oneof=observe limit_reward rollback ban"`
	Note   string `json:"note" binding:"max=512"`
}

type RiskFlag struct {
	ID        int64          `json:"id"`
	UserID    int64          `json:"userId"`
	RunID     string         `json:"runId,omitempty"`
	RuleCode  string         `json:"ruleCode"`
	Score     int            `json:"score"`
	Evidence  map[string]any `json:"evidence"`
	Action    string         `json:"action"`
	Status    string         `json:"status"`
	Note      string         `json:"note,omitempty"`
	CreatedAt time.Time      `json:"createdAt"`
	HandledAt *time.Time     `json:"handledAt,omitempty"`
}

type ListFlagsOutput struct {
	Items []RiskFlag `json:"items"`
	Total int        `json:"total"`
}

type CreateFlagsInput struct {
	UserID    int64
	RunID     uuid.UUID
	RiskScore int
	Reasons   []string
	Evidence  map[string]any
}

func reconnectEventRuleCodes(event string) []string {
	switch event {
	case EventReconnect:
		return []string{
			"R013_HOST_RECONNECT_TIMEOUT",
			"R014_RECONNECT_TOKEN_INVALID",
			"R015_RECONNECT_WINDOW_EXPIRED",
		}
	case EventReconnectFailed:
		return []string{
			"R014_RECONNECT_TOKEN_INVALID",
		}
	case EventReconnectTimeout:
		return []string{
			"R013_HOST_RECONNECT_TIMEOUT",
			"R015_RECONNECT_WINDOW_EXPIRED",
		}
	default:
		return nil
	}
}
