package audit

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"
)

var (
	ErrInvalidArgument = errors.New("INVALID_ARGUMENT")
	ErrInternal        = errors.New("INTERNAL_ERROR")
)

type Service interface {
	LogRiskAction(ctx context.Context, adminActor string, flagID int64, action, note string) error
	LogRewardJobRetry(ctx context.Context, adminActor string, jobID int64, runID string) error
	LogRewardJobApprove(ctx context.Context, adminActor string, jobID int64, runID, note string) error
	LogRewardJobDeny(ctx context.Context, adminActor string, jobID int64, runID, note string) error
	ListLogs(ctx context.Context, input ListLogsInput) (ListLogsOutput, error)
}

type service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return &service{repo: repo}
}

func (s *service) LogRiskAction(ctx context.Context, adminActor string, flagID int64, action, note string) error {
	adminActor = strings.TrimSpace(adminActor)
	action = strings.TrimSpace(action)
	if adminActor == "" || flagID <= 0 || action == "" {
		return ErrInvalidArgument
	}

	payload := map[string]any{
		"action": action,
	}
	if strings.TrimSpace(note) != "" {
		payload["note"] = note
	}

	if err := s.repo.Create(ctx, CreateLogInput{
		AdminActor: adminActor,
		Action:     ActionRiskApply,
		TargetType: TargetTypeRiskFlag,
		TargetID:   strconv.FormatInt(flagID, 10),
		Payload:    payload,
	}, time.Now().UTC()); err != nil {
		return ErrInternal
	}
	return nil
}

func (s *service) LogRewardJobRetry(ctx context.Context, adminActor string, jobID int64, runID string) error {
	adminActor = strings.TrimSpace(adminActor)
	runID = strings.TrimSpace(runID)
	if adminActor == "" || jobID <= 0 || runID == "" {
		return ErrInvalidArgument
	}

	payload := map[string]any{
		"runId": runID,
	}

	if err := s.repo.Create(ctx, CreateLogInput{
		AdminActor: adminActor,
		Action:     ActionRewardRetry,
		TargetType: TargetTypeRewardJob,
		TargetID:   strconv.FormatInt(jobID, 10),
		Payload:    payload,
	}, time.Now().UTC()); err != nil {
		return ErrInternal
	}
	return nil
}

func (s *service) LogRewardJobApprove(ctx context.Context, adminActor string, jobID int64, runID, note string) error {
	adminActor = strings.TrimSpace(adminActor)
	runID = strings.TrimSpace(runID)
	if adminActor == "" || jobID <= 0 || runID == "" {
		return ErrInvalidArgument
	}

	payload := map[string]any{
		"runId": runID,
	}
	if strings.TrimSpace(note) != "" {
		payload["note"] = strings.TrimSpace(note)
	}

	if err := s.repo.Create(ctx, CreateLogInput{
		AdminActor: adminActor,
		Action:     ActionRewardApprove,
		TargetType: TargetTypeRewardJob,
		TargetID:   strconv.FormatInt(jobID, 10),
		Payload:    payload,
	}, time.Now().UTC()); err != nil {
		return ErrInternal
	}
	return nil
}

func (s *service) LogRewardJobDeny(ctx context.Context, adminActor string, jobID int64, runID, note string) error {
	adminActor = strings.TrimSpace(adminActor)
	runID = strings.TrimSpace(runID)
	if adminActor == "" || jobID <= 0 || runID == "" {
		return ErrInvalidArgument
	}

	payload := map[string]any{
		"runId": runID,
	}
	if strings.TrimSpace(note) != "" {
		payload["note"] = strings.TrimSpace(note)
	}

	if err := s.repo.Create(ctx, CreateLogInput{
		AdminActor: adminActor,
		Action:     ActionRewardDeny,
		TargetType: TargetTypeRewardJob,
		TargetID:   strconv.FormatInt(jobID, 10),
		Payload:    payload,
	}, time.Now().UTC()); err != nil {
		return ErrInternal
	}
	return nil
}

func (s *service) ListLogs(ctx context.Context, input ListLogsInput) (ListLogsOutput, error) {
	items, total, err := s.repo.List(ctx, input)
	if err != nil {
		return ListLogsOutput{}, ErrInternal
	}
	return ListLogsOutput{
		Items: items,
		Total: total,
	}, nil
}
