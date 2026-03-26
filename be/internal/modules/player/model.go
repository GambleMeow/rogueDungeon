package player

import "time"

type UserRef struct {
	UserID  int64
	SteamID string
}

type Loadout struct {
	CharacterID string   `json:"characterId" binding:"required,min=1,max=32"`
	WeaponID    string   `json:"weaponId" binding:"required,min=1,max=32"`
	SkillIDs    []string `json:"skillIds" binding:"max=8"`
}

type UpdateLoadoutInput struct {
	Loadout Loadout `json:"loadout" binding:"required"`
}

type ProfileOutput struct {
	UserID       int64          `json:"userId"`
	SteamID      string         `json:"steamId"`
	Level        int            `json:"level"`
	Exp          int            `json:"exp"`
	TalentPoints int            `json:"talentPoints"`
	Talents      map[string]int `json:"talents"`
	Loadout      Loadout        `json:"loadout"`
	UpdatedAt    time.Time      `json:"updatedAt"`
}

type ProfileRecord struct {
	UserID       int64
	SteamID      string
	Level        int
	Exp          int
	TalentPoints int
	Talents      map[string]int
	Loadout      Loadout
	UpdatedAt    time.Time
}
