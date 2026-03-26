package run

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"rogue-dungeon-backend/internal/common/ctxkeys"
	"rogue-dungeon-backend/internal/common/identity"
	"rogue-dungeon-backend/internal/transport/http/response"
)

func TestHandler_StartAndFinishRun_P2PFlowAccepted(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	risk := &stubRiskEngine{score: 10}
	reward := &stubRewardService{}
	svc := NewService(repo, idem, risk, reward, &stubRiskReporter{})
	handler := NewHandler(svc)

	router := newRunTestRouter(handler, testHostSteamID, 2001)

	startReq := StartRunInput{
		Mode:        ModeRogueCoopV1,
		Difficulty:  2,
		Region:      "asia-east",
		HostSteamID: testHostSteamID,
		Party: []PartyMember{
			{SteamID: testHostSteamID, CharID: "char_1"},
			{SteamID: testPeerSteamID, CharID: "char_2"},
			{SteamID: testPeer2SteamID, CharID: "char_3"},
		},
		ClientBuild: "dev-test",
	}
	startBody, _ := json.Marshal(startReq)
	startResp := performJSONRequest(router, http.MethodPost, "/v1/runs/start", startBody, nil)
	if startResp.Code != http.StatusOK {
		t.Fatalf("expected start status 200, got %d body=%s", startResp.Code, startResp.Body.String())
	}

	var startOut StartRunOutput
	if err := json.Unmarshal(startResp.Body.Bytes(), &startOut); err != nil {
		t.Fatalf("decode start response failed: %v", err)
	}
	runID, err := uuid.Parse(startOut.RunID)
	if err != nil {
		t.Fatalf("invalid run id: %v", err)
	}

	finishReq := buildValidFinishInput(runID, startOut.RunToken, []string{
		testHostSteamID,
		testPeerSteamID,
		testPeer2SteamID,
	})
	finishBody, _ := json.Marshal(finishReq)
	finishResp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/finish",
		finishBody,
		map[string]string{"X-Idempotency-Key": "idem-http-accepted"},
	)
	if finishResp.Code != http.StatusOK {
		t.Fatalf("expected finish status 200, got %d body=%s", finishResp.Code, finishResp.Body.String())
	}

	var finishOut FinishRunOutput
	if err := json.Unmarshal(finishResp.Body.Bytes(), &finishOut); err != nil {
		t.Fatalf("decode finish response failed: %v", err)
	}
	if finishOut.Verdict != VerdictAccepted || finishOut.RewardStatus != RewardStatusGranted {
		t.Fatalf("unexpected finish output: %+v", finishOut)
	}
	if reward.grantNowCalls != 1 {
		t.Fatalf("expected exactly one grant call, got %d", reward.grantNowCalls)
	}
}

func TestHandler_FinishRun_MissingIdempotencyHeader(t *testing.T) {
	gin.SetMode(gin.TestMode)

	svc := NewService(
		NewMemoryRepository(),
		NewMemoryIdempotencyStore(),
		&stubRiskEngine{score: 0},
		&stubRewardService{},
		&stubRiskReporter{},
	)
	handler := NewHandler(svc)
	router := newRunTestRouter(handler, testHostSteamID, 2001)

	reqBody := []byte(`{"runToken":"rtk_dummy","final":{"result":"win","clearTimeSec":1,"roomsCleared":1,"teamScore":1,"deaths":0},"members":[{"steamId":"76561198000000001","damageDone":1,"downCount":0,"reviveCount":0,"rewardDraft":[{"type":"soft_currency","id":"gold","amount":1}]}],"proof":{"segmentSec":30,"headHash":"aaaaaaaa","tailHash":"bbbbbbbb","segments":[{"idx":0,"kills":1,"goldGain":1,"damageOut":1,"damageIn":1,"hash":"cccccccc"}]},"clientMeta":{"build":"dev","platform":"windows","avgRttMs":1,"packetLossPct":0}}`)
	resp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+uuid.NewString()+"/finish",
		reqBody,
		nil,
	)
	if resp.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400 for missing idempotency header, got %d", resp.Code)
	}

	var errBody response.ErrorBody
	if err := json.Unmarshal(resp.Body.Bytes(), &errBody); err != nil {
		t.Fatalf("decode error body failed: %v", err)
	}
	if errBody.Code != "INVALID_ARGUMENT" {
		t.Fatalf("expected INVALID_ARGUMENT, got %s", errBody.Code)
	}
}

func TestHandler_FinishRun_TamperedProofReturnsBadRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	svc := NewService(repo, idem, &stubRiskEngine{score: 10}, &stubRewardService{}, &stubRiskReporter{})
	handler := NewHandler(svc)
	router := newRunTestRouter(handler, testHostSteamID, 2001)

	runID, runToken := startRunForTest(t, svc, UserRef{UserID: 2001, SteamID: testHostSteamID}, []string{
		testHostSteamID,
		testPeerSteamID,
	})
	req := buildValidFinishInput(runID, runToken, []string{testHostSteamID, testPeerSteamID})
	req.Proof.Segments[0].Kills++
	body, _ := json.Marshal(req)

	resp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/finish",
		body,
		map[string]string{"X-Idempotency-Key": "idem-http-proof-invalid"},
	)
	if resp.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400 for invalid proof, got %d body=%s", resp.Code, resp.Body.String())
	}

	var errBody response.ErrorBody
	if err := json.Unmarshal(resp.Body.Bytes(), &errBody); err != nil {
		t.Fatalf("decode error body failed: %v", err)
	}
	if errBody.Code != ErrProofInvalid.Error() {
		t.Fatalf("expected %s, got %s", ErrProofInvalid.Error(), errBody.Code)
	}
}

func TestHandler_HostMigrationClaimConfirm_Success(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{}, cfg)
	handler := NewHandler(svc)

	hostActor := UserRef{UserID: 3001, SteamID: testHostSteamID}
	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID, testPeer2SteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	router := newRunTestRouter(handler, testPeerSteamID, 3002)
	claimResp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/host-migration/claim",
		nil,
		nil,
	)
	if claimResp.Code != http.StatusOK {
		t.Fatalf("expected claim status 200, got %d body=%s", claimResp.Code, claimResp.Body.String())
	}

	var claimOut RunHostMigrationClaimOutput
	if err := json.Unmarshal(claimResp.Body.Bytes(), &claimOut); err != nil {
		t.Fatalf("decode claim response failed: %v", err)
	}
	if claimOut.CandidateSteamID != testPeerSteamID {
		t.Fatalf("expected candidate %s, got %s", testPeerSteamID, claimOut.CandidateSteamID)
	}
	if claimOut.ClaimToken == "" {
		t.Fatal("expected non-empty claim token")
	}

	confirmBody, _ := json.Marshal(RunHostMigrationConfirmInput{ClaimToken: claimOut.ClaimToken})
	confirmResp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/host-migration/confirm",
		confirmBody,
		nil,
	)
	if confirmResp.Code != http.StatusOK {
		t.Fatalf("expected confirm status 200, got %d body=%s", confirmResp.Code, confirmResp.Body.String())
	}

	var out RunHeartbeatOutput
	if err := json.Unmarshal(confirmResp.Body.Bytes(), &out); err != nil {
		t.Fatalf("decode confirm response failed: %v", err)
	}
	if out.Status != RunStatusRunning {
		t.Fatalf("expected status %q, got %q", RunStatusRunning, out.Status)
	}
	if out.CurrentHostSteamID != testPeerSteamID {
		t.Fatalf("expected new host %s, got %s", testPeerSteamID, out.CurrentHostSteamID)
	}
}

func TestHandler_HostMigrationClaim_WhenMigrationTimeoutReturnsConflict(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{}, cfg)
	handler := NewHandler(svc)

	hostActor := UserRef{UserID: 3001, SteamID: testHostSteamID}
	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}
	repo.mu.Lock()
	run := repo.runs[runID]
	expired := time.Now().UTC().Add(-2 * time.Second)
	run.HostMigrationDeadlineAt = &expired
	repo.runs[runID] = run
	repo.mu.Unlock()

	router := newRunTestRouter(handler, testPeerSteamID, 3002)
	resp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/host-migration/claim",
		nil,
		nil,
	)
	if resp.Code != http.StatusConflict {
		t.Fatalf("expected status 409, got %d body=%s", resp.Code, resp.Body.String())
	}

	var errBody response.ErrorBody
	if err := json.Unmarshal(resp.Body.Bytes(), &errBody); err != nil {
		t.Fatalf("decode error body failed: %v", err)
	}
	if errBody.Code != ErrConflict.Error() {
		t.Fatalf("expected error code %s, got %s", ErrConflict.Error(), errBody.Code)
	}
}

func TestHandler_HostMigrationConfirm_InvalidTokenReturnsBadRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{}, cfg)
	handler := NewHandler(svc)

	hostActor := UserRef{UserID: 3001, SteamID: testHostSteamID}
	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	router := newRunTestRouter(handler, testPeerSteamID, 3002)
	reqBody, _ := json.Marshal(RunHostMigrationConfirmInput{ClaimToken: "rrt_invalid_token_value"})
	resp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/host-migration/confirm",
		reqBody,
		nil,
	)
	if resp.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d body=%s", resp.Code, resp.Body.String())
	}

	var errBody response.ErrorBody
	if err := json.Unmarshal(resp.Body.Bytes(), &errBody); err != nil {
		t.Fatalf("decode error body failed: %v", err)
	}
	if errBody.Code != ErrReconnectTokenInvalid.Error() {
		t.Fatalf("expected error code %s, got %s", ErrReconnectTokenInvalid.Error(), errBody.Code)
	}
}

func TestHandler_HostMigrationConfirm_ExpiredTokenReturnsBadRequest(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{}, cfg)
	handler := NewHandler(svc)

	hostActor := UserRef{UserID: 3001, SteamID: testHostSteamID}
	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	router := newRunTestRouter(handler, testPeerSteamID, 3002)
	claimResp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/host-migration/claim",
		nil,
		nil,
	)
	if claimResp.Code != http.StatusOK {
		t.Fatalf("expected claim status 200, got %d body=%s", claimResp.Code, claimResp.Body.String())
	}
	var claimOut RunHostMigrationClaimOutput
	if err := json.Unmarshal(claimResp.Body.Bytes(), &claimOut); err != nil {
		t.Fatalf("decode claim response failed: %v", err)
	}

	repo.mu.Lock()
	run := repo.runs[runID]
	expired := time.Now().UTC().Add(-2 * time.Second)
	run.ReconnectTokenExpireAt = &expired
	repo.runs[runID] = run
	repo.mu.Unlock()

	reqBody, _ := json.Marshal(RunHostMigrationConfirmInput{ClaimToken: claimOut.ClaimToken})
	resp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/host-migration/confirm",
		reqBody,
		nil,
	)
	if resp.Code != http.StatusBadRequest {
		t.Fatalf("expected status 400, got %d body=%s", resp.Code, resp.Body.String())
	}

	var errBody response.ErrorBody
	if err := json.Unmarshal(resp.Body.Bytes(), &errBody); err != nil {
		t.Fatalf("decode error body failed: %v", err)
	}
	if errBody.Code != ErrReconnectTokenInvalid.Error() {
		t.Fatalf("expected error code %s, got %s", ErrReconnectTokenInvalid.Error(), errBody.Code)
	}
}

func TestHandler_HostMigrationConfirm_TimedOutMemberReturnsConflict(t *testing.T) {
	gin.SetMode(gin.TestMode)

	repo := NewMemoryRepository()
	idem := NewMemoryIdempotencyStore()
	cfg := ServiceConfig{
		HostReconnectWindow:   3 * time.Minute,
		PlayerReconnectWindow: 3 * time.Minute,
		HostMigrationWindow:   90 * time.Second,
		ReconnectTokenTTL:     30 * time.Second,
	}
	svc := NewServiceWithConfig(repo, idem, &stubRiskEngine{score: 0}, &stubRewardService{}, &stubRiskReporter{}, cfg)
	handler := NewHandler(svc)

	hostActor := UserRef{UserID: 3001, SteamID: testHostSteamID}
	runID, _ := startRunForTest(t, svc, hostActor, []string{testHostSteamID, testPeerSteamID, testPeer2SteamID})
	if _, err := repo.PromoteRunToMigrationWait(context.Background(), runID, time.Now().UTC().Add(5*time.Minute), cfg.HostMigrationWindow); err != nil {
		t.Fatalf("promote run to migration wait failed: %v", err)
	}

	router := newRunTestRouter(handler, testPeerSteamID, 3002)
	claimResp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/host-migration/claim",
		nil,
		nil,
	)
	if claimResp.Code != http.StatusOK {
		t.Fatalf("expected claim status 200, got %d body=%s", claimResp.Code, claimResp.Body.String())
	}
	var claimOut RunHostMigrationClaimOutput
	if err := json.Unmarshal(claimResp.Body.Bytes(), &claimOut); err != nil {
		t.Fatalf("decode claim response failed: %v", err)
	}

	repo.mu.Lock()
	run := repo.runs[runID]
	for idx := range run.Party {
		if run.Party[idx].SteamID == testPeerSteamID {
			run.Party[idx].State = RunMemberStateTimedOut
			expired := time.Now().UTC().Add(-2 * time.Second)
			run.Party[idx].ReconnectDeadlineAt = &expired
			break
		}
	}
	repo.runs[runID] = run
	repo.mu.Unlock()

	reqBody, _ := json.Marshal(RunHostMigrationConfirmInput{ClaimToken: claimOut.ClaimToken})
	resp := performJSONRequest(
		router,
		http.MethodPost,
		"/v1/runs/"+runID.String()+"/host-migration/confirm",
		reqBody,
		nil,
	)
	if resp.Code != http.StatusConflict {
		t.Fatalf("expected status 409, got %d body=%s", resp.Code, resp.Body.String())
	}

	var errBody response.ErrorBody
	if err := json.Unmarshal(resp.Body.Bytes(), &errBody); err != nil {
		t.Fatalf("decode error body failed: %v", err)
	}
	if errBody.Code != ErrReconnectWindowExpired.Error() {
		t.Fatalf("expected error code %s, got %s", ErrReconnectWindowExpired.Error(), errBody.Code)
	}
}

func newRunTestRouter(handler *Handler, steamID string, userID int64) *gin.Engine {
	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Set(ctxkeys.ActorKey, identity.Actor{
			UserID:  userID,
			SteamID: steamID,
		})
		c.Next()
	})
	router.POST("/v1/runs/start", handler.StartRun)
	router.POST("/v1/runs/:runId/finish", handler.FinishRun)
	router.POST("/v1/runs/:runId/host-migration/claim", handler.HostMigrationClaim)
	router.POST("/v1/runs/:runId/host-migration/confirm", handler.HostMigrationConfirm)
	router.GET("/v1/runs/:runId", handler.GetRun)
	return router
}

func performJSONRequest(router *gin.Engine, method, url string, body []byte, headers map[string]string) *httptest.ResponseRecorder {
	if body == nil {
		body = []byte("{}")
	}
	req := httptest.NewRequest(method, url, bytes.NewBuffer(body))
	req = req.WithContext(context.Background())
	req.Header.Set("Content-Type", "application/json")
	for key, value := range headers {
		req.Header.Set(key, value)
	}
	resp := httptest.NewRecorder()
	router.ServeHTTP(resp, req)
	return resp
}
