package audit

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

	"rogue-dungeon-backend/internal/transport/http/response"
)

type Handler struct {
	service Service
}

func NewHandler(service Service) *Handler {
	return &Handler{service: service}
}

func (h *Handler) ListLogs(c *gin.Context) {
	var req ListLogsInput
	if err := c.ShouldBindQuery(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.ListLogs(c.Request.Context(), req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusOK, out)
}

func (h *Handler) writeServiceError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, ErrInvalidArgument):
		response.WriteError(c, http.StatusBadRequest, err.Error(), err.Error())
	default:
		response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
	}
}
