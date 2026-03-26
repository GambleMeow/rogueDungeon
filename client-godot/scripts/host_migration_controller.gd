extends Node
class_name HostMigrationController

signal state_changed(next_state: int)
signal countdown_updated(seconds_left: int)
signal host_changed(new_host_steam_id: String)
signal migration_failed(reason_code: String)
signal session_updated(session: Dictionary)

enum NetState {
	RUNNING,
	MIGRATION_WAIT,
	MIGRATION_CANDIDATE,
	MIGRATION_FOLLOWER,
	ABORTED,
}

@export var poll_interval_running_sec: float = 2.5
@export var poll_interval_migration_sec: float = 0.75
@export var session_retry_backoff_max_sec: float = 4.0
@export var max_reclaim_attempts: int = 1
@export var max_consecutive_session_failures: int = 6

var net_state: int = NetState.RUNNING
var run_id: String = ""
var local_steam_id: String = ""

var _api: BackendApi
var _active: bool = false
var _claiming: bool = false
var _last_host_steam_id: String = ""
var _consecutive_poll_failures: int = 0
var _last_claim_epoch: int = -1

func setup(api: BackendApi, p_run_id: String, p_local_steam_id: String) -> void:
	_api = api
	run_id = p_run_id.strip_edges()
	local_steam_id = p_local_steam_id.strip_edges()

func start() -> void:
	if _api == null:
		push_error("HostMigrationController: BackendApi is null")
		return
	if run_id.is_empty() or local_steam_id.is_empty():
		push_error("HostMigrationController: run_id/local_steam_id is empty")
		return
	if _active:
		return
	_active = true
	call_deferred("_poll_loop")

func stop() -> void:
	_active = false

func _poll_loop() -> void:
	while _active:
		var poll_ok := await _poll_once()
		var wait_sec := _calc_next_wait_sec(poll_ok)
		await get_tree().create_timer(wait_sec).timeout

func _poll_once() -> bool:
	var resp := await _api.get_session_state(run_id)
	if not bool(resp.get("ok", false)):
		_consecutive_poll_failures += 1
		if _consecutive_poll_failures >= max(max_consecutive_session_failures, 1):
			emit_signal("migration_failed", "SESSION_STATE_FAILED")
		return false
	_consecutive_poll_failures = 0

	var payload := _as_dict(resp.get("data", {}))
	emit_signal("session_updated", payload)
	var status := str(payload.get("status", ""))
	match status:
		"running":
			_handle_running(payload)
		"host_migration_wait":
			await _handle_migration_wait(payload)
		"aborted":
			_set_state(NetState.ABORTED)
			emit_signal("migration_failed", "RUN_ABORTED")
		_:
			# Keep polling for eventual consistency.
			pass
	return true

func _calc_next_wait_sec(poll_ok: bool) -> float:
	var base_sec := poll_interval_running_sec
	if net_state == NetState.MIGRATION_WAIT \
		or net_state == NetState.MIGRATION_CANDIDATE \
		or net_state == NetState.MIGRATION_FOLLOWER:
		base_sec = poll_interval_migration_sec
	if poll_ok:
		return max(base_sec, 0.1)
	var backoff := base_sec * pow(1.8, float(_consecutive_poll_failures))
	return clampf(backoff, base_sec, session_retry_backoff_max_sec)

func _handle_running(session: Dictionary) -> void:
	_set_state(NetState.RUNNING)
	_last_claim_epoch = -1
	var current_host := str(session.get("currentHostSteamId", ""))
	if current_host != _last_host_steam_id and not current_host.is_empty():
		_last_host_steam_id = current_host
		emit_signal("host_changed", current_host)

func _handle_migration_wait(session: Dictionary) -> void:
	_set_state(NetState.MIGRATION_WAIT)
	var countdown_left := _emit_migration_countdown(session)
	if countdown_left == 0:
		emit_signal("migration_failed", "MIGRATION_WINDOW_EXPIRED")
		return

	if _claiming:
		return

	var epoch := int(session.get("migrationEpoch", 0))
	var candidate := _select_candidate(session)
	if candidate == local_steam_id:
		if _last_claim_epoch == epoch:
			return
		_last_claim_epoch = epoch
		_set_state(NetState.MIGRATION_CANDIDATE)
		await _claim_and_confirm()
	else:
		_set_state(NetState.MIGRATION_FOLLOWER)

func _claim_and_confirm() -> void:
	_claiming = true
	var claim_resp := await _api.host_migration_claim(run_id)
	if not bool(claim_resp.get("ok", false)):
		_claiming = false
		var claim_status := int(claim_resp.get("status", 0))
		if claim_status == 403:
			_set_state(NetState.MIGRATION_FOLLOWER)
			return
		if claim_status == 409:
			emit_signal("migration_failed", "MIGRATION_WINDOW_EXPIRED")
			return
		emit_signal("migration_failed", "CLAIM_FAILED")
		return

	var claim_payload := _as_dict(claim_resp.get("data", {}))
	var claim_token := str(claim_payload.get("claimToken", ""))
	if claim_token.is_empty():
		_claiming = false
		emit_signal("migration_failed", "CLAIM_TOKEN_EMPTY")
		return

	var attempts_left := max_reclaim_attempts
	var confirm_resp := await _api.host_migration_confirm(run_id, claim_token)
	while _is_token_invalid(confirm_resp) and attempts_left > 0:
		attempts_left -= 1
		var retry_claim := await _api.host_migration_claim(run_id)
		if not bool(retry_claim.get("ok", false)):
			confirm_resp = retry_claim
			break
		var retry_payload := _as_dict(retry_claim.get("data", {}))
		claim_token = str(retry_payload.get("claimToken", ""))
		if claim_token.is_empty():
			confirm_resp = {"ok": false, "status": 400, "code": "RECONNECT_TOKEN_INVALID", "data": {}}
			break
		confirm_resp = await _api.host_migration_confirm(run_id, claim_token)

	_claiming = false
	if _is_confirm_ok(confirm_resp):
		var session := _as_dict(confirm_resp.get("data", {}))
		_handle_running(session)
		return

	var confirm_status := int(confirm_resp.get("status", 0))
	if confirm_status == 409:
		emit_signal("migration_failed", "MIGRATION_WINDOW_EXPIRED")
	elif _is_token_invalid(confirm_resp):
		emit_signal("migration_failed", "TOKEN_INVALID")
	else:
		emit_signal("migration_failed", "CONFIRM_FAILED")

func _select_candidate(session: Dictionary) -> String:
	var old_host := str(session.get("currentHostSteamId", ""))
	var now_unix := int(Time.get_unix_time_from_system())
	var members_var: Variant = session.get("members", [])
	var members: Array = members_var if members_var is Array else []

	var candidates: Array[Dictionary] = []
	for item in members:
		if not (item is Dictionary):
			continue
		var member := item as Dictionary
		var steam_id := str(member.get("steamId", ""))
		if steam_id.is_empty():
			continue
		if steam_id == old_host:
			continue

		var state := str(member.get("state", "online"))
		if state == "timed_out":
			continue

		var reconnect_deadline := str(member.get("reconnectDeadlineAt", ""))
		if not reconnect_deadline.is_empty():
			var deadline_unix := _parse_backend_unix_time(reconnect_deadline)
			if deadline_unix > 0 and deadline_unix < now_unix:
				continue

		candidates.append({
			"steamId": steam_id,
			"rank": _candidate_rank(state),
		})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a := int(a.get("rank", 99))
		var rank_b := int(b.get("rank", 99))
		if rank_a != rank_b:
			return rank_a < rank_b
		return str(a.get("steamId", "")) < str(b.get("steamId", ""))
	)

	if candidates.is_empty():
		return ""
	return str(candidates[0].get("steamId", ""))

func _candidate_rank(state: String) -> int:
	match state:
		"", "online":
			return 0
		"reconnecting":
			return 1
		_:
			return 9

func _emit_migration_countdown(session: Dictionary) -> int:
	var deadline := str(session.get("hostMigrationDeadlineAt", ""))
	if deadline.is_empty():
		return -1
	var deadline_unix := _parse_backend_unix_time(deadline)
	if deadline_unix <= 0:
		return -1
	var now_unix := int(Time.get_unix_time_from_system())
	var left := max(deadline_unix - now_unix, 0)
	emit_signal("countdown_updated", left)
	return left

func _is_confirm_ok(resp: Dictionary) -> bool:
	if not bool(resp.get("ok", false)):
		return false
	var payload := _as_dict(resp.get("data", {}))
	return str(payload.get("status", "")) == "running"

func _is_token_invalid(resp: Dictionary) -> bool:
	if bool(resp.get("ok", false)):
		return false
	return str(resp.get("code", "")) == "RECONNECT_TOKEN_INVALID"

func _set_state(next_state: int) -> void:
	if net_state == next_state:
		return
	net_state = next_state
	emit_signal("state_changed", next_state)

func _as_dict(raw: Variant) -> Dictionary:
	return raw if raw is Dictionary else {}

func _parse_backend_unix_time(raw_datetime: String) -> int:
	var value := raw_datetime.strip_edges()
	if value.is_empty():
		return 0
	var parsed := int(Time.get_unix_time_from_datetime_string(value))
	if parsed > 0:
		return parsed

	var fallback := value.replace("T", " ")
	if fallback.ends_with("Z"):
		fallback = fallback.substr(0, fallback.length() - 1)
	var dot_idx := fallback.find(".")
	if dot_idx >= 0:
		fallback = fallback.substr(0, dot_idx)
	parsed = int(Time.get_unix_time_from_datetime_string(fallback))
	if parsed > 0:
		return parsed
	return 0
