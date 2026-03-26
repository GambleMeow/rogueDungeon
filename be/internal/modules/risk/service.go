package risk

import (
	"context"
	"errors"
	"strings"
	"time"
)

var (
	ErrInvalidArgument = errors.New("INVALID_ARGUMENT")
	ErrUnauthorized    = errors.New("UNAUTHORIZED")
	ErrInternal        = errors.New("INTERNAL_ERROR")
)

type Service interface {
	CreateFlags(ctx context.Context, input CreateFlagsInput) error
	ListFlags(ctx context.Context, input ListFlagsInput) (ListFlagsOutput, error)
	ApplyAction(ctx context.Context, id int64, input ApplyActionInput) (RiskFlag, error)
}

type service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return &service{repo: repo}
}

func (s *service) CreateFlags(ctx context.Context, input CreateFlagsInput) error {
	if input.UserID <= 0 {
		return ErrInvalidArgument
	}
	if len(input.Reasons) == 0 {
		return nil
	}
	if input.RiskScore < 0 {
		return ErrInvalidArgument
	}

	if err := s.repo.CreateFlags(ctx, input); err != nil {
		return ErrInternal
	}
	return nil
}

func (s *service) ListFlags(ctx context.Context, input ListFlagsInput) (ListFlagsOutput, error) {
	input.Status = strings.TrimSpace(input.Status)
	input.RuleCode = strings.ToUpper(strings.TrimSpace(input.RuleCode))
	input.Source = strings.ToLower(strings.TrimSpace(input.Source))
	input.Event = strings.ToLower(strings.TrimSpace(input.Event))
	if err := MustStatus(input.Status); err != nil {
		return ListFlagsOutput{}, ErrInvalidArgument
	}
	if err := MustEvent(input.Event); err != nil {
		return ListFlagsOutput{}, ErrInvalidArgument
	}

	items, total, err := s.repo.ListFlags(ctx, input)
	if err != nil {
		return ListFlagsOutput{}, ErrInternal
	}
	return ListFlagsOutput{
		Items: items,
		Total: total,
	}, nil
}

func (s *service) ApplyAction(ctx context.Context, id int64, input ApplyActionInput) (RiskFlag, error) {
	if id <= 0 {
		return RiskFlag{}, ErrInvalidArgument
	}
	input.Action = strings.TrimSpace(input.Action)
	switch input.Action {
	case ActionObserve, ActionLimitReward, ActionRollback, ActionBan:
	default:
		return RiskFlag{}, ErrInvalidArgument
	}

	flag, err := s.repo.ApplyAction(ctx, id, input, time.Now().UTC())
	if err != nil {
		if errors.Is(err, ErrFlagNotFound) {
			return RiskFlag{}, ErrFlagNotFound
		}
		return RiskFlag{}, ErrInternal
	}
	return flag, nil
}
