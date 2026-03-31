extends Node
class_name SteamP2PTransport

signal event_emitted(message: String)

@export var listen_port: int = 19090
@export var default_remote_host: String = ""
@export var default_remote_port: int = 19090
@export var endpoint_map_csv: String = ""
@export var connect_timeout_sec: float = 4.0

var _run_id: String = ""
var _local_steam_id: String = ""
var _state: String = "DISCONNECTED"
var _role: String = "none"
var _host_steam_id: String = ""
var _peer: ENetMultiplayerPeer
var _endpoint_map: Dictionary = {}

func setup(run_id: String, local_steam_id: String) -> void:
	_run_id = run_id.strip_edges()
	_local_steam_id = local_steam_id.strip_edges()
	_state = "DISCONNECTED"
	_role = "none"
	_host_steam_id = ""
	_endpoint_map = _parse_endpoint_map(endpoint_map_csv)
	_reset_peer()

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
	emit_signal("event_emitted", "steam_stub transport connect target=%s" % target)

	_reset_peer()
	_peer = ENetMultiplayerPeer.new()

	if target == _local_steam_id:
		return _start_as_host(target)
	return await _connect_as_client(target)

func disconnect_transport(reason_code: String = "MANUAL_STOP") -> void:
	emit_signal("event_emitted", "steam_stub transport disconnect reason=%s" % reason_code)
	_reset_peer()
	_state = "DISCONNECTED"
	_role = "none"
	_host_steam_id = ""

func get_connection_state_text() -> String:
	return _state

func get_role() -> String:
	return _role

func get_host_steam_id() -> String:
	return _host_steam_id

func _start_as_host(target: String) -> Dictionary:
	var port: int = max(listen_port, 1)
	var err := _peer.create_server(port, 8)
	if err != OK:
		_reset_peer()
		_state = "DISCONNECTED"
		return {
			"ok": false,
			"code": "STEAM_STUB_CREATE_SERVER_FAILED",
		}
	_attach_peer(_peer)
	_state = "CONNECTED"
	_role = "host"
	_host_steam_id = target
	emit_signal("event_emitted", "steam_stub listening port=%d" % port)
	return {
		"ok": true,
		"role": _role,
		"hostSteamId": _host_steam_id,
	}

func _connect_as_client(target: String) -> Dictionary:
	var endpoint := _resolve_endpoint_for_host(target)
	if endpoint.is_empty():
		_reset_peer()
		_state = "DISCONNECTED"
		return {
			"ok": false,
			"code": "STEAM_STUB_ENDPOINT_MISSING",
		}

	var host := str(endpoint.get("host", ""))
	var port := int(endpoint.get("port", default_remote_port))
	if host.is_empty() or port <= 0:
		_reset_peer()
		_state = "DISCONNECTED"
		return {
			"ok": false,
			"code": "STEAM_STUB_ENDPOINT_INVALID",
		}

	var err := _peer.create_client(host, port)
	if err != OK:
		_reset_peer()
		_state = "DISCONNECTED"
		return {
			"ok": false,
			"code": "STEAM_STUB_CREATE_CLIENT_FAILED",
		}
	_attach_peer(_peer)
	emit_signal("event_emitted", "steam_stub dialing %s:%d target=%s" % [host, port, target])

	var deadline_ms := Time.get_ticks_msec() + int(max(connect_timeout_sec, 0.5) * 1000.0)
	while Time.get_ticks_msec() < deadline_ms:
		var status := _peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED:
			_state = "CONNECTED"
			_role = "client"
			_host_steam_id = target
			emit_signal("event_emitted", "steam_stub connected host=%s endpoint=%s:%d" % [target, host, port])
			return {
				"ok": true,
				"role": _role,
				"hostSteamId": _host_steam_id,
			}
		if status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			# keep polling until timeout; ENet may transiently toggle.
			pass
		await get_tree().process_frame

	_reset_peer()
	_state = "DISCONNECTED"
	return {
		"ok": false,
		"code": "STEAM_STUB_CONNECT_TIMEOUT",
	}

func _attach_peer(peer: ENetMultiplayerPeer) -> void:
	if get_tree() == null:
		return
	var mp := get_tree().get_multiplayer()
	mp.multiplayer_peer = peer

func _reset_peer() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	if get_tree() != null:
		var mp := get_tree().get_multiplayer()
		if mp.multiplayer_peer != null:
			mp.multiplayer_peer = null

func _resolve_endpoint_for_host(target_steam_id: String) -> Dictionary:
	var key := target_steam_id.strip_edges()
	if _endpoint_map.has(key):
		return _endpoint_map[key]
	var fallback_host := default_remote_host.strip_edges()
	if fallback_host.is_empty():
		return {}
	return {
		"host": fallback_host,
		"port": max(default_remote_port, 1),
	}

func _parse_endpoint_map(raw_text: String) -> Dictionary:
	var output := {}
	for token in raw_text.split(",", false):
		var item := token.strip_edges()
		if item.is_empty():
			continue
		var eq_idx := item.find("=")
		if eq_idx <= 0:
			continue
		var steam_id := item.substr(0, eq_idx).strip_edges()
		var endpoint := item.substr(eq_idx + 1).strip_edges()
		if steam_id.is_empty() or endpoint.is_empty():
			continue

		var host := endpoint
		var port: int = max(default_remote_port, 1)
		var colon_idx := endpoint.rfind(":")
		if colon_idx > 0 and colon_idx < endpoint.length() - 1:
			host = endpoint.substr(0, colon_idx).strip_edges()
			var port_text := endpoint.substr(colon_idx + 1).strip_edges()
			if port_text.is_valid_int():
				port = max(port_text.to_int(), 1)

		if host.is_empty():
			continue
		output[steam_id] = {
			"host": host,
			"port": port,
		}
	return output
