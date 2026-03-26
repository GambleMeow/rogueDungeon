package bootstrap

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"rogue-dungeon-backend/internal/common/ctxkeys"
	"rogue-dungeon-backend/internal/common/identity"
	appjwt "rogue-dungeon-backend/internal/platform/jwt"
	"rogue-dungeon-backend/internal/transport/http/response"
)

func RequestIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		requestID := c.GetHeader("X-Request-ID")
		if requestID == "" {
			requestID = uuid.NewString()
		}

		c.Set(ctxkeys.RequestIDKey, requestID)
		c.Header("X-Request-ID", requestID)
		c.Next()
	}
}

func AuthMiddleware(tokenManager *appjwt.TokenManager) gin.HandlerFunc {
	return func(c *gin.Context) {
		raw := c.GetHeader("Authorization")
		if raw == "" {
			response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "missing authorization header")
			c.Abort()
			return
		}

		const bearer = "Bearer "
		if !strings.HasPrefix(raw, bearer) {
			response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid authorization format")
			c.Abort()
			return
		}

		token := strings.TrimSpace(strings.TrimPrefix(raw, bearer))
		subject, err := tokenManager.ParseToken(token, appjwt.TokenTypeAccess)
		if err != nil {
			response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid or expired token")
			c.Abort()
			return
		}

		c.Set(ctxkeys.ActorKey, identity.Actor{
			UserID:  subject.UserID,
			SteamID: subject.SteamID,
		})
		c.Next()
	}
}

func AdminAuthMiddleware(adminToken string) gin.HandlerFunc {
	return func(c *gin.Context) {
		if strings.TrimSpace(adminToken) == "" {
			response.WriteError(c, http.StatusServiceUnavailable, "ADMIN_NOT_CONFIGURED", "admin token is not configured")
			c.Abort()
			return
		}

		raw := c.GetHeader("X-Admin-Token")
		if raw == "" || raw != adminToken {
			response.WriteError(c, http.StatusUnauthorized, "UNAUTHORIZED", "invalid admin token")
			c.Abort()
			return
		}

		adminActor := strings.TrimSpace(c.GetHeader("X-Admin-Actor"))
		if adminActor == "" {
			adminActor = "admin-token"
		}
		c.Set(ctxkeys.AdminActorKey, adminActor)
		c.Next()
	}
}
