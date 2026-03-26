package risk

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"rogue-dungeon-backend/internal/common/ctxkeys"
	"rogue-dungeon-backend/internal/transport/http/response"
)

type ActionAuditor interface {
	LogRiskAction(ctx context.Context, adminActor string, flagID int64, action, note string) error
}

type noopActionAuditor struct{}

func (n *noopActionAuditor) LogRiskAction(_ context.Context, _ string, _ int64, _ string, _ string) error {
	return nil
}

type Handler struct {
	service Service
	auditor ActionAuditor
}

func NewHandler(service Service, auditor ActionAuditor) *Handler {
	if auditor == nil {
		auditor = &noopActionAuditor{}
	}
	return &Handler{
		service: service,
		auditor: auditor,
	}
}

func (h *Handler) ListFlags(c *gin.Context) {
	var req ListFlagsInput
	if err := c.ShouldBindQuery(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.ListFlags(c.Request.Context(), req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusOK, out)
}

func (h *Handler) ApplyAction(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", "invalid id")
		return
	}

	var req ApplyActionInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.ApplyAction(c.Request.Context(), id, req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	adminActor := strings.TrimSpace(c.GetString(ctxkeys.AdminActorKey))
	if adminActor == "" {
		adminActor = "admin-token"
	}
	_ = h.auditor.LogRiskAction(c.Request.Context(), adminActor, id, req.Action, req.Note)

	c.JSON(http.StatusOK, out)
}

func (h *Handler) writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrInvalidArgument):
		response.WriteError(c, http.StatusBadRequest, err.Error(), err.Error())
	case errors.Is(err, ErrFlagNotFound):
		response.WriteError(c, http.StatusNotFound, err.Error(), err.Error())
	default:
		response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
	}
}
