package auth

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"time"
)

var (
	ErrSteamTicketInvalid = errors.New("STEAM_TICKET_INVALID")
)

type SteamVerifier interface {
	VerifyTicket(ctx context.Context, steamID, ticket string) error
}

const (
	DefaultSteamAuthEndpoint = "https://api.steampowered.com/ISteamUserAuth/AuthenticateUserTicket/v1/"
)

type LocalSteamVerifier struct{}

func NewLocalSteamVerifier() *LocalSteamVerifier {
	return &LocalSteamVerifier{}
}

func (v *LocalSteamVerifier) VerifyTicket(_ context.Context, steamID, ticket string) error {
	steamID = strings.TrimSpace(steamID)
	ticket = strings.TrimSpace(ticket)
	if len(steamID) != 17 || len(ticket) < 10 {
		return ErrSteamTicketInvalid
	}
	return nil
}

type SteamWebVerifier struct {
	apiKey   string
	appID    string
	endpoint string
	client   *http.Client
}

func NewSteamWebVerifier(apiKey, appID, endpoint string, timeout time.Duration) *SteamWebVerifier {
	if timeout <= 0 {
		timeout = 5 * time.Second
	}
	if strings.TrimSpace(endpoint) == "" {
		endpoint = DefaultSteamAuthEndpoint
	}
	return &SteamWebVerifier{
		apiKey:   strings.TrimSpace(apiKey),
		appID:    strings.TrimSpace(appID),
		endpoint: strings.TrimSpace(endpoint),
		client: &http.Client{
			Timeout: timeout,
		},
	}
}

type steamAuthResponse struct {
	Response struct {
		Params struct {
			Result         string `json:"result"`
			SteamID        string `json:"steamid"`
			OwnerSteamID   string `json:"ownersteamid"`
			VACBanned      bool   `json:"vacbanned"`
			PublisherBanned bool  `json:"publisherbanned"`
		} `json:"params"`
	} `json:"response"`
}

func (v *SteamWebVerifier) VerifyTicket(ctx context.Context, steamID, ticket string) error {
	steamID = strings.TrimSpace(steamID)
	ticket = strings.TrimSpace(ticket)
	if len(steamID) != 17 || len(ticket) < 10 {
		return ErrSteamTicketInvalid
	}
	if v == nil || v.apiKey == "" || v.appID == "" {
		return ErrSteamTicketInvalid
	}

	endpoint, err := url.Parse(v.endpoint)
	if err != nil {
		return ErrSteamTicketInvalid
	}
	q := endpoint.Query()
	q.Set("key", v.apiKey)
	q.Set("appid", v.appID)
	q.Set("ticket", ticket)
	endpoint.RawQuery = q.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint.String(), nil)
	if err != nil {
		return ErrSteamTicketInvalid
	}

	resp, err := v.client.Do(req)
	if err != nil {
		return ErrSteamTicketInvalid
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return ErrSteamTicketInvalid
	}

	var parsed steamAuthResponse
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return ErrSteamTicketInvalid
	}

	if parsed.Response.Params.Result != "OK" {
		return ErrSteamTicketInvalid
	}
	if parsed.Response.Params.SteamID != steamID {
		return ErrSteamTicketInvalid
	}
	if parsed.Response.Params.PublisherBanned || parsed.Response.Params.VACBanned {
		return ErrSteamTicketInvalid
	}

	return nil
}
