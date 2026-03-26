ALTER TABLE run_results
ADD COLUMN IF NOT EXISTS reward_status SMALLINT NOT NULL DEFAULT 2;

ALTER TABLE run_results
ADD COLUMN IF NOT EXISTS risk_reasons JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE run_sessions
ADD COLUMN IF NOT EXISTS host_last_heartbeat_at TIMESTAMPTZ;

ALTER TABLE run_sessions
ADD COLUMN IF NOT EXISTS host_reconnect_deadline_at TIMESTAMPTZ;

ALTER TABLE run_sessions
ADD COLUMN IF NOT EXISTS host_migration_deadline_at TIMESTAMPTZ;

ALTER TABLE run_sessions
ADD COLUMN IF NOT EXISTS migration_epoch BIGINT NOT NULL DEFAULT 0;

ALTER TABLE run_sessions
ADD COLUMN IF NOT EXISTS reconnect_token_hash CHAR(64);

ALTER TABLE run_sessions
ADD COLUMN IF NOT EXISTS reconnect_token_steam_id BIGINT;

ALTER TABLE run_sessions
ADD COLUMN IF NOT EXISTS reconnect_token_expire_at TIMESTAMPTZ;

UPDATE run_sessions
SET host_last_heartbeat_at = COALESCE(host_last_heartbeat_at, started_at),
	host_reconnect_deadline_at = COALESCE(host_reconnect_deadline_at, started_at + INTERVAL '3 minutes');

DO $$
BEGIN
	IF EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conname = 'run_sessions_status_check'
	) THEN
		ALTER TABLE run_sessions DROP CONSTRAINT run_sessions_status_check;
	END IF;
	ALTER TABLE run_sessions
	ADD CONSTRAINT run_sessions_status_check CHECK (status IN (0,1,2,3,4));
END $$;

ALTER TABLE run_session_members
ADD COLUMN IF NOT EXISTS member_state SMALLINT NOT NULL DEFAULT 0;

ALTER TABLE run_session_members
ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ;

ALTER TABLE run_session_members
ADD COLUMN IF NOT EXISTS reconnect_deadline_at TIMESTAMPTZ;

UPDATE run_session_members
SET last_seen_at = COALESCE(last_seen_at, joined_at);

DO $$
BEGIN
	IF NOT EXISTS (
		SELECT 1
		FROM pg_constraint
		WHERE conname = 'run_results_reward_status_check'
	) THEN
		ALTER TABLE run_results
		ADD CONSTRAINT run_results_reward_status_check CHECK (reward_status IN (1,2,3));
	END IF;
END $$;

CREATE TABLE IF NOT EXISTS reward_grants (
	id BIGSERIAL PRIMARY KEY,
	user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
	run_id UUID NOT NULL REFERENCES run_sessions(run_id) ON DELETE CASCADE,
	payload JSONB NOT NULL DEFAULT '[]'::jsonb,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
	UNIQUE (user_id, run_id)
);

CREATE INDEX IF NOT EXISTS idx_reward_grants_user_created
ON reward_grants(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS reward_jobs (
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

CREATE INDEX IF NOT EXISTS idx_reward_jobs_status_retry
ON reward_jobs(status, next_retry_at);

ALTER TABLE reward_jobs
ADD COLUMN IF NOT EXISTS manual_only BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS admin_audit_logs (
	id BIGSERIAL PRIMARY KEY,
	admin_actor VARCHAR(128) NOT NULL,
	action VARCHAR(64) NOT NULL,
	target_type VARCHAR(64) NOT NULL,
	target_id VARCHAR(128) NOT NULL,
	payload JSONB NOT NULL DEFAULT '{}'::jsonb,
	created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_logs_created
ON admin_audit_logs(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_risk_flags_rule_created
ON risk_flags(rule_code, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_risk_flags_source_created
ON risk_flags((evidence->>'source'), created_at DESC);
