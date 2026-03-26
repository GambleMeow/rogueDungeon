package response

import (
	"github.com/gin-gonic/gin"

	"rogue-dungeon-backend/internal/common/ctxkeys"
)

type ErrorBody struct {
	Code      string `json:"code"`
	Message   string `json:"message"`
	RequestID string `json:"requestId,omitempty"`
}

func WriteError(c *gin.Context, status int, code, message string) {
	requestID := c.GetString(ctxkeys.RequestIDKey)
	c.JSON(status, ErrorBody{
		Code:      code,
		Message:   message,
		RequestID: requestID,
	})
}
