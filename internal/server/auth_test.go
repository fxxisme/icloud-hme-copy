package server

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestAPIKeyAuth(t *testing.T) {
	gin.SetMode(gin.TestMode)

	tests := []struct {
		name       string
		headerName string
		header     string
		wantStatus int
	}{
		{name: "missing", wantStatus: http.StatusUnauthorized},
		{name: "wrong bearer", headerName: "Authorization", header: "Bearer wrong", wantStatus: http.StatusUnauthorized},
		{name: "valid bearer", headerName: "Authorization", header: "Bearer test-secret", wantStatus: http.StatusOK},
		{name: "valid api key header", headerName: "X-API-Key", header: "test-secret", wantStatus: http.StatusOK},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.GET("/api/test", apiKeyAuth("test-secret"), func(c *gin.Context) {
				c.Status(http.StatusOK)
			})

			req := httptest.NewRequest(http.MethodGet, "/api/test", nil)
			if tt.headerName != "" {
				req.Header.Set(tt.headerName, tt.header)
			}
			resp := httptest.NewRecorder()
			router.ServeHTTP(resp, req)

			if resp.Code != tt.wantStatus {
				t.Fatalf("status = %d, want %d", resp.Code, tt.wantStatus)
			}
		})
	}
}
