CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  steam_id BIGINT NOT NULL UNIQUE,
  steam_persona_name VARCHAR(64),
  status SMALLINT NOT NULL DEFAULT 0 CHECK (status IN (0,1,2)),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_login_at TIMESTAMPTZ
);

CREATE TABLE player_profiles (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  level INT NOT NULL DEFAULT 1 CHECK (level >= 1),
  exp INT NOT NULL DEFAULT 0 CHECK (exp >= 0),
  talent_points INT NOT NULL DEFAULT 0 CHECK (talent_points >= 0),
  talents JSONB NOT NULL DEFAULT '{}'::jsonb,
  loadout JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE inventories (
  user_id BIGINT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  soft_currency INT NOT NULL DEFAULT 0 CHECK (soft_currency >= 0),
  hard_currency INT NOT NULL DEFAULT 0 CHECK (hard_currency >= 0),
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  cosmetics JSONB NOT NULL DEFAULT '[]'::jsonb,
  version INT NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE entitlements (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  steam_dlc_id INT NOT NULL,
  owned BOOLEAN NOT NULL DEFAULT TRUE,
  source VARCHAR(16) NOT NULL DEFAULT 'steam',
  synced_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, steam_dlc_id)
);

CREATE TABLE run_sessions (
  run_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seed BIGINT NOT NULL,
  run_token_hash CHAR(64) NOT NULL,
  host_user_id BIGINT NOT NULL REFERENCES users(id),
  host_steam_id BIGINT NOT NULL,
  mode VARCHAR(32) NOT NULL,
  difficulty SMALLINT NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  region VARCHAR(32) NOT NULL,
  status SMALLINT NOT NULL DEFAULT 0 CHECK (status IN (0,1,2,3,4)),
  host_last_heartbeat_at TIMESTAMPTZ,
  host_reconnect_deadline_at TIMESTAMPTZ,
  host_migration_deadline_at TIMESTAMPTZ,
  migration_epoch BIGINT NOT NULL DEFAULT 0,
  reconnect_token_hash CHAR(64),
  reconnect_token_steam_id BIGINT,
  reconnect_token_expire_at TIMESTAMPTZ,
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE run_session_members (
  run_id UUID NOT NULL REFERENCES run_sessions(run_id) ON DELETE CASCADE,
  steam_id BIGINT NOT NULL,
  char_id VARCHAR(32) NOT NULL,
  slot_no SMALLINT NOT NULL CHECK (slot_no BETWEEN 1 AND 4),
  is_host BOOLEAN NOT NULL DEFAULT FALSE,
  member_state SMALLINT NOT NULL DEFAULT 0 CHECK (member_state IN (0,1,2)),
  last_seen_at TIMESTAMPTZ,
  reconnect_deadline_at TIMESTAMPTZ,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (run_id, steam_id),
  UNIQUE (run_id, slot_no)
);

CREATE TABLE run_results (
  run_id UUID PRIMARY KEY REFERENCES run_sessions(run_id) ON DELETE CASCADE,
  submitted_by_steam_id BIGINT NOT NULL,
  clear_time_sec INT NOT NULL CHECK (clear_time_sec >= 0),
  rooms_cleared INT NOT NULL CHECK (rooms_cleared >= 0),
  team_score INT NOT NULL CHECK (team_score >= 0),
  deaths INT NOT NULL CHECK (deaths >= 0),
  proof_payload JSONB NOT NULL,
  result_payload JSONB NOT NULL,
  risk_reasons JSONB NOT NULL DEFAULT '[]'::jsonb,
  risk_score INT NOT NULL DEFAULT 0 CHECK (risk_score >= 0),
  verdict SMALLINT NOT NULL DEFAULT 0 CHECK (verdict IN (0,1,2,3)),
  reward_status SMALLINT NOT NULL DEFAULT 2 CHECK (reward_status IN (1,2,3)),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  reviewed_at TIMESTAMPTZ
);

CREATE TABLE reward_grants (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  run_id UUID NOT NULL REFERENCES run_sessions(run_id) ON DELETE CASCADE,
  payload JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, run_id)
);

CREATE TABLE reward_jobs (
  id BIGSERIAL PRIMARY KEY,
  run_id UUID NOT NULL UNIQUE REFERENCES run_sessions(run_id) ON DELETE CASCADE,
  payload JSONB NOT NULL DEFAULT '[]'::jsonb,
  manual_only BOOLEAN NOT NULL DEFAULT FALSE,
  status SMALLINT NOT NULL DEFAULT 0 CHECK (status IN (0,1,2,3)),
  attempts INT NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error TEXT,
  next_retry_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE risk_flags (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  run_id UUID REFERENCES run_sessions(run_id) ON DELETE SET NULL,
  rule_code VARCHAR(64) NOT NULL,
  score INT NOT NULL CHECK (score >= 0),
  evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
  action SMALLINT NOT NULL DEFAULT 0 CHECK (action IN (0,1,2,3)),
  status SMALLINT NOT NULL DEFAULT 0 CHECK (status IN (0,1,2,3)),
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  handled_at TIMESTAMPTZ
);

CREATE TABLE admin_audit_logs (
  id BIGSERIAL PRIMARY KEY,
  admin_actor VARCHAR(128) NOT NULL,
  action VARCHAR(64) NOT NULL,
  target_type VARCHAR(64) NOT NULL,
  target_id VARCHAR(128) NOT NULL,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE idempotency_keys (
  key VARCHAR(72) PRIMARY KEY,
  route VARCHAR(128) NOT NULL,
  user_id BIGINT,
  request_hash CHAR(64) NOT NULL,
  response_body JSONB,
  status_code INT,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_run_sessions_host_created ON run_sessions(host_steam_id, created_at DESC);
CREATE INDEX idx_run_sessions_status_created ON run_sessions(status, created_at DESC);
CREATE INDEX idx_run_results_verdict_created ON run_results(verdict, created_at DESC);
CREATE INDEX idx_idempotency_expires ON idempotency_keys(expires_at);
CREATE INDEX idx_entitlements_user_owned ON entitlements(user_id, owned);
CREATE INDEX idx_risk_flags_status_created ON risk_flags(status, created_at DESC);
CREATE INDEX idx_risk_flags_rule_created ON risk_flags(rule_code, created_at DESC);
CREATE INDEX idx_risk_flags_source_created ON risk_flags((evidence->>'source'), created_at DESC);
CREATE INDEX idx_admin_audit_logs_created ON admin_audit_logs(created_at DESC);
CREATE INDEX idx_reward_grants_user_created ON reward_grants(user_id, created_at DESC);
CREATE INDEX idx_reward_jobs_status_retry ON reward_jobs(status, next_retry_at);
