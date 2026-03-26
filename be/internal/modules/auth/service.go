package auth

import (
	"context"
	"errors"
	"strings"
	"time"

	appjwt "rogue-dungeon-backend/internal/platform/jwt"
)

var (
	ErrInvalidArgument = errors.New("INVALID_ARGUMENT")
	ErrUnauthorized    = errors.New("UNAUTHORIZED")
	ErrInternal        = errors.New("INTERNAL_ERROR")
)

type Service interface {
	SteamLogin(ctx context.Context, input SteamLoginInput) (LoginOutput, error)
	Refresh(ctx context.Context, input RefreshInput) (LoginOutput, error)
}

type service struct {
	repo      Repository
	verifier  SteamVerifier
	tokenMgr  *appjwt.TokenManager
}

func NewService(repo Repository, verifier SteamVerifier, tokenMgr *appjwt.TokenManager) Service {
	return &service{
		repo:     repo,
		verifier: verifier,
		tokenMgr: tokenMgr,
	}
}

func (s *service) SteamLogin(ctx context.Context, input SteamLoginInput) (LoginOutput, error) {
	if strings.TrimSpace(input.SteamID) == "" || strings.TrimSpace(input.SteamTicket) == "" {
		return LoginOutput{}, ErrInvalidArgument
	}

	if err := s.verifier.VerifyTicket(ctx, input.SteamID, input.SteamTicket); err != nil {
		return LoginOutput{}, ErrUnauthorized
	}

	user, err := s.repo.GetBySteamID(ctx, input.SteamID)
	if err != nil {
		if errors.Is(err, ErrUserNotFound) {
			user, err = s.repo.Create(ctx, input.SteamID)
			if err != nil {
				return LoginOutput{}, ErrInternal
			}
		} else {
			return LoginOutput{}, ErrInternal
		}
	}

	now := time.Now().UTC()
	if err := s.repo.TouchLogin(ctx, input.SteamID, now); err != nil {
		return LoginOutput{}, ErrInternal
	}

	pair, err := s.tokenMgr.IssueTokenPair(appjwt.Subject{
		UserID:  user.UserID,
		SteamID: user.SteamID,
	})
	if err != nil {
		return LoginOutput{}, ErrInternal
	}

	return LoginOutput{
		UserID:       user.UserID,
		SteamID:      user.SteamID,
		AccessToken:  pair.AccessToken,
		RefreshToken: pair.RefreshToken,
		ExpiresAt:    pair.ExpiresAt,
	}, nil
}

func (s *service) Refresh(ctx context.Context, input RefreshInput) (LoginOutput, error) {
	if strings.TrimSpace(input.RefreshToken) == "" {
		return LoginOutput{}, ErrInvalidArgument
	}

	subject, err := s.tokenMgr.ParseToken(input.RefreshToken, appjwt.TokenTypeRefresh)
	if err != nil {
		return LoginOutput{}, ErrUnauthorized
	}

	user, err := s.repo.GetBySteamID(ctx, subject.SteamID)
	if err != nil {
		if errors.Is(err, ErrUserNotFound) {
			return LoginOutput{}, ErrUnauthorized
		}
		return LoginOutput{}, ErrInternal
	}

	pair, err := s.tokenMgr.IssueTokenPair(appjwt.Subject{
		UserID:  user.UserID,
		SteamID: user.SteamID,
	})
	if err != nil {
		return LoginOutput{}, ErrInternal
	}

	return LoginOutput{
		UserID:       user.UserID,
		SteamID:      user.SteamID,
		AccessToken:  pair.AccessToken,
		RefreshToken: pair.RefreshToken,
		ExpiresAt:    pair.ExpiresAt,
	}, nil
}
