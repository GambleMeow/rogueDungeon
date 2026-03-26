package inventory

import "time"

type UserRef struct {
	UserID  int64
	SteamID string
}

type Item struct {
	ID     string `json:"id"`
	Amount int    `json:"amount"`
}

type RewardGrant struct {
	Type   string
	ID     string
	Amount int
}

type InventoryOutput struct {
	UserID       int64     `json:"userId"`
	SteamID      string    `json:"steamId"`
	SoftCurrency int       `json:"softCurrency"`
	HardCurrency int       `json:"hardCurrency"`
	Items        []Item    `json:"items"`
	Cosmetics    []string  `json:"cosmetics"`
	UpdatedAt    time.Time `json:"updatedAt"`
}

type InventoryRecord struct {
	UserID       int64
	SteamID      string
	SoftCurrency int
	HardCurrency int
	Items        []Item
	Cosmetics    []string
	UpdatedAt    time.Time
}
