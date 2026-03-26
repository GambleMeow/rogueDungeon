package auth

import "time"

type SteamLoginInput struct {
	SteamID     string `json:"steamId" binding:"required,len=17,numeric"`
	SteamTicket string `json:"steamTicket" binding:"required,min=10,max=2048"`
}

type RefreshInput struct {
	RefreshToken string `json:"refreshToken" binding:"required,min=16,max=4096"`
}

type LoginOutput struct {
	UserID       int64     `json:"userId"`
	SteamID      string    `json:"steamId"`
	AccessToken  string    `json:"accessToken"`
	RefreshToken string    `json:"refreshToken"`
	ExpiresAt    time.Time `json:"expiresAt"`
}

type User struct {
	UserID    int64
	SteamID   string
	CreatedAt time.Time
	LastLogin time.Time
}
