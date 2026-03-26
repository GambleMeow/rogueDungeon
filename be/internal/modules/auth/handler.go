package auth

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

func (h *Handler) SteamLogin(c *gin.Context) {
	var req SteamLoginInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.SteamLogin(c.Request.Context(), req)
	if err != nil {
		h.writeServiceError(c, err)
		return
	}

	c.JSON(http.StatusOK, out)
}

func (h *Handler) Refresh(c *gin.Context) {
	var req RefreshInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.Refresh(c.Request.Context(), req)
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
	case errors.Is(err, ErrUnauthorized):
		response.WriteError(c, http.StatusUnauthorized, err.Error(), err.Error())
	default:
		response.WriteError(c, http.StatusInternalServerError, "INTERNAL_ERROR", "internal server error")
	}
}
