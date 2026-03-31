extends Node
class_name P2PSessionAdapter

signal role_changed(next_role: String)
signal connection_state_changed(next_state: String)
signal host_target_changed(host_steam_id: String)
signal connection_failed(reason_code: String)
signal transport_event(message: String)

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
}

var run_id: String = ""
var local_steam_id: String = ""
var current_role: String = "none"
var current_host_steam_id: String = ""
var _connection_state: int = ConnectionState.DISCONNECTED
var _transport = null

func setup(p_run_id: String, p_local_steam_id: String, transport) -> void:
	run_id = p_run_id.strip_edges()
	local_steam_id = p_local_steam_id.strip_edges()
	current_role = "none"
	current_host_steam_id = ""
	_bind_transport(transport)
	_set_connection_state(ConnectionState.DISCONNECTED)

func switch_host(target_host_steam_id: String) -> Dictionary:
	var target = target_host_steam_id.strip_edges()
	if run_id.is_empty() or local_steam_id.is_empty():
		return _fail("P2P_NOT_INITIALIZED")
	if _transport == null:
		return _fail("P2P_TRANSPORT_MISSING")
	if target.is_empty():
		return _fail("EMPTY_HOST_ID")

	if _connection_state == ConnectionState.CONNECTED and target == current_host_steam_id:
		return {
			"ok": true,
			"changed": false,
			"role": current_role,
			"hostSteamId": current_host_steam_id,
		}

	_set_connection_state(ConnectionState.CONNECTING)
	emit_signal("host_target_changed", target)
	emit_signal("transport_event", "adapter switching host=%s run=%s" % [target, run_id])

	var result = await _transport.connect_to_host(target)
	if not bool(result.get("ok", false)):
		_set_connection_state(ConnectionState.DISCONNECTED)
		return _fail(str(result.get("code", "P2P_CONNECT_FAILED")))

	current_host_steam_id = str(result.get("hostSteamId", _transport.get_host_steam_id()))
	if current_host_steam_id.is_empty():
		current_host_steam_id = target

	var next_role = str(result.get("role", _transport.get_role()))
	if next_role.is_empty():
		next_role = "client"
		if current_host_steam_id == local_steam_id:
			next_role = "host"

	if current_role != next_role:
		current_role = next_role
		emit_signal("role_changed", current_role)
	_set_connection_state(_state_from_text(_transport.get_connection_state_text()))

	return {
		"ok": true,
		"changed": true,
		"role": current_role,
		"hostSteamId": current_host_steam_id,
	}

func disconnect_session(reason_code: String = "MANUAL_STOP") -> void:
	if _connection_state == ConnectionState.DISCONNECTED:
		return
	if _transport != null:
		_transport.disconnect_transport(reason_code)
	emit_signal("transport_event", "adapter disconnect reason=%s" % reason_code)
	current_role = "none"
	current_host_steam_id = ""
	_set_connection_state(ConnectionState.DISCONNECTED)

func get_connection_state_text() -> String:
	match _connection_state:
		ConnectionState.DISCONNECTED:
			return "DISCONNECTED"
		ConnectionState.CONNECTING:
			return "CONNECTING"
		ConnectionState.CONNECTED:
			return "CONNECTED"
		_:
			return "UNKNOWN"

func get_transport_name() -> String:
	if _transport == null:
		return "none"
	return _transport.get_class()

func _set_connection_state(next_state: int) -> void:
	if _connection_state == next_state:
		return
	_connection_state = next_state
	emit_signal("connection_state_changed", get_connection_state_text())

func _bind_transport(transport) -> void:
	if _transport != null and is_instance_valid(_transport):
		if _transport.event_emitted.is_connected(_on_transport_event):
			_transport.event_emitted.disconnect(_on_transport_event)
		if _transport.get_parent() == self:
			_transport.queue_free()
	_transport = transport
	if _transport == null:
		return
	if _transport.get_parent() != self:
		add_child(_transport)
	if not _transport.event_emitted.is_connected(_on_transport_event):
		_transport.event_emitted.connect(_on_transport_event)
	_transport.setup(run_id, local_steam_id)

func _on_transport_event(message: String) -> void:
	emit_signal("transport_event", message)

func _state_from_text(state_text: String) -> int:
	match state_text:
		"CONNECTED":
			return ConnectionState.CONNECTED
		"CONNECTING":
			return ConnectionState.CONNECTING
		_:
			return ConnectionState.DISCONNECTED

func _fail(reason_code: String) -> Dictionary:
	emit_signal("connection_failed", reason_code)
	emit_signal("transport_event", "p2p failure reason=%s" % reason_code)
	return {
		"ok": false,
		"code": reason_code,
	}
