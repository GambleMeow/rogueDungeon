package commerce

import "time"

type UserRef struct {
	UserID  int64
	SteamID string
}

type CatalogItem struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Price    int    `json:"price"`
	Currency string `json:"currency"`
}

type CatalogOutput struct {
	Items []CatalogItem `json:"items"`
}

type SyncEntitlementsInput struct {
	OwnedDLCIDs []int `json:"ownedDlcIds" binding:"max=128,dive,min=1"`
}

type SyncEntitlementsOutput struct {
	UserID      int64     `json:"userId"`
	SteamID     string    `json:"steamId"`
	OwnedDLCIDs []int     `json:"ownedDlcIds"`
	SyncedAt    time.Time `json:"syncedAt"`
}
