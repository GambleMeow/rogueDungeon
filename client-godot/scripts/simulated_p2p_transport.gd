extends P2PTransportBase
class_name SimulatedP2PTransport

@export var connect_delay_sec: float = 0.15
@export var simulated_fail_hosts: PackedStringArray = []

var _run_id: String = ""
var _local_steam_id: String = ""
var _state: String = "DISCONNECTED"
var _role: String = "none"
var _host_steam_id: String = ""

func setup(run_id: String, local_steam_id: String) -> void:
	_run_id = run_id.strip_edges()
	_local_steam_id = local_steam_id.strip_edges()
	_state = "DISCONNECTED"
	_role = "none"
	_host_steam_id = ""

func connect_to_host(target_host_steam_id: String) -> Dictionary:
	var target := target_host_steam_id.strip_edges()
	if _run_id.is_empty() or _local_steam_id.is_empty():
		return {
			"ok": false,
			"code": "P2P_NOT_INITIALIZED",
		}
	if target.is_empty():
		return {
			"ok": false,
			"code": "EMPTY_HOST_ID",
		}

	_state = "CONNECTING"
	emit_signal("event_emitted", "sim transport connecting host=%s run=%s" % [target, _run_id])
	await get_tree().create_timer(max(connect_delay_sec, 0.01)).timeout

	if simulated_fail_hosts.has(target):
		_state = "DISCONNECTED"
		emit_signal("event_emitted", "sim transport failed host=%s" % target)
		return {
			"ok": false,
			"code": "P2P_CONNECT_FAILED",
		}

	_host_steam_id = target
	_role = "client"
	if target == _local_steam_id:
		_role = "host"
	_state = "CONNECTED"
	emit_signal("event_emitted", "sim transport connected role=%s host=%s" % [_role, _host_steam_id])
	return {
		"ok": true,
		"role": _role,
		"hostSteamId": _host_steam_id,
	}

func disconnect(reason_code: String = "MANUAL_STOP") -> void:
	emit_signal("event_emitted", "sim transport disconnect reason=%s" % reason_code)
	_state = "DISCONNECTED"
	_role = "none"
	_host_steam_id = ""

func get_connection_state_text() -> String:
	return _state

func get_role() -> String:
	return _role

func get_host_steam_id() -> String:
	return _host_steam_id
