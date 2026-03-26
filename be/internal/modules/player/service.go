package player

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
	GetProfile(ctx context.Context, actor UserRef) (ProfileOutput, error)
	UpdateLoadout(ctx context.Context, actor UserRef, input UpdateLoadoutInput) (ProfileOutput, error)
}

type service struct {
	repo Repository
}

func NewService(repo Repository) Service {
	return &service{repo: repo}
}

func (s *service) GetProfile(ctx context.Context, actor UserRef) (ProfileOutput, error) {
	if actor.UserID <= 0 || strings.TrimSpace(actor.SteamID) == "" {
		return ProfileOutput{}, ErrUnauthorized
	}

	record, err := s.repo.GetOrCreate(ctx, actor)
	if err != nil {
		return ProfileOutput{}, ErrInternal
	}
	return toProfileOutput(record), nil
}

func (s *service) UpdateLoadout(ctx context.Context, actor UserRef, input UpdateLoadoutInput) (ProfileOutput, error) {
	if actor.UserID <= 0 || strings.TrimSpace(actor.SteamID) == "" {
		return ProfileOutput{}, ErrUnauthorized
	}
	if strings.TrimSpace(input.Loadout.CharacterID) == "" || strings.TrimSpace(input.Loadout.WeaponID) == "" {
		return ProfileOutput{}, ErrInvalidArgument
	}
	if len(input.Loadout.SkillIDs) > 8 {
		return ProfileOutput{}, ErrInvalidArgument
	}

	if _, err := s.repo.GetOrCreate(ctx, actor); err != nil {
		return ProfileOutput{}, ErrInternal
	}

	record, err := s.repo.UpdateLoadout(ctx, actor.UserID, input.Loadout, time.Now().UTC())
	if err != nil {
		return ProfileOutput{}, ErrInternal
	}
	record.SteamID = actor.SteamID
	return toProfileOutput(record), nil
}

func toProfileOutput(record ProfileRecord) ProfileOutput {
	talents := make(map[string]int, len(record.Talents))
	for key, value := range record.Talents {
		talents[key] = value
	}
	return ProfileOutput{
		UserID:       record.UserID,
		SteamID:      record.SteamID,
		Level:        record.Level,
		Exp:          record.Exp,
		TalentPoints: record.TalentPoints,
		Talents:      talents,
		Loadout: Loadout{
			CharacterID: record.Loadout.CharacterID,
			WeaponID:    record.Loadout.WeaponID,
			SkillIDs:    append([]string(nil), record.Loadout.SkillIDs...),
		},
		UpdatedAt: record.UpdatedAt,
	}
}
