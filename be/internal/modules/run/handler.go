package run

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"rogue-dungeon-backend/internal/common/ctxkeys"
	"rogue-dungeon-backend/internal/common/identity"
	"rogue-dungeon-backend/internal/transport/http/response"
)

type Handler struct {
	service Service
}

func NewHandler(service Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) StartRun(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	var req StartRunInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.StartRun(c.Request.Context(), actor, req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) FinishRun(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	idemKey := c.GetHeader("X-Idempotency-Key")
	if idemKey == "" {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "X-Idempotency-Key required")
		return
	}

	var req FinishRunInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.FinishRun(c.Request.Context(), actor, runID, idemKey, req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) AbortRun(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	out, err := h.service.AbortRun(c.Request.Context(), actor, runID)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) Heartbeat(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	var req RunHeartbeatInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.Heartbeat(c.Request.Context(), actor, runID, req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) HostMigrationClaim(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	out, err := h.service.HostMigrationClaim(c.Request.Context(), actor, runID)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) HostMigrationConfirm(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	var req RunHostMigrationConfirmInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.HostMigrationConfirm(c.Request.Context(), actor, runID, req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) ReconnectRequest(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	out, err := h.service.ReconnectRequest(c.Request.Context(), actor, runID)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) ReconnectConfirm(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	var req RunReconnectConfirmInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.ReconnectConfirm(c.Request.Context(), actor, runID, req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) GetSessionState(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	out, err := h.service.GetSessionState(c.Request.Context(), actor, runID)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) GetRun(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	out, err := h.service.GetRun(c.Request.Context(), actor, runID)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) ListRuns(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	var req ListRunsInput
	if err := c.ShouldBindQuery(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.ListRuns(c.Request.Context(), actor, req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) GetRunDetail(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	out, err := h.service.GetRunDetail(c.Request.Context(), actor, runID)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) GetRunReasons(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	runID, err := uuid.Parse(c.Param("runId"))
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid runId")
		return
	}

	out, err := h.service.GetRunReasons(c.Request.Context(), actor, runID)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func actorFromContext(c *gin.Context) (UserRef, error) {
	raw, ok := c.Get(ctxkeys.ActorKey)
	if !ok {
		return UserRef{}, ErrUnauthorized
	}
	actor, ok := raw.(identity.Actor)
	if !ok {
		return UserRef{}, ErrUnauthorized
	}
	return UserRef(actor), nil
}

func (h *Handler) writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrInvalidArgument), errors.Is(err, ErrProofInvalid), errors.Is(err, ErrMemberSetMismatch), errors.Is(err, ErrRunTokenInvalid), errors.Is(err, ErrReconnectTokenInvalid):
		response.WriteError(c, http.StatusBadRequest, err.Error(), err.Error())
	case errors.Is(err, ErrUnauthorized):
		response.WriteError(c, http.StatusUnauthorized, err.Error(), err.Error())
	case errors.Is(err, ErrForbidden):
		response.WriteError(c, http.StatusForbidden, err.Error(), err.Error())
	case errors.Is(err, ErrRunNotFound):
		response.WriteError(c, http.StatusNotFound, err.Error(), err.Error())
	case errors.Is(err, ErrConflict), errors.Is(err, ErrIdempotencyReplayMismatch), errors.Is(err, ErrRunAlreadyFinalized), errors.Is(err, ErrReconnectWindowExpired):
		response.WriteError(c, http.StatusConflict, err.Error(), err.Error())
	default:
		response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
	}
}
