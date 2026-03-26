package run

import (
	"context"
	"errors"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

var ErrRewardJobNotFound = errors.New("REWARD_JOB_NOT_FOUND")

const (
	RewardJobStatusPending    = "pending"
	RewardJobStatusProcessing = "processing"
	RewardJobStatusCompleted  = "completed"
	RewardJobStatusFailed     = "failed"
)

type RewardJobMember struct {
	SteamID string       `json:"steamId"`
	Rewards []RewardDraft `json:"rewards"`
}

type RewardJob struct {
	ID          int64             `json:"id"`
	RunID       string            `json:"runId"`
	Members     []RewardJobMember `json:"members"`
	ManualOnly  bool              `json:"manualOnly"`
	Status      string            `json:"status"`
	Attempts    int               `json:"attempts"`
	LastError   string            `json:"lastError,omitempty"`
	NextRetryAt time.Time         `json:"nextRetryAt"`
	CreatedAt   time.Time         `json:"createdAt"`
	UpdatedAt   time.Time         `json:"updatedAt"`
}

type ListRewardJobsInput struct {
	Status     string `form:"status"`
	RunID      string `form:"runId"`
	ManualOnly string `form:"manualOnly"`
	CreatedFrom string `form:"createdFrom"`
	CreatedTo   string `form:"createdTo"`
	OrderBy    string `form:"orderBy"`
	Order      string `form:"order"`
	Limit      int    `form:"limit"`
	Offset     int    `form:"offset"`
}

type ListRewardJobsOutput struct {
	Items []RewardJob `json:"items"`
	Total int         `json:"total"`
}

type RewardJobStatsInput struct {
	Status      string `form:"status"`
	RunID       string `form:"runId"`
	ManualOnly  string `form:"manualOnly"`
	CreatedFrom string `form:"createdFrom"`
	CreatedTo   string `form:"createdTo"`
	GroupBy     string `form:"groupBy"`
	TZ          string `form:"tz"`
}

type RewardJobStatsTrendItem struct {
	Bucket          string `json:"bucket"`
	Day             string `json:"day"`
	Label           string `json:"label"`
	Total           int    `json:"total"`
	Pending         int    `json:"pending"`
	Processing      int    `json:"processing"`
	Completed       int    `json:"completed"`
	Failed          int    `json:"failed"`
	ManualOnlyTrue  int    `json:"manualOnlyTrue"`
	ManualOnlyFalse int    `json:"manualOnlyFalse"`
}

type RewardJobStatsOutput struct {
	Total           int                    `json:"total"`
	Pending         int                    `json:"pending"`
	Processing      int                    `json:"processing"`
	Completed       int                    `json:"completed"`
	Failed          int                    `json:"failed"`
	ManualOnlyTrue  int                    `json:"manualOnlyTrue"`
	ManualOnlyFalse int                    `json:"manualOnlyFalse"`
	Timezone        string                 `json:"timezone"`
	Trend           []RewardJobStatsTrendItem `json:"trend,omitempty"`
}

type RewardJobTimezoneAlias struct {
	Alias    string `json:"alias"`
	Timezone string `json:"timezone"`
}

type RewardJobFrontendDefaults struct {
	StatsGroupBy  string `json:"statsGroupBy"`
	StatsTimezone string `json:"statsTimezone"`
}

type RewardJobTimezonesOutput struct {
	DefaultTimezone          string                  `json:"defaultTimezone"`
	Timezones                []string                `json:"timezones"`
	Aliases                  []RewardJobTimezoneAlias `json:"aliases"`
	DeprecatedAliases        []string                `json:"deprecatedAliases"`
	PreferredTimezoneExamples []string               `json:"preferredTimezoneExamples"`
	FrontendDefaults         RewardJobFrontendDefaults `json:"frontendDefaults"`
}

type RewardJobStore interface {
	EnqueueDelayed(ctx context.Context, runID uuid.UUID, members []FinishMember, availableAt time.Time, manualOnly bool) error
	List(ctx context.Context, input ListRewardJobsInput) ([]RewardJob, int, error)
	Stats(ctx context.Context, input RewardJobStatsInput) (RewardJobStatsOutput, error)
	GetByID(ctx context.Context, id int64) (RewardJob, error)
	RetryNow(ctx context.Context, id int64, at time.Time) (RewardJob, error)
	DenyNow(ctx context.Context, id int64, reason string, at time.Time) (RewardJob, error)
	ClaimDue(ctx context.Context, limit int, now time.Time) ([]RewardJob, error)
	MarkCompleted(ctx context.Context, id int64, at time.Time) error
	MarkRetry(ctx context.Context, id int64, nextRetryAt time.Time, lastError string, at time.Time) error
	MarkFailed(ctx context.Context, id int64, lastError string, at time.Time) error
}

type MemoryRewardJobStore struct {
	mu      sync.RWMutex
	autoID  int64
	jobs    map[int64]RewardJob
	runToID map[uuid.UUID]int64
}

func NewMemoryRewardJobStore() *MemoryRewardJobStore {
	return &MemoryRewardJobStore{
		autoID:  1,
		jobs:    make(map[int64]RewardJob),
		runToID: make(map[uuid.UUID]int64),
	}
}

func (s *MemoryRewardJobStore) EnqueueDelayed(_ context.Context, runID uuid.UUID, members []FinishMember, availableAt time.Time, manualOnly bool) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if _, exists := s.runToID[runID]; exists {
		return nil
	}

	jobMembers := toRewardJobMembers(members)
	if len(jobMembers) == 0 {
		return nil
	}

	now := time.Now().UTC()
	if availableAt.IsZero() {
		availableAt = now
	}

	job := RewardJob{
		ID:          s.autoID,
		RunID:       runID.String(),
		Members:     jobMembers,
		ManualOnly:  manualOnly,
		Status:      RewardJobStatusPending,
		Attempts:    0,
		NextRetryAt: availableAt,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	s.jobs[job.ID] = job
	s.runToID[runID] = job.ID
	s.autoID++
	return nil
}

func (s *MemoryRewardJobStore) List(_ context.Context, input ListRewardJobsInput) ([]RewardJob, int, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	status := normalizeRewardJobStatus(input.Status)
	if !isRewardJobStatusValid(status) {
		return nil, 0, ErrInvalidArgument
	}
	filterRunID, hasRunID, err := parseOptionalRunID(input.RunID)
	if err != nil {
		return nil, 0, err
	}
	filterManualOnly, hasManualOnly, err := parseOptionalManualOnly(input.ManualOnly)
	if err != nil {
		return nil, 0, err
	}
	filterCreatedFrom, hasCreatedFrom, err := parseOptionalRFC3339Time(input.CreatedFrom)
	if err != nil {
		return nil, 0, err
	}
	filterCreatedTo, hasCreatedTo, err := parseOptionalRFC3339Time(input.CreatedTo)
	if err != nil {
		return nil, 0, err
	}
	if hasCreatedFrom && hasCreatedTo && filterCreatedFrom.After(filterCreatedTo) {
		return nil, 0, ErrInvalidArgument
	}
	sortField, sortAsc, err := parseRewardJobSort(input.OrderBy, input.Order)
	if err != nil {
		return nil, 0, err
	}

	limit := input.Limit
	if limit <= 0 {
		limit = 50
	}
	if limit > 200 {
		limit = 200
	}
	offset := input.Offset
	if offset < 0 {
		offset = 0
	}

	all := make([]RewardJob, 0, len(s.jobs))
	for _, job := range s.jobs {
		if status != "" && job.Status != status {
			continue
		}
		if hasRunID && job.RunID != filterRunID.String() {
			continue
		}
		if hasManualOnly && job.ManualOnly != filterManualOnly {
			continue
		}
		if hasCreatedFrom && job.CreatedAt.Before(filterCreatedFrom) {
			continue
		}
		if hasCreatedTo && job.CreatedAt.After(filterCreatedTo) {
			continue
		}
		all = append(all, cloneRewardJob(job))
	}

	sort.SliceStable(all, func(i, j int) bool {
		if sortField == "id" {
			if sortAsc {
				return all[i].ID < all[j].ID
			}
			return all[i].ID > all[j].ID
		}

		if all[i].CreatedAt.Equal(all[j].CreatedAt) {
			if sortAsc {
				return all[i].ID < all[j].ID
			}
			return all[i].ID > all[j].ID
		}
		if sortAsc {
			return all[i].CreatedAt.Before(all[j].CreatedAt)
		}
		return all[i].CreatedAt.After(all[j].CreatedAt)
	})

	total := len(all)
	if offset >= total {
		return []RewardJob{}, total, nil
	}
	end := offset + limit
	if end > total {
		end = total
	}
	return all[offset:end], total, nil
}

func (s *MemoryRewardJobStore) Stats(_ context.Context, input RewardJobStatsInput) (RewardJobStatsOutput, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	status := normalizeRewardJobStatus(input.Status)
	if !isRewardJobStatusValid(status) {
		return RewardJobStatsOutput{}, ErrInvalidArgument
	}
	filterRunID, hasRunID, err := parseOptionalRunID(input.RunID)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	filterManualOnly, hasManualOnly, err := parseOptionalManualOnly(input.ManualOnly)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	filterCreatedFrom, hasCreatedFrom, err := parseOptionalRFC3339Time(input.CreatedFrom)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	filterCreatedTo, hasCreatedTo, err := parseOptionalRFC3339Time(input.CreatedTo)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	if hasCreatedFrom && hasCreatedTo && filterCreatedFrom.After(filterCreatedTo) {
		return RewardJobStatsOutput{}, ErrInvalidArgument
	}
	groupBy, err := parseRewardJobGroupBy(input.GroupBy)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}
	timezoneName, timezoneLoc, err := parseRewardJobTimezone(input.TZ)
	if err != nil {
		return RewardJobStatsOutput{}, err
	}

	stats := RewardJobStatsOutput{
		Timezone: timezoneName,
	}
	bucketMap := make(map[string]*RewardJobStatsTrendItem)
	for _, job := range s.jobs {
		if status != "" && job.Status != status {
			continue
		}
		if hasRunID && job.RunID != filterRunID.String() {
			continue
		}
		if hasManualOnly && job.ManualOnly != filterManualOnly {
			continue
		}
		if hasCreatedFrom && job.CreatedAt.Before(filterCreatedFrom) {
			continue
		}
		if hasCreatedTo && job.CreatedAt.After(filterCreatedTo) {
			continue
		}

		stats.Total++
		switch job.Status {
		case RewardJobStatusPending:
			stats.Pending++
		case RewardJobStatusProcessing:
			stats.Processing++
		case RewardJobStatusCompleted:
			stats.Completed++
		case RewardJobStatusFailed:
			stats.Failed++
		}
		if job.ManualOnly {
			stats.ManualOnlyTrue++
		} else {
			stats.ManualOnlyFalse++
		}

		if groupBy == "day" || groupBy == "hour" {
			bucket := trendBucketKey(job.CreatedAt, groupBy, timezoneLoc)
			item, exists := bucketMap[bucket]
			if !exists {
				item = &RewardJobStatsTrendItem{
					Bucket: bucket,
					Day:    bucket,
					Label:  trendBucketLabel(job.CreatedAt, groupBy, timezoneLoc),
				}
				bucketMap[bucket] = item
			}

			item.Total++
			switch job.Status {
			case RewardJobStatusPending:
				item.Pending++
			case RewardJobStatusProcessing:
				item.Processing++
			case RewardJobStatusCompleted:
				item.Completed++
			case RewardJobStatusFailed:
				item.Failed++
			}
			if job.ManualOnly {
				item.ManualOnlyTrue++
			} else {
				item.ManualOnlyFalse++
			}
		}
	}

	if groupBy == "day" || groupBy == "hour" {
		stats.Trend = make([]RewardJobStatsTrendItem, 0, len(bucketMap))
		for _, item := range bucketMap {
			stats.Trend = append(stats.Trend, *item)
		}
		sort.Slice(stats.Trend, func(i, j int) bool {
			return stats.Trend[i].Day < stats.Trend[j].Day
		})
	}

	return stats, nil
}

func (s *MemoryRewardJobStore) RetryNow(_ context.Context, id int64, at time.Time) (RewardJob, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	job, ok := s.jobs[id]
	if !ok {
		return RewardJob{}, ErrRewardJobNotFound
	}

	if at.IsZero() {
		at = time.Now().UTC()
	}
	job.Status = RewardJobStatusPending
	job.ManualOnly = false
	job.NextRetryAt = at
	job.LastError = ""
	job.UpdatedAt = at
	s.jobs[id] = job
	return cloneRewardJob(job), nil
}

func (s *MemoryRewardJobStore) GetByID(_ context.Context, id int64) (RewardJob, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	job, ok := s.jobs[id]
	if !ok {
		return RewardJob{}, ErrRewardJobNotFound
	}
	return cloneRewardJob(job), nil
}

func (s *MemoryRewardJobStore) DenyNow(_ context.Context, id int64, reason string, at time.Time) (RewardJob, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	job, ok := s.jobs[id]
	if !ok {
		return RewardJob{}, ErrRewardJobNotFound
	}
	if at.IsZero() {
		at = time.Now().UTC()
	}

	job.Status = RewardJobStatusFailed
	job.ManualOnly = true
	job.LastError = truncateString(reason, 512)
	if strings.TrimSpace(job.LastError) == "" {
		job.LastError = "denied_by_admin"
	}
	job.UpdatedAt = at
	s.jobs[id] = job
	return cloneRewardJob(job), nil
}

func (s *MemoryRewardJobStore) ClaimDue(_ context.Context, limit int, now time.Time) ([]RewardJob, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if limit <= 0 {
		limit = 20
	}
	if now.IsZero() {
		now = time.Now().UTC()
	}

	candidates := make([]RewardJob, 0, len(s.jobs))
	for _, job := range s.jobs {
		if job.Status != RewardJobStatusPending {
			continue
		}
		if job.ManualOnly {
			continue
		}
		if job.NextRetryAt.After(now) {
			continue
		}
		candidates = append(candidates, job)
	}

	sort.SliceStable(candidates, func(i, j int) bool {
		if candidates[i].NextRetryAt.Equal(candidates[j].NextRetryAt) {
			return candidates[i].ID < candidates[j].ID
		}
		return candidates[i].NextRetryAt.Before(candidates[j].NextRetryAt)
	})

	if len(candidates) > limit {
		candidates = candidates[:limit]
	}

	result := make([]RewardJob, 0, len(candidates))
	for _, job := range candidates {
		job.Status = RewardJobStatusProcessing
		job.UpdatedAt = now
		s.jobs[job.ID] = job
		result = append(result, cloneRewardJob(job))
	}

	return result, nil
}

func (s *MemoryRewardJobStore) MarkCompleted(_ context.Context, id int64, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	job, ok := s.jobs[id]
	if !ok {
		return ErrRewardJobNotFound
	}
	if at.IsZero() {
		at = time.Now().UTC()
	}
	job.Status = RewardJobStatusCompleted
	job.LastError = ""
	job.UpdatedAt = at
	s.jobs[id] = job
	return nil
}

func (s *MemoryRewardJobStore) MarkRetry(_ context.Context, id int64, nextRetryAt time.Time, lastError string, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	job, ok := s.jobs[id]
	if !ok {
		return ErrRewardJobNotFound
	}
	if at.IsZero() {
		at = time.Now().UTC()
	}
	job.Status = RewardJobStatusPending
	job.Attempts++
	job.LastError = strings.TrimSpace(lastError)
	job.NextRetryAt = nextRetryAt
	job.UpdatedAt = at
	s.jobs[id] = job
	return nil
}

func (s *MemoryRewardJobStore) MarkFailed(_ context.Context, id int64, lastError string, at time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	job, ok := s.jobs[id]
	if !ok {
		return ErrRewardJobNotFound
	}
	if at.IsZero() {
		at = time.Now().UTC()
	}
	job.Status = RewardJobStatusFailed
	job.Attempts++
	job.LastError = strings.TrimSpace(lastError)
	job.UpdatedAt = at
	s.jobs[id] = job
	return nil
}

func toRewardJobMembers(members []FinishMember) []RewardJobMember {
	result := make([]RewardJobMember, 0, len(members))
	for _, member := range members {
		if member.SteamID == "" || len(member.RewardDraft) == 0 {
			continue
		}

		rewards := make([]RewardDraft, 0, len(member.RewardDraft))
		for _, reward := range member.RewardDraft {
			if reward.Amount <= 0 {
				continue
			}
			rewards = append(rewards, reward)
		}
		if len(rewards) == 0 {
			continue
		}

		result = append(result, RewardJobMember{
			SteamID: member.SteamID,
			Rewards: rewards,
		})
	}
	return result
}

func cloneRewardJob(job RewardJob) RewardJob {
	clonedMembers := make([]RewardJobMember, 0, len(job.Members))
	for _, member := range job.Members {
		rewards := make([]RewardDraft, 0, len(member.Rewards))
		rewards = append(rewards, member.Rewards...)
		clonedMembers = append(clonedMembers, RewardJobMember{
			SteamID: member.SteamID,
			Rewards: rewards,
		})
	}

	return RewardJob{
		ID:          job.ID,
		RunID:       job.RunID,
		Members:     clonedMembers,
		ManualOnly:  job.ManualOnly,
		Status:      job.Status,
		Attempts:    job.Attempts,
		LastError:   job.LastError,
		NextRetryAt: job.NextRetryAt,
		CreatedAt:   job.CreatedAt,
		UpdatedAt:   job.UpdatedAt,
	}
}

func normalizeRewardJobStatus(status string) string {
	return strings.ToLower(strings.TrimSpace(status))
}

func isRewardJobStatusValid(status string) bool {
	switch status {
	case "", RewardJobStatusPending, RewardJobStatusProcessing, RewardJobStatusCompleted, RewardJobStatusFailed:
		return true
	default:
		return false
	}
}

func parseOptionalRunID(raw string) (uuid.UUID, bool, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return uuid.UUID{}, false, nil
	}

	runID, err := uuid.Parse(raw)
	if err != nil {
		return uuid.UUID{}, false, ErrInvalidArgument
	}
	return runID, true, nil
}

func parseOptionalManualOnly(raw string) (bool, bool, error) {
	raw = strings.TrimSpace(strings.ToLower(raw))
	if raw == "" {
		return false, false, nil
	}

	switch raw {
	case "true", "1", "yes", "y":
		return true, true, nil
	case "false", "0", "no", "n":
		return false, true, nil
	default:
		return false, false, ErrInvalidArgument
	}
}

func parseOptionalRFC3339Time(raw string) (time.Time, bool, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return time.Time{}, false, nil
	}

	parsed, err := time.Parse(time.RFC3339Nano, raw)
	if err != nil {
		return time.Time{}, false, ErrInvalidArgument
	}
	return parsed, true, nil
}

func parseRewardJobSort(rawField, rawOrder string) (field string, asc bool, err error) {
	rawField = strings.TrimSpace(strings.ToLower(rawField))
	rawOrder = strings.TrimSpace(strings.ToLower(rawOrder))

	if rawField == "" {
		rawField = "createdat"
	}
	switch rawField {
	case "createdat", "created_at", "created":
		field = "createdAt"
	case "id":
		field = "id"
	default:
		return "", false, ErrInvalidArgument
	}

	if rawOrder == "" {
		return field, false, nil
	}
	switch rawOrder {
	case "asc":
		return field, true, nil
	case "desc":
		return field, false, nil
	default:
		return "", false, ErrInvalidArgument
	}
}

func parseRewardJobGroupBy(raw string) (string, error) {
	raw = strings.TrimSpace(strings.ToLower(raw))
	switch raw {
	case "", "none":
		return "", nil
	case "day":
		return "day", nil
	case "hour":
		return "hour", nil
	default:
		return "", ErrInvalidArgument
	}
}

func trendBucketKey(at time.Time, groupBy string, loc *time.Location) string {
	at = at.In(loc)
	if groupBy == "hour" {
		at = time.Date(at.Year(), at.Month(), at.Day(), at.Hour(), 0, 0, 0, loc)
		if loc.String() == "UTC" {
			return at.UTC().Format("2006-01-02T15:00:00Z")
		}
		return at.Format("2006-01-02T15:00:00-07:00")
	}
	return at.Format("2006-01-02")
}

func trendBucketLabel(at time.Time, groupBy string, loc *time.Location) string {
	at = at.In(loc)
	if groupBy == "hour" {
		at = time.Date(at.Year(), at.Month(), at.Day(), at.Hour(), 0, 0, 0, loc)
		return at.Format("01-02 15:00")
	}
	return at.Format("01-02")
}

const (
	rewardJobDefaultTimezone   = "UTC"
	rewardJobDefaultStatsGroup = "day"
)

func parseRewardJobTimezone(raw string) (string, *time.Location, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		raw = rewardJobDefaultTimezone
	}

	canonical := canonicalizeRewardJobTimezone(raw)
	if isAmbiguousTimezoneAbbr(raw) {
		return "", nil, ErrInvalidArgument
	}

	loc, err := time.LoadLocation(canonical)
	if err != nil {
		return "", nil, ErrInvalidArgument
	}
	return loc.String(), loc, nil
}

func GetRewardJobTimezonesOutput() RewardJobTimezonesOutput {
	aliases := make([]RewardJobTimezoneAlias, 0, len(rewardJobTimezoneAliases))
	for alias, timezone := range rewardJobTimezoneAliases {
		aliases = append(aliases, RewardJobTimezoneAlias{
			Alias:    alias,
			Timezone: timezone,
		})
	}
	sort.Slice(aliases, func(i, j int) bool {
		return aliases[i].Alias < aliases[j].Alias
	})

	deprecatedAliases := make([]string, 0, len(aliases))
	for _, alias := range aliases {
		if isDeprecatedTimezoneAlias(alias.Alias, alias.Timezone) {
			deprecatedAliases = append(deprecatedAliases, alias.Alias)
		}
	}

	timezoneSet := map[string]struct{}{
		rewardJobDefaultTimezone: {},
		"Asia/Shanghai":       {},
		"Asia/Tokyo":          {},
		"Asia/Seoul":          {},
		"Asia/Singapore":      {},
		"Europe/London":       {},
		"Europe/Berlin":       {},
		"America/Los_Angeles": {},
		"America/New_York":    {},
	}
	for _, alias := range aliases {
		timezoneSet[alias.Timezone] = struct{}{}
	}
	timezones := make([]string, 0, len(timezoneSet))
	for timezone := range timezoneSet {
		timezones = append(timezones, timezone)
	}
	sort.Strings(timezones)
	preferredTimezoneExamples := buildPreferredTimezoneExamples(timezoneSet)

	return RewardJobTimezonesOutput{
		DefaultTimezone:           rewardJobDefaultTimezone,
		Timezones:                 timezones,
		Aliases:                   aliases,
		DeprecatedAliases:         deprecatedAliases,
		PreferredTimezoneExamples: preferredTimezoneExamples,
		FrontendDefaults: RewardJobFrontendDefaults{
			StatsGroupBy:  rewardJobDefaultStatsGroup,
			StatsTimezone: rewardJobDefaultTimezone,
		},
	}
}

func isDeprecatedTimezoneAlias(alias, timezone string) bool {
	alias = strings.ToLower(strings.TrimSpace(alias))
	timezone = strings.ToLower(strings.TrimSpace(timezone))
	return alias != timezone
}

func buildPreferredTimezoneExamples(timezoneSet map[string]struct{}) []string {
	candidates := []string{
		"UTC",
		"Asia/Shanghai",
		"Asia/Tokyo",
		"Asia/Seoul",
		"Europe/London",
		"America/Los_Angeles",
		"America/New_York",
	}
	out := make([]string, 0, len(candidates))
	for _, timezone := range candidates {
		if _, exists := timezoneSet[timezone]; exists {
			out = append(out, timezone)
		}
	}
	return out
}

func canonicalizeRewardJobTimezone(raw string) string {
	key := strings.ToLower(strings.TrimSpace(raw))
	if mapped, ok := rewardJobTimezoneAliases[key]; ok {
		return mapped
	}
	return raw
}

func isAmbiguousTimezoneAbbr(raw string) bool {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return false
	}

	// Common 2-5 letter abbreviations are ambiguous globally (e.g. CST).
	if len(raw) < 2 || len(raw) > 5 {
		return false
	}
	for _, ch := range raw {
		if (ch < 'A' || ch > 'Z') && (ch < 'a' || ch > 'z') {
			return false
		}
	}

	_, mapped := rewardJobTimezoneAliases[strings.ToLower(raw)]
	return !mapped
}

var rewardJobTimezoneAliases = map[string]string{
	"utc":           "UTC",
	"z":             "UTC",
	"gmt":           "UTC",
	"etc/utc":       "UTC",
	"etc/gmt":       "UTC",
	"prc":           "Asia/Shanghai",
	"china":         "Asia/Shanghai",
	"cn":            "Asia/Shanghai",
	"asia/beijing":  "Asia/Shanghai",
	"asia/chongqing": "Asia/Shanghai",
	"asia/harbin":   "Asia/Shanghai",
	"asia/urumqi":   "Asia/Shanghai",
}
