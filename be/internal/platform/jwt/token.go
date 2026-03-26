package jwt

import (
	"errors"
	"time"

	gjwt "github.com/golang-jwt/jwt/v5"
)

const (
	TokenTypeAccess  = "access"
	TokenTypeRefresh = "refresh"
)

var (
	ErrTokenInvalid = errors.New("token invalid")
)

type Config struct {
	Issuer     string
	Secret     string
	AccessTTL  time.Duration
	RefreshTTL time.Duration
}

type Subject struct {
	UserID  int64
	SteamID string
}

type TokenPair struct {
	AccessToken  string    `json:"accessToken"`
	RefreshToken string    `json:"refreshToken"`
	ExpiresAt    time.Time `json:"expiresAt"`
}

type Claims struct {
	UserID    int64  `json:"uid"`
	SteamID   string `json:"sid"`
	TokenType string `json:"typ"`
	gjwt.RegisteredClaims
}

type TokenManager struct {
	issuer     string
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
}

func NewTokenManager(cfg Config) *TokenManager {
	accessTTL := cfg.AccessTTL
	if accessTTL <= 0 {
		accessTTL = 15 * time.Minute
	}
	refreshTTL := cfg.RefreshTTL
	if refreshTTL <= 0 {
		refreshTTL = 7 * 24 * time.Hour
	}

	return &TokenManager{
		issuer:     cfg.Issuer,
		secret:     []byte(cfg.Secret),
		accessTTL:  accessTTL,
		refreshTTL: refreshTTL,
	}
}

func (m *TokenManager) IssueTokenPair(subject Subject) (TokenPair, error) {
	now := time.Now().UTC()
	accessToken, err := m.issueToken(subject, TokenTypeAccess, now.Add(m.accessTTL))
	if err != nil {
		return TokenPair{}, err
	}

	refreshToken, err := m.issueToken(subject, TokenTypeRefresh, now.Add(m.refreshTTL))
	if err != nil {
		return TokenPair{}, err
	}

	return TokenPair{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
		ExpiresAt:    now.Add(m.accessTTL),
	}, nil
}

func (m *TokenManager) ParseToken(raw string, expectedType string) (Subject, error) {
	token, err := gjwt.ParseWithClaims(raw, &Claims{}, func(token *gjwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*gjwt.SigningMethodHMAC); !ok {
			return nil, ErrTokenInvalid
		}
		return m.secret, nil
	})
	if err != nil {
		return Subject{}, ErrTokenInvalid
	}

	claims, ok := token.Claims.(*Claims)
	if !ok || !token.Valid {
		return Subject{}, ErrTokenInvalid
	}
	if claims.Issuer != m.issuer || claims.TokenType != expectedType {
		return Subject{}, ErrTokenInvalid
	}
	if claims.UserID <= 0 || claims.SteamID == "" {
		return Subject{}, ErrTokenInvalid
	}

	return Subject{
		UserID:  claims.UserID,
		SteamID: claims.SteamID,
	}, nil
}

func (m *TokenManager) issueToken(subject Subject, tokenType string, exp time.Time) (string, error) {
	claims := Claims{
		UserID:    subject.UserID,
		SteamID:   subject.SteamID,
		TokenType: tokenType,
		RegisteredClaims: gjwt.RegisteredClaims{
			Issuer:    m.issuer,
			Subject:   subject.SteamID,
			ExpiresAt: gjwt.NewNumericDate(exp),
			IssuedAt:  gjwt.NewNumericDate(time.Now().UTC()),
		},
	}

	token := gjwt.NewWithClaims(gjwt.SigningMethodHS256, claims)
	return token.SignedString(m.secret)
}
