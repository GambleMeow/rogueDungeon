package commerce

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"

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

func (h *Handler) GetCatalog(c *gin.Context) {
	out, err := h.service.GetCatalog(c.Request.Context())
	if err != nil {
		h.writeServiceError(c, err)
		return
	}
	c.JSON(http.StatusOK, out)
}

func (h *Handler) SyncEntitlements(c *gin.Context) {
	actor, err := actorFromContext(c)
	if err != nil {
		response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing actor context")
		return
	}

	var req SyncEntitlementsInput
	if err := c.ShouldBindJSON(&req); err != nil {
		response.WriteError(c, http.StatusBadRequest, "INVALID_ARGUMENT", err.Error())
		return
	}

	out, err := h.service.SyncEntitlements(c.Request.Context(), actor, req)
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
	return UserRef{
		UserID:  actor.UserID,
		SteamID: actor.SteamID,
	}, nil
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
