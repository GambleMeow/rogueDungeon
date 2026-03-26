package run

import (
	"context"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"rogue-dungeon-backend/internal/common/ctxkeys"
	"rogue-dungeon-backend/internal/transport/http/response"
)

type RewardJobAdminHandler struct {
	store   RewardJobStore
	repo    Repository
	applier RewardApplier
	auditor RewardJobRetryAuditor
}

type RewardJobRetryAuditor interface {
	LogRewardJobRetry(ctx context.Context, adminActor string, jobID int64, runID string) error
	LogRewardJobApprove(ctx context.Context, adminActor string, jobID int64, runID, note string) error
	LogRewardJobDeny(ctx context.Context, adminActor string, jobID int64, runID, note string) error
}

type noopRewardJobRetryAuditor struct{}

func (n *noopRewardJobRetryAuditor) LogRewardJobRetry(_ context.Context, _ string, _ int64, _ string) error {
	return nil
}

func (n *noopRewardJobRetryAuditor) LogRewardJobApprove(_ context.Context, _ string, _ int64, _ string, _ string) error {
	return nil
}

func (n *noopRewardJobRetryAuditor) LogRewardJobDeny(_ context.Context, _ string, _ int64, _ string, _ string) error {
	return nil
}

func NewRewardJobAdminHandler(store RewardJobStore, repo Repository, applier RewardApplier, auditor RewardJobRetryAuditor) *RewardJobAdminHandler {
	if auditor == nil {
		auditor = &noopRewardJobRetryAuditor{}
	}
	return &RewardJobAdminHandler{
		store:   store,
		repo:    repo,
		applier: applier,
		auditor: auditor,
	}
}

func (h *RewardJobAdminHandler) List(c *gin.Context) {
	var req ListRewardJobsInput
	if err := c.ShouldBindQuery(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	if h.store == nil {
		c.JSON(http.StatusOK, ListRewardJobsOutput{
			Items: []RewardJob{},
			Total: 0,
		})
		return
	}

	items, total, err := h.store.List(c.Request.Context(), req)
	if err != nil {
		h.writeError(c, err)
		return
	}

	c.JSON(http.StatusOK, ListRewardJobsOutput{
		Items: items,
		Total: total,
	})
}

func (h *RewardJobAdminHandler) Stats(c *gin.Context) {
	var req RewardJobStatsInput
	if err := c.ShouldBindQuery(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}
	if h.store == nil {
		c.JSON(http.StatusOK, RewardJobStatsOutput{})
		return
	}

	out, err := h.store.Stats(c.Request.Context(), req)
	if err != nil {
		h.writeError(c, err)
		return
	}
	c.JSON(http.StatusOK, out)
}

func (h *RewardJobAdminHandler) Timezones(c *gin.Context) {
	c.JSON(http.StatusOK, GetRewardJobTimezonesOutput())
}

func (h *RewardJobAdminHandler) Get(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid id")
		return
	}
	if h.store == nil {
		response.WriteError(c, http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "reward job queue unavailable")
		return
	}

	job, err := h.store.GetByID(c.Request.Context(), id)
	if err != nil {
		h.writeError(c, err)
		return
	}
	c.JSON(http.StatusOK, job)
}

func (h *RewardJobAdminHandler) Retry(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid id")
		return
	}

	if h.store == nil {
		response.WriteError(c, http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "reward job queue unavailable")
		return
	}

	job, err := h.store.RetryNow(c.Request.Context(), id, time.Now().UTC())
	if err != nil {
		h.writeError(c, err)
		return
	}

	adminActor := strings.TrimSpace(c.GetString(ctxkeys.AdminActorKey))
	if adminActor == "" {
		adminActor = "admin-token"
	}
	_ = h.auditor.LogRewardJobRetry(c.Request.Context(), adminActor, id, job.RunID)

	c.JSON(http.StatusOK, job)
}

type denyRewardJobInput struct {
	Note string `json:"note" binding:"max=512"`
}

type approveRewardJobInput struct {
	Note string `json:"note" binding:"max=512"`
}

func (h *RewardJobAdminHandler) Approve(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid id")
		return
	}
	if h.store == nil || h.applier == nil {
		response.WriteError(c, http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "reward job queue unavailable")
		return
	}

	var req approveRewardJobInput
	if err := c.ShouldBindJSON(&req); err != nil && !errors.Is(err, io.EOF) {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	job, err := h.store.RetryNow(c.Request.Context(), id, time.Now().UTC())
	if err != nil {
		h.writeError(c, err)
		return
	}

	runID, err := uuid.Parse(job.RunID)
	if err != nil {
		_ = h.store.MarkRetry(c.Request.Context(), id, time.Now().UTC().Add(15*time.Second), err.Error(), time.Now().UTC())
		response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
		return
	}

	for _, member := range job.Members {
		if member.SteamID == "" || len(member.Rewards) == 0 {
			continue
		}
		if err := h.applier.ApplyRewards(c.Request.Context(), member.SteamID, runID, member.Rewards, time.Now().UTC()); err != nil {
			_ = h.store.MarkRetry(c.Request.Context(), id, time.Now().UTC().Add(15*time.Second), err.Error(), time.Now().UTC())
			response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
			return
		}
	}

	if err := h.store.MarkCompleted(c.Request.Context(), id, time.Now().UTC()); err != nil {
		h.writeError(c, err)
		return
	}

	if h.repo != nil {
		if err := h.repo.UpdateRunRewardStatus(c.Request.Context(), runID, RewardStatusGranted, time.Now().UTC()); err != nil && !errors.Is(err, errRecordNotFound) {
			response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
			return
		}
	}

	adminActor := strings.TrimSpace(c.GetString(ctxkeys.AdminActorKey))
	if adminActor == "" {
		adminActor = "admin-token"
	}
	_ = h.auditor.LogRewardJobApprove(c.Request.Context(), adminActor, id, job.RunID, req.Note)
	job.Status = RewardJobStatusCompleted
	job.LastError = ""
	job.ManualOnly = false
	job.UpdatedAt = time.Now().UTC()
	c.JSON(http.StatusOK, job)
}

func (h *RewardJobAdminHandler) Deny(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid id")
		return
	}
	if h.store == nil {
		response.WriteError(c, http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "reward job queue unavailable")
		return
	}

	var req denyRewardJobInput
	if err := c.ShouldBindJSON(&req); err != nil && !errors.Is(err, io.EOF) {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	job, err := h.store.DenyNow(c.Request.Context(), id, req.Note, time.Now().UTC())
	if err != nil {
		h.writeError(c, err)
		return
	}

	if h.repo != nil {
		runID, parseErr := uuid.Parse(job.RunID)
		if parseErr == nil {
			if err := h.repo.UpdateRunRewardStatus(c.Request.Context(), runID, RewardStatusDenied, time.Now().UTC()); err != nil && !errors.Is(err, errRecordNotFound) {
				response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
				return
			}
		}
	}

	adminActor := strings.TrimSpace(c.GetString(ctxkeys.AdminActorKey))
	if adminActor == "" {
		adminActor = "admin-token"
	}
	_ = h.auditor.LogRewardJobDeny(c.Request.Context(), adminActor, id, job.RunID, req.Note)

	c.JSON(http.StatusOK, job)
}

func (h *RewardJobAdminHandler) writeError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrInvalidArgument):
		response.WriteError(c, http.StatusBadRequest, err.Error(), err.Error())
	case errors.Is(err, ErrRewardJobNotFound):
		response.WriteError(c, http.StatusNotFound, err.Error(), err.Error())
	default:
		response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
	}
}
