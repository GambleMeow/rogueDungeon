package audit

import "time"

const (
	TargetTypeRiskFlag = "risk_flag"
	TargetTypeRewardJob = "reward_job"
	ActionRiskApply    = "risk_apply_action"
	ActionRewardRetry  = "reward_retry"
	ActionRewardApprove = "reward_approve"
	ActionRewardDeny   = "reward_deny"
)

type LogEntry struct {
	ID         int64          `json:"id"`
	AdminActor string         `json:"adminActor"`
	Action     string         `json:"action"`
	TargetType string         `json:"targetType"`
	TargetID   string         `json:"targetId"`
	Payload    map[string]any `json:"payload"`
	CreatedAt  time.Time      `json:"createdAt"`
}

type ListLogsInput struct {
	Limit  int `form:"limit"`
	Offset int `form:"offset"`
}

type ListLogsOutput struct {
	Items []LogEntry `json:"items"`
	Total int        `json:"total"`
}

type CreateLogInput struct {
	AdminActor string
	Action     string
	TargetType string
	TargetID   string
	Payload    map[string]any
}
