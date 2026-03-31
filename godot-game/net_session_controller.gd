extends Node

@export_enum("offline", "host", "client") var network_mode: String = "offline"
@export_enum("enet_direct", "steam_stub", "steam_relay") var net_transport_mode: String = "enet_direct"
@export var transport_config_enabled: bool = true
@export var transport_config_path: String = "res://net_transport.cfg"
@export var auto_start_network: bool = false
@export var server_host: String = "127.0.0.1"
@export var server_port: int = 19090
@export var steam_app_id: int = 408
@export var steam_embed_callbacks: bool = true
@export var steam_virtual_port: int = 0
@export var steam_local_id: String = ""
@export var steam_target_host_id: String = ""
@export var steam_stub_listen_port: int = 19090
@export var steam_stub_default_remote_host: String = "127.0.0.1"
@export var steam_stub_default_remote_port: int = 19090
@export var steam_stub_endpoint_map_csv: String = ""
@export var send_interval_sec: float = 0.05
@export var hero_sync_interval_sec: float = 0.05
@export var world_sync_interval_sec: float = 0.08
@export var adaptive_world_sync_enabled: bool = true
@export var world_sync_interval_min_sec: float = 0.07
@export var world_sync_interval_max_sec: float = 0.24
@export var world_sync_backoff_step_sec: float = 0.02
@export var world_sync_recover_step_sec: float = 0.01
@export var world_packet_budget_bytes: int = 1180
@export var world_mob_chunk_size: int = 4
@export var world_mob_chunk_size_min: int = 2
@export var world_mob_chunk_size_max: int = 8
@export var world_full_sync_mob_threshold: int = 12

@export var hero_controller_path: NodePath = NodePath("../HeroController")
@export var fallback_local_hero_path: NodePath = NodePath("../HeroController/herowarden")
@export var game_ui_path: NodePath = NodePath("../GameUI")
@export var boss_controller_path: NodePath = NodePath("../EnemyAI")
@export var tauren_spawner_path: NodePath = NodePath("../TaurenSpawner")
@export var remote_players_root_path: NodePath = NodePath("../NetworkPlayers")
@export var remote_melee_player_scene: PackedScene = preload("res://modles/herowarden.glb")
@export var remote_ranged_player_scene: PackedScene = preload("res://modles/Rifleman.glb")
@export var remote_transformed_player_scene: PackedScene = preload("res://modles/SpiritOfVengeance.before_trim.glb")
@export var remote_player_scene: PackedScene = preload("res://modles/herowarden.glb")
@export var remote_player_scale: Vector3 = Vector3.ONE
@export var remote_position_smooth_speed: float = 16.0
@export var remote_rotation_smooth_speed: float = 14.0
@export var remote_snap_distance: float = 260.0
@export var remote_select_screen_radius: float = 72.0
@export var sync_skill_effects: bool = true
@export var remote_flash_effect_scene: PackedScene = preload("res://effects/HeroWarden/FanOfKnivesCaster/FanOfKnivesCaster.glb")
@export var remote_flash_effect_scale: Vector3 = Vector3(2.0, 2.0, 2.0)
@export var remote_haste_effect_scale: Vector3 = Vector3(1.35, 1.35, 1.35)
@export var remote_skill_effect_fallback_lifetime: float = 1.8
@export var remote_ranged_q_ray_length: float = 780.0
@export var remote_ranged_q_ray_width: float = 16.0
@export var remote_ranged_q_ray_thickness: float = 2.0
@export var remote_ranged_q_ray_lifetime: float = 0.12

@export var sync_hero_state: bool = true
@export var sync_equipment_state: bool = true
@export var sync_boss_state: bool = true
@export var sync_mob_state: bool = true

const SKILL_ID_W_RANGED_SPEED: int = 202

var _peer: MultiplayerPeer = null
var _is_network_running: bool = false
var _send_elapsed_sec: float = 0.0
var _hero_send_elapsed_sec: float = 0.0
var _world_send_elapsed_sec: float = 0.0
var _dynamic_world_sync_interval_sec: float = 0.08
var _dynamic_world_mob_chunk_size: int = 4
var _world_mob_chunk_cursor: int = 0
var _last_world_packet_bytes: int = 0
var _status_refresh_elapsed_sec: float = 0.0
var _remote_players_root: Node3D = null
var _remote_avatars: Dictionary = {}
var _remote_avatar_model_keys: Dictionary = {}
var _remote_avatar_last_anims: Dictionary = {}
var _remote_avatar_target_positions: Dictionary = {}
var _remote_avatar_target_yaws: Dictionary = {}
var _remote_last_flash_cd: Dictionary = {}
var _remote_last_haste_active: Dictionary = {}
var _remote_last_skill_event_seq: Dictionary = {}

var _peer_latest_hero_state: Dictionary = {}
var _peer_latest_equipment_state: Dictionary = {}
var _host_hero_snapshot_seq: int = 0
var _last_applied_hero_snapshot_seq: int = -1
var _local_prev_flash_cd: float = 0.0
var _local_prev_haste_active: bool = false
var _local_skill_event_seq: int = 0
var _local_last_skill_event: Dictionary = {}
var _local_prev_explicit_skill_event_seq: int = -1
var _steam_stub_endpoint_map: Dictionary = {}
var _steam_singleton: Object = null
var _steam_initialized: bool = false

var _status_layer: CanvasLayer = null
var _status_panel: PanelContainer = null
var _status_label: Label = null
var _last_status_text: String = ""
var _status_event_hint: String = ""
var _ui_observed_peer_id: int = 0

func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)
	add_to_group("net_session_controller")
	_reset_world_sync_adaptive_runtime()
	_reset_local_skill_event_runtime(true)
	_connect_multiplayer_signals_once()
	_ensure_remote_players_root()
	_create_status_overlay()
	_apply_transport_config_overrides()
	_apply_cmdline_overrides()
	_refresh_steam_stub_endpoint_map()
	_apply_network_authority_mode()
	_notify_game_ui_observe_peer(0)
	if auto_start_network and network_mode != "offline":
		start_network()
	else:
		_status_event_hint = ""
		_refresh_status_text()

func _exit_tree() -> void:
	stop_network()

func _process(delta: float) -> void:
	_pump_steam_callbacks_if_needed()
	_update_remote_avatar_smoothing(delta)
	_status_refresh_elapsed_sec += maxf(delta, 0.0)
	if _status_refresh_elapsed_sec >= 0.5:
		_status_refresh_elapsed_sec = 0.0
		_refresh_status_text()

func _physics_process(delta: float) -> void:
	if not _is_network_running:
		return
	var mode: String = network_mode.strip_edges().to_lower()
	if mode == "host":
		_tick_host(delta)
	elif mode == "client":
		_tick_client(delta)

func _unhandled_input(event: InputEvent) -> void:
	if not _is_network_running:
		return
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event == null:
		return
	if not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	var clicked_peer_id: int = _pick_remote_peer_by_mouse_position(mouse_event.position)
	if clicked_peer_id > 0:
		if _ui_observed_peer_id != clicked_peer_id:
			_ui_observed_peer_id = clicked_peer_id
			_notify_game_ui_observe_peer(_ui_observed_peer_id)
		return
	if _is_click_on_local_hero(mouse_event.position):
		if _ui_observed_peer_id != 0:
			_ui_observed_peer_id = 0
			_notify_game_ui_observe_peer(0)

func _tick_host(delta: float) -> void:
	var host_id: int = multiplayer.get_unique_id()
	if host_id > 0:
		if sync_hero_state:
			_peer_latest_hero_state[host_id] = _collect_local_hero_state()
		if sync_equipment_state:
			_peer_latest_equipment_state[host_id] = _collect_local_equipment_state()

	if multiplayer.get_peers().is_empty():
		return

	_hero_send_elapsed_sec += maxf(delta, 0.0)
	if _hero_send_elapsed_sec >= maxf(hero_sync_interval_sec, 0.02):
		_hero_send_elapsed_sec = 0.0
		var hero_snapshot: Dictionary = _build_hero_snapshot()
		rpc("rpc_hero_snapshot", hero_snapshot)

	_world_send_elapsed_sec += maxf(delta, 0.0)
	var active_world_interval: float = _get_active_world_sync_interval_sec()
	if _world_send_elapsed_sec >= active_world_interval:
		_world_send_elapsed_sec = 0.0
		var world_snapshot: Dictionary = _build_world_snapshot()
		_last_world_packet_bytes = _estimate_payload_bytes(world_snapshot)
		_adjust_dynamic_world_sync_interval(world_snapshot, _last_world_packet_bytes)
		rpc("rpc_world_snapshot", world_snapshot)

func _tick_client(delta: float) -> void:
	_send_elapsed_sec += maxf(delta, 0.0)
	if _send_elapsed_sec < maxf(send_interval_sec, 0.01):
		return
	_send_elapsed_sec = 0.0
	if multiplayer.get_peers().is_empty():
		return
	var hero_state: Dictionary = _collect_local_hero_state()
	var equipment_state: Dictionary = _collect_local_equipment_state()
	var combat_report: Dictionary = _collect_client_combat_report()
	rpc_id(1, "rpc_submit_client_state", hero_state, equipment_state, combat_report)

func start_network() -> void:
	stop_network()

	var mode: String = network_mode.strip_edges().to_lower()
	if mode == "offline":
		_status_event_hint = ""
		_refresh_status_text()
		return

	_refresh_steam_stub_endpoint_map()
	var transport_mode: String = net_transport_mode.strip_edges().to_lower()
	var err: int = ERR_CANT_CREATE
	var start_hint: String = "network_started"
	if transport_mode == "steam_relay":
		var relay_result: Dictionary = _create_steam_relay_peer(mode)
		err = _int_from_variant(relay_result.get("err", ERR_CANT_CREATE), ERR_CANT_CREATE)
		if bool(relay_result.get("ok", false)):
			var relay_peer_variant: Variant = relay_result.get("peer", null)
			if relay_peer_variant is MultiplayerPeer:
				_peer = relay_peer_variant as MultiplayerPeer
			else:
				_peer = null
				err = ERR_CANT_CREATE
		if relay_result.has("hint"):
			start_hint = str(relay_result.get("hint", start_hint))
	elif transport_mode == "steam_stub":
		var steam_stub_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		var local_id: String = _resolve_effective_steam_local_id()
		var target_host_id: String = steam_target_host_id.strip_edges()
		if target_host_id.is_empty():
			if mode == "host":
				target_host_id = local_id
			elif not server_host.strip_edges().is_empty():
				target_host_id = server_host.strip_edges()
		if mode == "host":
			var listen_port: int = maxi(steam_stub_listen_port, 1)
			err = steam_stub_peer.create_server(listen_port, 8)
			start_hint = "network_started(steam_stub app=%d local=%s host_id=%s listen=%d)" % [
				steam_app_id,
				local_id if not local_id.is_empty() else "-",
				target_host_id if not target_host_id.is_empty() else "-",
				listen_port
			]
		else:
			var endpoint: Dictionary = _resolve_steam_stub_endpoint(target_host_id)
			var remote_host: String = str(endpoint.get("host", "")).strip_edges()
			var remote_port: int = _int_from_variant(endpoint.get("port", steam_stub_default_remote_port), steam_stub_default_remote_port)
			if remote_host.is_empty() or remote_port <= 0:
				err = ERR_INVALID_PARAMETER
			else:
				err = steam_stub_peer.create_client(remote_host, maxi(remote_port, 1))
				start_hint = "network_started(steam_stub app=%d local=%s host_id=%s dial=%s:%d)" % [
					steam_app_id,
					local_id if not local_id.is_empty() else "-",
					target_host_id if not target_host_id.is_empty() else "-",
					remote_host,
					remote_port
				]
		if err == OK:
			_peer = steam_stub_peer
	else:
		var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
		if mode == "host":
			err = enet_peer.create_server(maxi(server_port, 1), 8)
		else:
			err = enet_peer.create_client(server_host.strip_edges(), maxi(server_port, 1))
		start_hint = "network_started(enet_direct)"
		if err == OK:
			_peer = enet_peer

	if err != OK:
		_peer = null
		var fail_hint: String = "start_failed(err=%d)" % err
		if start_hint.begins_with("start_failed("):
			fail_hint = start_hint
		_status_event_hint = fail_hint
		_refresh_status_text()
		push_error("net_session_controller: %s" % fail_hint)
		return

	multiplayer.multiplayer_peer = _peer
	_is_network_running = true
	_send_elapsed_sec = 0.0
	_hero_send_elapsed_sec = 0.0
	_world_send_elapsed_sec = 0.0
	_host_hero_snapshot_seq = 0
	_last_applied_hero_snapshot_seq = -1
	_reset_world_sync_adaptive_runtime()
	_reset_local_skill_event_runtime(true)
	_status_refresh_elapsed_sec = 0.0
	_status_event_hint = start_hint
	_apply_network_authority_mode()
	_refresh_status_text()

func stop_network() -> void:
	_clear_remote_avatars()
	_peer_latest_hero_state.clear()
	_peer_latest_equipment_state.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_peer = null
	_is_network_running = false
	_send_elapsed_sec = 0.0
	_hero_send_elapsed_sec = 0.0
	_world_send_elapsed_sec = 0.0
	_host_hero_snapshot_seq = 0
	_last_applied_hero_snapshot_seq = -1
	_reset_world_sync_adaptive_runtime()
	_reset_local_skill_event_runtime(false)
	_status_refresh_elapsed_sec = 0.0
	_status_event_hint = ""
	_ui_observed_peer_id = 0
	_notify_game_ui_observe_peer(0)
	_apply_network_authority_mode()
	_refresh_status_text()

func _connect_multiplayer_signals_once() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)

func _on_peer_connected(peer_id: int) -> void:
	_status_event_hint = "peer_connected(id=%d)" % peer_id
	_refresh_status_text()

func _on_peer_disconnected(peer_id: int) -> void:
	_remove_remote_avatar(peer_id)
	_peer_latest_hero_state.erase(peer_id)
	_peer_latest_equipment_state.erase(peer_id)
	if _ui_observed_peer_id == peer_id:
		_ui_observed_peer_id = 0
		_notify_game_ui_observe_peer(0)
	_status_event_hint = "peer_disconnected(id=%d)" % peer_id
	_refresh_status_text()

func _on_connected_to_server() -> void:
	_status_event_hint = "connected_to_server"
	_refresh_status_text()

func _on_connection_failed() -> void:
	if _is_network_running:
		stop_network()
	_status_event_hint = "connection_failed"
	_refresh_status_text()

func _on_server_disconnected() -> void:
	if _is_network_running:
		stop_network()
	_status_event_hint = "server_disconnected"
	_refresh_status_text()

@rpc("any_peer", "reliable")
func rpc_submit_client_state(hero_state: Dictionary, equipment_state: Dictionary, combat_report: Dictionary = {}) -> void:
	if network_mode.strip_edges().to_lower() != "host":
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	if sync_hero_state:
		_peer_latest_hero_state[sender_id] = hero_state
		_upsert_remote_avatar_from_state(sender_id, hero_state)
	if sync_equipment_state:
		_peer_latest_equipment_state[sender_id] = equipment_state
	_merge_client_combat_report(combat_report, sender_id)

@rpc("authority", "reliable")
func rpc_hero_snapshot(snapshot: Dictionary) -> void:
	if network_mode.strip_edges().to_lower() == "host":
		return
	_apply_world_snapshot(snapshot)

@rpc("authority", "unreliable")
func rpc_world_snapshot(snapshot: Dictionary) -> void:
	if network_mode.strip_edges().to_lower() == "host":
		return
	_apply_world_snapshot(snapshot)

@rpc("authority", "call_remote", "reliable")
func rpc_apply_hero_damage_from_authority(amount: int, ignore_armor: bool = false) -> void:
	if network_mode.strip_edges().to_lower() == "host":
		return
	var hero_controller: Node = _get_hero_controller()
	if hero_controller != null and hero_controller.has_method("apply_damage"):
		hero_controller.call("apply_damage", maxi(amount, 0), ignore_armor, null)

@rpc("authority", "call_remote", "reliable")
func rpc_apply_hero_slow_from_authority(slow_percent: float, duration: float) -> void:
	if network_mode.strip_edges().to_lower() == "host":
		return
	var hero_controller: Node = _get_hero_controller()
	if hero_controller != null and hero_controller.has_method("apply_temporary_slow"):
		hero_controller.call("apply_temporary_slow", slow_percent, duration)

func _build_world_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	snapshot["timestamp_ms"] = Time.get_ticks_msec()
	if sync_boss_state:
		snapshot["boss"] = _collect_boss_state()
	if sync_mob_state:
		var all_mobs: Array = _collect_mob_states()
		var total_mobs: int = all_mobs.size()
		var chunk_size: int = _get_active_world_mob_chunk_size(total_mobs)
		if total_mobs <= 0:
			snapshot["mobs"] = []
			snapshot["mobs_partial"] = false
			snapshot["mobs_total"] = 0
			snapshot["mobs_start"] = 0
			_world_mob_chunk_cursor = 0
		elif (world_full_sync_mob_threshold > 0 and total_mobs <= world_full_sync_mob_threshold) or chunk_size >= total_mobs:
			snapshot["mobs"] = all_mobs
			snapshot["mobs_partial"] = false
			snapshot["mobs_total"] = total_mobs
			snapshot["mobs_start"] = 0
			_world_mob_chunk_cursor = 0
		else:
			var start_idx: int = clampi(_world_mob_chunk_cursor, 0, maxi(total_mobs - 1, 0))
			var mobs_chunk: Array = []
			for i in range(chunk_size):
				var idx: int = (start_idx + i) % total_mobs
				mobs_chunk.append(all_mobs[idx])
			snapshot["mobs"] = mobs_chunk
			snapshot["mobs_partial"] = true
			snapshot["mobs_total"] = total_mobs
			snapshot["mobs_start"] = start_idx
			_world_mob_chunk_cursor = (start_idx + chunk_size) % total_mobs
	return snapshot


func _build_hero_snapshot() -> Dictionary:
	var snapshot: Dictionary = {}
	_host_hero_snapshot_seq += 1
	snapshot["hero_seq"] = _host_hero_snapshot_seq
	snapshot["timestamp_ms"] = Time.get_ticks_msec()
	snapshot["host_peer_id"] = multiplayer.get_unique_id()
	if sync_hero_state:
		snapshot["host_hero"] = _collect_local_hero_state()
	if sync_equipment_state:
		snapshot["host_equipment"] = _collect_local_equipment_state()

	var peers_payload: Dictionary = {}
	for key_variant in _peer_latest_hero_state.keys():
		var peer_id: int = int(key_variant)
		if peer_id == multiplayer.get_unique_id():
			continue
		var payload: Dictionary = {}
		if sync_hero_state and _peer_latest_hero_state.has(peer_id):
			payload["hero"] = _peer_latest_hero_state[peer_id]
		if sync_equipment_state and _peer_latest_equipment_state.has(peer_id):
			payload["equipment"] = _peer_latest_equipment_state[peer_id]
		peers_payload[str(peer_id)] = payload
	snapshot["peers"] = peers_payload
	return snapshot


func _reset_world_sync_adaptive_runtime() -> void:
	var min_interval: float = minf(world_sync_interval_min_sec, world_sync_interval_max_sec)
	var max_interval: float = maxf(world_sync_interval_min_sec, world_sync_interval_max_sec)
	_dynamic_world_sync_interval_sec = clampf(world_sync_interval_sec, min_interval, max_interval)
	var min_chunk: int = maxi(mini(world_mob_chunk_size_min, world_mob_chunk_size_max), 1)
	var max_chunk: int = maxi(maxi(world_mob_chunk_size_min, world_mob_chunk_size_max), min_chunk)
	_dynamic_world_mob_chunk_size = clampi(world_mob_chunk_size, min_chunk, max_chunk)
	_world_mob_chunk_cursor = 0
	_last_world_packet_bytes = 0


func _get_active_world_sync_interval_sec() -> float:
	if not adaptive_world_sync_enabled:
		return maxf(world_sync_interval_sec, 0.02)
	var min_interval: float = minf(world_sync_interval_min_sec, world_sync_interval_max_sec)
	var max_interval: float = maxf(world_sync_interval_min_sec, world_sync_interval_max_sec)
	return clampf(_dynamic_world_sync_interval_sec, min_interval, max_interval)


func _get_active_world_mob_chunk_size(total_mobs: int) -> int:
	if total_mobs <= 0:
		return 0
	var base_chunk: int = world_mob_chunk_size
	if adaptive_world_sync_enabled:
		base_chunk = _dynamic_world_mob_chunk_size
	return clampi(base_chunk, 1, total_mobs)


func _estimate_payload_bytes(payload: Variant) -> int:
	var payload_bytes: PackedByteArray = var_to_bytes(payload)
	return payload_bytes.size()


func _extract_mob_count_from_snapshot(snapshot: Dictionary) -> int:
	var total_variant: Variant = snapshot.get("mobs_total", null)
	if total_variant != null:
		return _int_from_variant(total_variant, 0)
	var mobs_variant: Variant = snapshot.get("mobs", [])
	if mobs_variant is Array:
		return (mobs_variant as Array).size()
	return 0


func _adjust_dynamic_world_sync_interval(snapshot: Dictionary, packet_bytes: int) -> void:
	if not adaptive_world_sync_enabled:
		return

	var min_interval: float = minf(world_sync_interval_min_sec, world_sync_interval_max_sec)
	var max_interval: float = maxf(world_sync_interval_min_sec, world_sync_interval_max_sec)
	var budget: int = maxi(world_packet_budget_bytes, 256)
	var mob_count: int = _extract_mob_count_from_snapshot(snapshot)
	var over_budget: bool = packet_bytes > budget
	var severe_over_budget: bool = packet_bytes > int(round(float(budget) * 1.35))
	var heavy_mobs: bool = mob_count >= 8

	if severe_over_budget:
		_dynamic_world_sync_interval_sec = minf(_dynamic_world_sync_interval_sec + maxf(world_sync_backoff_step_sec, 0.005) * 1.8, max_interval)
	elif over_budget:
		_dynamic_world_sync_interval_sec = minf(_dynamic_world_sync_interval_sec + maxf(world_sync_backoff_step_sec, 0.005), max_interval)
	elif heavy_mobs:
		_dynamic_world_sync_interval_sec = minf(_dynamic_world_sync_interval_sec + maxf(world_sync_backoff_step_sec, 0.005) * 0.35, max_interval)
	else:
		_dynamic_world_sync_interval_sec = maxf(_dynamic_world_sync_interval_sec - maxf(world_sync_recover_step_sec, 0.003), min_interval)

	var min_chunk: int = maxi(mini(world_mob_chunk_size_min, world_mob_chunk_size_max), 1)
	var max_chunk: int = maxi(maxi(world_mob_chunk_size_min, world_mob_chunk_size_max), min_chunk)
	if severe_over_budget or over_budget:
		if _dynamic_world_mob_chunk_size > min_chunk:
			_dynamic_world_mob_chunk_size -= 1
	elif packet_bytes < int(round(float(budget) * 0.55)):
		if _dynamic_world_mob_chunk_size < max_chunk:
			_dynamic_world_mob_chunk_size += 1
	_dynamic_world_mob_chunk_size = clampi(_dynamic_world_mob_chunk_size, min_chunk, max_chunk)

func _apply_world_snapshot(snapshot: Dictionary) -> void:
	var self_id: int = 0
	if multiplayer.multiplayer_peer != null:
		self_id = multiplayer.get_unique_id()

	var host_id: int = int(snapshot.get("host_peer_id", 1))
	var valid_remote_ids: Dictionary = {}
	var has_hero_payload: bool = false
	if sync_hero_state:
		if snapshot.has("host_hero"):
			has_hero_payload = true
		elif snapshot.has("peers"):
			has_hero_payload = true

	if has_hero_payload and snapshot.has("hero_seq"):
		var incoming_seq: int = _int_from_variant(snapshot.get("hero_seq", -1), -1)
		if incoming_seq >= 0:
			if incoming_seq <= _last_applied_hero_snapshot_seq:
				return
			_last_applied_hero_snapshot_seq = incoming_seq

	if sync_hero_state and snapshot.has("host_hero"):
		var host_hero_variant: Variant = snapshot["host_hero"]
		if host_hero_variant is Dictionary:
			var host_hero: Dictionary = host_hero_variant
			_peer_latest_hero_state[host_id] = host_hero
			if host_id != self_id:
				_upsert_remote_avatar_from_state(host_id, host_hero)
				valid_remote_ids[host_id] = true

	if sync_equipment_state and snapshot.has("host_equipment"):
		var host_eq_variant: Variant = snapshot["host_equipment"]
		if host_eq_variant is Dictionary:
			_peer_latest_equipment_state[host_id] = host_eq_variant

	var peers_variant: Variant = null
	if snapshot.has("peers"):
		peers_variant = snapshot["peers"]
	if peers_variant is Dictionary:
		var peers_payload: Dictionary = peers_variant
		for key_variant in peers_payload.keys():
			var peer_id: int = int(str(key_variant))
			var payload_variant: Variant = peers_payload[key_variant]
			if not (payload_variant is Dictionary):
				continue
			var payload: Dictionary = payload_variant
			if sync_hero_state and payload.has("hero"):
				var hero_variant: Variant = payload["hero"]
				if hero_variant is Dictionary:
					var hero_state: Dictionary = hero_variant
					_peer_latest_hero_state[peer_id] = hero_state
					if peer_id != self_id:
						_upsert_remote_avatar_from_state(peer_id, hero_state)
						valid_remote_ids[peer_id] = true
			if sync_equipment_state and payload.has("equipment"):
				var eq_variant: Variant = payload["equipment"]
				if eq_variant is Dictionary:
					_peer_latest_equipment_state[peer_id] = eq_variant

	if sync_boss_state and snapshot.has("boss"):
		var boss_variant: Variant = snapshot["boss"]
		if boss_variant is Dictionary:
			_apply_boss_state(boss_variant)

	if sync_mob_state and snapshot.has("mobs"):
		var mobs_variant: Variant = snapshot["mobs"]
		if mobs_variant is Array:
			_apply_mob_states(mobs_variant)

	if has_hero_payload:
		_remove_absent_remote_avatars(valid_remote_ids)
	_refresh_status_text()

func _collect_local_hero_state() -> Dictionary:
	var state: Dictionary = {}
	var hero: Node3D = _get_local_hero()
	if hero == null:
		return state
	state["pos"] = hero.global_position
	state["yaw"] = hero.rotation.y
	state["visible"] = hero.visible
	state["scale"] = hero.scale

	var hero_controller: Node = _get_hero_controller()
	if hero_controller != null:
		state["hp"] = _int_from_variant(hero_controller.get("_current_hp"), 0)
		state["max_hp"] = _int_from_variant(hero_controller.get("max_hp"), 0)
		state["mana"] = _int_from_variant(hero_controller.get("current_mana"), 0)
		state["max_mana"] = _int_from_variant(hero_controller.get("max_mana"), 0)
		state["flash_cd"] = _float_from_variant(hero_controller.get("_flash_cooldown"), 0.0)
		state["haste_cd"] = _float_from_variant(hero_controller.get("_haste_cooldown"), 0.0)
		state["haste_active"] = _bool_from_variant(hero_controller.get("_haste_active"), false)
		state["haste_left"] = _float_from_variant(hero_controller.get("_haste_time_left"), 0.0)
		state["is_moving"] = _bool_from_variant(hero_controller.get("_is_moving"), false)
		state["is_attacking"] = _bool_from_variant(hero_controller.get("_is_attacking"), false)
		state["skill_q_id"] = _int_from_variant(hero_controller.get("skill_q_id"), 0)
		state["skill_q_name"] = str(hero_controller.get("skill_q_name"))
		state["skill_w_id"] = _int_from_variant(hero_controller.get("skill_w_id"), 0)
		state["skill_w_name"] = str(hero_controller.get("skill_w_name"))
		state["hero_id"] = _int_from_variant(hero_controller.get("hero_id"), 1)
		state["hero_profile"] = str(hero_controller.get("hero_profile"))
		state["is_transformed"] = _bool_from_variant(hero_controller.get("_is_transformed"), false)
		state["transform_left"] = _float_from_variant(hero_controller.get("_transform_time_left"), 0.0)
		state["damage"] = _int_from_variant(hero_controller.get("damage_per_hit"), 0)
		state["armor"] = _float_from_variant(hero_controller.get("armor"), 0.0)
		state["move_speed"] = _float_from_variant(hero_controller.get("move_speed"), 0.0)
		state["attack_speed"] = _float_from_variant(hero_controller.get("attack_speed"), 0.0)
		state["attack_interval"] = _float_from_variant(hero_controller.get("attack_interval"), 0.0)
		state["attack_range"] = _float_from_variant(hero_controller.get("attack_range"), 0.0)
		state["cooldown_reduction_percent_total"] = _float_from_variant(hero_controller.get("cooldown_reduction_percent_total"), 0.0)
		state["physical_crit_chance"] = _float_from_variant(hero_controller.get("physical_crit_chance"), 0.0)
		state["physical_crit_multiplier"] = _float_from_variant(hero_controller.get("physical_crit_multiplier"), 0.0)
		state["spell_crit_chance"] = _float_from_variant(hero_controller.get("spell_crit_chance"), 0.0)
		state["spell_crit_multiplier"] = _float_from_variant(hero_controller.get("spell_crit_multiplier"), 0.0)
		state["strength"] = _int_from_variant(hero_controller.get("strength"), 0)
		state["agility"] = _int_from_variant(hero_controller.get("agility"), 0)
		state["intelligence"] = _int_from_variant(hero_controller.get("intelligence"), 0)
		state["hp_regen_per_second"] = _float_from_variant(hero_controller.get("hp_regen_per_second"), 0.0)
		state["mana_regen_per_second"] = _float_from_variant(hero_controller.get("mana_regen_per_second"), 0.0)
		if hero_controller.has_method("is_dead"):
			state["is_dead"] = bool(hero_controller.call("is_dead"))
		else:
			state["is_dead"] = false

	var anim_player: AnimationPlayer = hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player != null:
		state["anim_name"] = String(anim_player.current_animation)
		state["anim_playing"] = anim_player.is_playing()
		state["anim_speed"] = anim_player.speed_scale
	var has_explicit_skill_event: bool = false
	if hero_controller != null:
		var explicit_event_variant: Variant = hero_controller.get("_network_last_skill_event")
		if explicit_event_variant is Dictionary:
			var explicit_event: Dictionary = explicit_event_variant
			var explicit_seq: int = _int_from_variant(explicit_event.get("seq", -1), -1)
			if explicit_seq >= 0:
				has_explicit_skill_event = true
				if explicit_seq > _local_prev_explicit_skill_event_seq:
					_local_prev_explicit_skill_event_seq = explicit_seq
					_local_last_skill_event = explicit_event.duplicate(true)
	if not has_explicit_skill_event:
		_update_local_skill_event_from_state(state)
	if not _local_last_skill_event.is_empty():
		state["skill_event"] = _local_last_skill_event.duplicate(true)
	return state

func _collect_local_equipment_state() -> Dictionary:
	var state: Dictionary = {}
	var hero_controller: Node = _get_hero_controller()
	if hero_controller != null:
		state["inventory"] = _extract_inventory_from_hero_controller(hero_controller)
	var ui: Node = _get_game_ui()
	if ui != null:
		state["gold"] = _int_from_variant(ui.get("_gold"), 0)
		state["shop_level"] = _int_from_variant(ui.get("_shop_level"), 1)
	return state

func _extract_inventory_from_hero_controller(hero_controller: Node) -> Array:
	var out: Array = []
	if hero_controller == null:
		return out
	var inv_variant: Variant = hero_controller.get("inventory")
	if inv_variant is Array:
		var inv: Array = inv_variant
		for item in inv:
			out.append(int(item))
	return out

func _collect_boss_state() -> Dictionary:
	var boss_controller: Node = _get_boss_controller()
	if boss_controller == null:
		return {}
	if boss_controller.has_method("export_network_state"):
		var exported_variant: Variant = boss_controller.call("export_network_state")
		if exported_variant is Dictionary:
			return exported_variant

	var state: Dictionary = {}
	var boss_model_variant: Variant = boss_controller.get("_enemy")
	if boss_model_variant is Node3D:
		var boss_model: Node3D = boss_model_variant
		state["pos"] = boss_model.global_position
		state["yaw"] = boss_model.rotation.y
		state["visible"] = boss_model.visible
	state["hp"] = _int_from_variant(boss_controller.get("_current_hp"), 0)
	state["max_hp"] = _int_from_variant(boss_controller.get("max_hp"), 0)
	state["dead"] = _bool_from_variant(boss_controller.get("_is_dead"), false)
	return state

func _apply_boss_state(state: Dictionary) -> void:
	var boss_controller: Node = _get_boss_controller()
	if boss_controller == null:
		return
	if boss_controller.has_method("apply_network_state"):
		boss_controller.call("apply_network_state", state)
		return

	var boss_model_variant: Variant = boss_controller.get("_enemy")
	if boss_model_variant is Node3D:
		var boss_model: Node3D = boss_model_variant
		var pos_variant: Variant = state.get("pos", boss_model.global_position)
		if pos_variant is Vector3:
			boss_model.global_position = pos_variant
		var rot: Vector3 = boss_model.rotation
		rot.y = _float_from_variant(state.get("yaw", rot.y), rot.y)
		boss_model.rotation = rot
		boss_model.visible = _bool_from_variant(state.get("visible", true), true)

	if state.has("max_hp"):
		boss_controller.set("max_hp", maxi(int(state["max_hp"]), 1))
	if state.has("hp"):
		var max_hp: int = _int_from_variant(boss_controller.get("max_hp"), 1)
		boss_controller.set("_current_hp", clampi(int(state["hp"]), 0, maxi(max_hp, 1)))
	if state.has("dead"):
		boss_controller.set("_is_dead", _bool_from_variant(state["dead"], false))
	if boss_controller.has_method("_update_hp_bar"):
		boss_controller.call("_update_hp_bar")

func _collect_mob_states() -> Array:
	var spawner: Node = _get_tauren_spawner()
	if spawner == null:
		return []
	if spawner.has_method("collect_network_states"):
		var states_variant: Variant = spawner.call("collect_network_states")
		if states_variant is Array:
			return states_variant
	return []

func _apply_mob_states(states: Array) -> void:
	var spawner: Node = _get_tauren_spawner()
	if spawner == null:
		return
	if spawner.has_method("apply_network_states"):
		spawner.call("apply_network_states", states)


func _collect_client_combat_report() -> Dictionary:
	var report: Dictionary = {}
	if sync_boss_state:
		var boss_state: Dictionary = _collect_boss_state()
		if not boss_state.is_empty():
			report["boss"] = {
				"hp": _int_from_variant(boss_state.get("hp", 0), 0),
				"dead": _bool_from_variant(boss_state.get("dead", false), false)
			}
	if sync_mob_state:
		var mobs: Array = _collect_mob_states()
		var damage_states: Array = []
		for mob_variant in mobs:
			if not (mob_variant is Dictionary):
				continue
			var mob_state: Dictionary = mob_variant
			damage_states.append({
				"id": str(mob_state.get("id", "")),
				"hp": _int_from_variant(mob_state.get("hp", 0), 0),
				"dead": _bool_from_variant(mob_state.get("dead", false), false)
			})
		report["mobs"] = damage_states
	return report


func _merge_client_combat_report(report: Dictionary, reporter_peer_id: int = 0) -> void:
	if report.is_empty():
		return
	if sync_boss_state and report.has("boss"):
		var boss_variant: Variant = report["boss"]
		if boss_variant is Dictionary:
			_merge_client_boss_damage_state(boss_variant, reporter_peer_id)
	if sync_mob_state and report.has("mobs"):
		var mobs_variant: Variant = report["mobs"]
		if mobs_variant is Array:
			_merge_client_mob_damage_states(mobs_variant, reporter_peer_id)


func _merge_client_boss_damage_state(state: Dictionary, reporter_peer_id: int = 0) -> void:
	var boss_controller: Node = _get_boss_controller()
	if boss_controller == null:
		return
	var attacker_avatar: Node3D = _get_remote_avatar_for_peer(reporter_peer_id)
	var current_hp: int = _int_from_variant(boss_controller.get("_current_hp"), 0)
	var reported_hp: int = _int_from_variant(state.get("hp", current_hp), current_hp)
	reported_hp = clampi(reported_hp, 0, maxi(_int_from_variant(boss_controller.get("max_hp"), 1), 1))
	if reported_hp < current_hp and boss_controller.has_method("apply_damage"):
		boss_controller.call("apply_damage", current_hp - reported_hp, attacker_avatar)
	var reported_dead: bool = _bool_from_variant(state.get("dead", false), false)
	if reported_dead and not _bool_from_variant(boss_controller.get("_is_dead"), false):
		var now_hp: int = _int_from_variant(boss_controller.get("_current_hp"), 0)
		if now_hp > 0 and boss_controller.has_method("apply_damage"):
			boss_controller.call("apply_damage", now_hp, attacker_avatar)


func _merge_client_mob_damage_states(states: Array, reporter_peer_id: int = 0) -> void:
	var spawner: Node = _get_tauren_spawner()
	if spawner == null:
		return
	var attacker_avatar: Node3D = _get_remote_avatar_for_peer(reporter_peer_id)
	if spawner.has_method("merge_client_damage_states"):
		spawner.call("merge_client_damage_states", states, attacker_avatar)


func _get_remote_avatar_for_peer(peer_id: int) -> Node3D:
	if peer_id <= 0:
		return null
	if not _remote_avatars.has(peer_id):
		return null
	var avatar: Node3D = _remote_avatars[peer_id] as Node3D
	if avatar == null or not is_instance_valid(avatar):
		return null
	return avatar


func request_damage_remote_hero(peer_id: int, amount: int, ignore_armor: bool = false) -> void:
	if network_mode.strip_edges().to_lower() != "host":
		return
	if multiplayer.multiplayer_peer == null:
		return
	if peer_id <= 0:
		return
	rpc_id(peer_id, "rpc_apply_hero_damage_from_authority", maxi(amount, 0), ignore_armor)


func request_slow_remote_hero(peer_id: int, slow_percent: float, duration: float) -> void:
	if network_mode.strip_edges().to_lower() != "host":
		return
	if multiplayer.multiplayer_peer == null:
		return
	if peer_id <= 0:
		return
	rpc_id(peer_id, "rpc_apply_hero_slow_from_authority", slow_percent, duration)

func _upsert_remote_avatar_from_state(peer_id: int, hero_state: Dictionary) -> void:
	var pos_variant: Variant = hero_state.get("pos", null)
	if not (pos_variant is Vector3):
		return
	var pos: Vector3 = pos_variant
	var previous_pos: Vector3 = pos
	if _remote_avatar_target_positions.has(peer_id):
		var prev_pos_variant: Variant = _remote_avatar_target_positions[peer_id]
		if prev_pos_variant is Vector3:
			previous_pos = prev_pos_variant
	var prev_flash_cd: float = _float_from_variant(_remote_last_flash_cd.get(peer_id, 0.0), 0.0)
	var prev_haste_active: bool = _bool_from_variant(_remote_last_haste_active.get(peer_id, false), false)
	var yaw: float = _float_from_variant(hero_state.get("yaw", 0.0), 0.0)
	var model_key: String = _get_remote_model_key(hero_state)
	var avatar: Node3D = _upsert_remote_avatar(peer_id, pos, yaw, model_key)
	if avatar == null:
		return
	if not avatar.is_in_group("hero"):
		avatar.add_to_group("hero")
	avatar.set_meta("network_peer_id", peer_id)
	var scale_variant: Variant = hero_state.get("scale", avatar.scale)
	if scale_variant is Vector3:
		avatar.scale = scale_variant
	_apply_remote_avatar_animation(peer_id, avatar, hero_state)
	if avatar != null and is_instance_valid(avatar):
		var is_dead: bool = _bool_from_variant(hero_state.get("is_dead", false), false)
		avatar.visible = not is_dead
	if sync_skill_effects:
		_apply_remote_skill_effects(peer_id, avatar, hero_state, previous_pos, prev_flash_cd, prev_haste_active)
	_remote_last_flash_cd[peer_id] = _float_from_variant(hero_state.get("flash_cd", prev_flash_cd), prev_flash_cd)
	_remote_last_haste_active[peer_id] = _bool_from_variant(hero_state.get("haste_active", prev_haste_active), prev_haste_active)

func _upsert_remote_avatar(peer_id: int, position: Vector3, yaw: float, model_key: String) -> Node3D:
	if peer_id <= 0:
		return null
	var self_id: int = 0
	if multiplayer.multiplayer_peer != null:
		self_id = multiplayer.get_unique_id()
	if peer_id == self_id:
		return null

	var avatar: Node3D = null
	if _remote_avatars.has(peer_id):
		avatar = _remote_avatars[peer_id] as Node3D
	var current_model_key: String = str(_remote_avatar_model_keys.get(peer_id, ""))
	var needs_recreate: bool = avatar == null or not is_instance_valid(avatar)
	if not needs_recreate and current_model_key != model_key:
		avatar.queue_free()
		avatar = null
		needs_recreate = true
	if needs_recreate:
		avatar = _create_remote_avatar(peer_id, model_key)
		if avatar == null:
			return null
		_remote_avatars[peer_id] = avatar
		_remote_avatar_model_keys[peer_id] = model_key
		_remote_avatar_last_anims.erase(peer_id)
		avatar.global_position = position
		var init_rot: Vector3 = avatar.rotation
		init_rot.x = 0.0
		init_rot.y = yaw
		init_rot.z = 0.0
		avatar.rotation = init_rot

	_remote_avatar_target_positions[peer_id] = position
	_remote_avatar_target_yaws[peer_id] = yaw

	if not needs_recreate:
		var snap_limit: float = maxf(remote_snap_distance, 1.0)
		if avatar.global_position.distance_to(position) >= snap_limit:
			avatar.global_position = position
			var snap_rot: Vector3 = avatar.rotation
			snap_rot.x = 0.0
			snap_rot.y = yaw
			snap_rot.z = 0.0
			avatar.rotation = snap_rot
	return avatar


func _update_remote_avatar_smoothing(delta: float) -> void:
	if delta <= 0.0:
		return
	if _remote_avatars.is_empty():
		return

	var pos_alpha: float = 1.0 - exp(-maxf(remote_position_smooth_speed, 0.01) * delta)
	var rot_alpha: float = 1.0 - exp(-maxf(remote_rotation_smooth_speed, 0.01) * delta)

	for key_variant in _remote_avatars.keys():
		var peer_id: int = int(key_variant)
		var avatar: Node3D = _remote_avatars[peer_id] as Node3D
		if avatar == null or not is_instance_valid(avatar):
			continue

		var target_pos: Vector3 = avatar.global_position
		if _remote_avatar_target_positions.has(peer_id):
			var pos_variant: Variant = _remote_avatar_target_positions[peer_id]
			if pos_variant is Vector3:
				target_pos = pos_variant
		avatar.global_position = avatar.global_position.lerp(target_pos, pos_alpha)

		var target_yaw: float = avatar.rotation.y
		if _remote_avatar_target_yaws.has(peer_id):
			target_yaw = _float_from_variant(_remote_avatar_target_yaws[peer_id], target_yaw)
		var next_rot: Vector3 = avatar.rotation
		next_rot.y = lerp_angle(next_rot.y, target_yaw, rot_alpha)
		avatar.rotation = next_rot

func _create_remote_avatar(peer_id: int, model_key: String) -> Node3D:
	_ensure_remote_players_root()
	if _remote_players_root == null:
		return null

	var avatar: Node3D = null
	var preferred_scene: PackedScene = _resolve_remote_player_scene(model_key)
	if preferred_scene != null:
		var inst: Node = preferred_scene.instantiate()
		avatar = inst as Node3D
	if avatar == null:
		avatar = Node3D.new()
		var marker_mesh: MeshInstance3D = MeshInstance3D.new()
		var capsule: CapsuleMesh = CapsuleMesh.new()
		capsule.radius = 24.0
		capsule.height = 80.0
		marker_mesh.mesh = capsule
		avatar.add_child(marker_mesh)

	avatar.name = "RemotePeer_%d" % peer_id
	avatar.scale = remote_player_scale
	avatar.add_to_group("hero")
	avatar.set_meta("network_peer_id", peer_id)
	_remote_players_root.add_child(avatar)
	_disable_collisions_recursive(avatar)
	return avatar


func _resolve_remote_player_scene(model_key: String) -> PackedScene:
	if model_key == "transformed":
		if remote_transformed_player_scene != null:
			return remote_transformed_player_scene
		if remote_melee_player_scene != null:
			return remote_melee_player_scene
	elif model_key == "ranged":
		if remote_ranged_player_scene != null:
			return remote_ranged_player_scene
	elif model_key == "melee":
		if remote_melee_player_scene != null:
			return remote_melee_player_scene
	if remote_player_scene != null:
		return remote_player_scene
	if remote_melee_player_scene != null:
		return remote_melee_player_scene
	return null


func _get_remote_model_key(hero_state: Dictionary) -> String:
	var is_transformed: bool = _bool_from_variant(hero_state.get("is_transformed", false), false)
	if is_transformed:
		return "transformed"
	var hero_id: int = _int_from_variant(hero_state.get("hero_id", 0), 0)
	if hero_id == 2:
		return "ranged"
	var profile: String = str(hero_state.get("hero_profile", "")).strip_edges().to_lower()
	if profile == "远程" or profile == "ranged":
		return "ranged"
	return "melee"


func _apply_remote_avatar_animation(peer_id: int, avatar: Node3D, hero_state: Dictionary) -> void:
	var anim_player: AnimationPlayer = avatar.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player == null:
		return
	var desired_anim: String = str(hero_state.get("anim_name", ""))
	if desired_anim.is_empty() or not anim_player.has_animation(desired_anim):
		desired_anim = _pick_remote_fallback_animation(anim_player, hero_state)
	if desired_anim.is_empty():
		return

	var should_play: bool = _bool_from_variant(hero_state.get("anim_playing", true), true)
	if not should_play:
		if anim_player.is_playing():
			anim_player.stop()
		return

	var last_anim: String = str(_remote_avatar_last_anims.get(peer_id, ""))
	var need_restart: bool = not anim_player.is_playing() or String(anim_player.current_animation) != desired_anim or last_anim != desired_anim
	if need_restart:
		anim_player.play(desired_anim)
	_remote_avatar_last_anims[peer_id] = desired_anim

	var speed_scale: float = _float_from_variant(hero_state.get("anim_speed", 1.0), 1.0)
	anim_player.speed_scale = clampf(speed_scale, 0.05, 8.0)


func _apply_remote_skill_effects(peer_id: int, avatar: Node3D, hero_state: Dictionary, previous_pos: Vector3, prev_flash_cd: float, prev_haste_active: bool) -> void:
	if avatar == null or not is_instance_valid(avatar):
		return
	if _apply_remote_skill_event_from_state(peer_id, avatar, hero_state, previous_pos):
		return
	var flash_cd: float = _float_from_variant(hero_state.get("flash_cd", prev_flash_cd), prev_flash_cd)
	var just_cast_q: bool = flash_cd > 0.2 and (prev_flash_cd <= 0.05 or flash_cd > prev_flash_cd + 0.35)
	if just_cast_q:
		var model_key: String = _get_remote_model_key(hero_state)
		if model_key == "ranged":
			var cast_yaw: float = _float_from_variant(hero_state.get("yaw", avatar.rotation.y), avatar.rotation.y)
			_spawn_remote_ranged_q_ray(avatar.global_position, cast_yaw)
		else:
			_spawn_remote_flash_pair(previous_pos, avatar.global_position)

	var haste_active: bool = _bool_from_variant(hero_state.get("haste_active", prev_haste_active), prev_haste_active)
	if haste_active and not prev_haste_active and _should_spawn_remote_w_effect(hero_state):
		_spawn_remote_flash_effect(avatar.global_position, remote_haste_effect_scale)


func _should_spawn_remote_w_effect(hero_state: Dictionary, event_state: Dictionary = {}) -> bool:
	var skill_w_id: int = 0
	if not event_state.is_empty():
		skill_w_id = _int_from_variant(event_state.get("skill_id", 0), 0)
	if skill_w_id <= 0:
		skill_w_id = _int_from_variant(hero_state.get("skill_w_id", 0), 0)
	if skill_w_id == SKILL_ID_W_RANGED_SPEED:
		return false
	if skill_w_id <= 0:
		var model_key: String = _get_remote_model_key(hero_state)
		if model_key == "ranged":
			return false
	return true


func _apply_remote_skill_event_from_state(peer_id: int, avatar: Node3D, hero_state: Dictionary, previous_pos: Vector3) -> bool:
	if not hero_state.has("skill_event"):
		return false
	var event_variant: Variant = hero_state["skill_event"]
	if not (event_variant is Dictionary):
		return false
	var event_state: Dictionary = event_variant
	var event_seq: int = _int_from_variant(event_state.get("seq", -1), -1)
	if event_seq < 0:
		return false
	var last_seq: int = _int_from_variant(_remote_last_skill_event_seq.get(peer_id, -1), -1)
	if event_seq <= last_seq:
		return false
	_remote_last_skill_event_seq[peer_id] = event_seq
	var event_from_pos: Vector3 = previous_pos
	var from_variant: Variant = event_state.get("from_pos", null)
	if from_variant is Vector3:
		event_from_pos = from_variant
	var event_to_pos: Vector3 = avatar.global_position
	var to_variant: Variant = event_state.get("to_pos", null)
	if to_variant is Vector3:
		event_to_pos = to_variant
	var event_type: String = str(event_state.get("type", "")).strip_edges().to_lower()
	match event_type:
		"q":
			var model_key: String = _get_remote_model_key(hero_state)
			if model_key == "ranged":
				var cast_yaw: float = _float_from_variant(
					event_state.get("yaw", hero_state.get("yaw", avatar.rotation.y)),
					avatar.rotation.y
				)
				_spawn_remote_ranged_q_ray(event_from_pos, cast_yaw)
			else:
				_spawn_remote_flash_pair(event_from_pos, event_to_pos)
			return true
		"w":
			if not _should_spawn_remote_w_effect(hero_state, event_state):
				return true
			var haste_pos: Vector3 = avatar.global_position
			var haste_pos_variant: Variant = event_state.get("pos", null)
			if haste_pos_variant is Vector3:
				haste_pos = haste_pos_variant
			_spawn_remote_flash_effect(haste_pos, remote_haste_effect_scale)
			return true
		_:
			return false


func _spawn_remote_flash_pair(origin_pos: Vector3, destination_pos: Vector3) -> void:
	_spawn_remote_flash_effect(origin_pos, remote_flash_effect_scale)
	if origin_pos.distance_to(destination_pos) >= 8.0:
		var destination_scale: Vector3 = remote_flash_effect_scale * 0.85
		_spawn_remote_flash_effect(destination_pos, destination_scale)


func _spawn_remote_flash_effect(effect_pos: Vector3, effect_scale: Vector3) -> void:
	if remote_flash_effect_scene == null:
		return
	var effect: Node3D = remote_flash_effect_scene.instantiate() as Node3D
	if effect == null:
		return
	effect.global_position = effect_pos
	effect.scale = effect_scale
	var host: Node = get_parent()
	if host == null:
		host = self
	host.add_child(effect)

	var duration: float = maxf(remote_skill_effect_fallback_lifetime, 0.08)
	var anim_player: AnimationPlayer = effect.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player != null:
		var anim_list: PackedStringArray = anim_player.get_animation_list()
		if anim_list.size() > 0:
			var anim_name: String = String(anim_list[0])
			var anim: Animation = anim_player.get_animation(anim_name)
			if anim != null:
				anim.loop_mode = Animation.LOOP_NONE
				duration = maxf(anim.length, 0.08)
			anim_player.play(anim_name)
	get_tree().create_timer(duration).timeout.connect(effect.queue_free)


func _spawn_remote_ranged_q_ray(ray_start: Vector3, yaw: float) -> void:
	var safe_dir: Vector3 = Vector3(sin(yaw), 0.0, cos(yaw))
	if safe_dir.length() <= 0.001:
		safe_dir = Vector3.FORWARD
	safe_dir = safe_dir.normalized()
	var ray_end: Vector3 = ray_start + safe_dir * maxf(remote_ranged_q_ray_length, 1.0)
	_spawn_remote_ranged_beam(ray_start, ray_end)


func _spawn_remote_ranged_beam(ray_start: Vector3, ray_end: Vector3) -> void:
	var delta: Vector3 = ray_end - ray_start
	if delta.length() <= 0.01:
		return
	var safe_dir: Vector3 = delta.normalized()
	var safe_length: float = maxf(delta.length(), 1.0)
	var safe_width: float = maxf(remote_ranged_q_ray_width, 0.5)
	var safe_thickness: float = maxf(remote_ranged_q_ray_thickness, 0.5)

	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(safe_length, safe_thickness, safe_width)
	var beam: MeshInstance3D = MeshInstance3D.new()
	beam.mesh = mesh
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.12, 0.12, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.2, 1.0)
	mat.emission_energy_multiplier = 2.2
	beam.material_override = mat

	var center: Vector3 = (ray_start + ray_end) * 0.5
	var up_axis: Vector3 = Vector3.UP
	if absf(safe_dir.dot(up_axis)) > 0.99:
		up_axis = Vector3.FORWARD
	var z_axis: Vector3 = safe_dir.cross(up_axis).normalized()
	var y_axis: Vector3 = z_axis.cross(safe_dir).normalized()
	beam.global_transform = Transform3D(Basis(safe_dir, y_axis, z_axis), center)

	var host: Node = get_parent()
	if host == null:
		host = self
	host.add_child(beam)
	get_tree().create_timer(maxf(remote_ranged_q_ray_lifetime, 0.03)).timeout.connect(beam.queue_free)


func _pick_remote_fallback_animation(anim_player: AnimationPlayer, hero_state: Dictionary) -> String:
	if _bool_from_variant(hero_state.get("is_dead", false), false):
		var death_anim: String = _find_anim_by_keywords(anim_player, ["death", "die"])
		if not death_anim.is_empty():
			return death_anim
	if _bool_from_variant(hero_state.get("is_attacking", false), false):
		var attack_anim: String = _find_anim_by_keywords(anim_player, ["attack", "slam", "spell"])
		if not attack_anim.is_empty():
			return attack_anim
	if _bool_from_variant(hero_state.get("is_moving", false), false):
		var move_anim: String = _find_anim_by_keywords(anim_player, ["walk", "run", "move", "locomotion", "go"])
		if not move_anim.is_empty():
			return move_anim
	return _find_anim_by_keywords(anim_player, ["stand", "idle", "wait"])


func _find_anim_by_keywords(anim_player: AnimationPlayer, keywords: Array[String]) -> String:
	var anim_list: PackedStringArray = anim_player.get_animation_list()
	for anim_name_sn in anim_list:
		var anim_name: String = String(anim_name_sn)
		var lower_name: String = anim_name.to_lower()
		for kw in keywords:
			if lower_name.find(kw) >= 0:
				return anim_name
	return ""

func _remove_absent_remote_avatars(valid_remote_ids: Dictionary) -> void:
	var stale_ids: Array[int] = []
	for key_variant in _remote_avatars.keys():
		var peer_id: int = int(key_variant)
		if not valid_remote_ids.has(peer_id):
			stale_ids.append(peer_id)
	for peer_id in stale_ids:
		_remove_remote_avatar(peer_id)

func _remove_remote_avatar(peer_id: int) -> void:
	if not _remote_avatars.has(peer_id):
		return
	var avatar: Node3D = _remote_avatars[peer_id] as Node3D
	_remote_avatars.erase(peer_id)
	_remote_avatar_model_keys.erase(peer_id)
	_remote_avatar_last_anims.erase(peer_id)
	_remote_avatar_target_positions.erase(peer_id)
	_remote_avatar_target_yaws.erase(peer_id)
	_remote_last_flash_cd.erase(peer_id)
	_remote_last_haste_active.erase(peer_id)
	_remote_last_skill_event_seq.erase(peer_id)
	if avatar != null and is_instance_valid(avatar):
		avatar.queue_free()

func _clear_remote_avatars() -> void:
	for key_variant in _remote_avatars.keys():
		var key: int = int(key_variant)
		_remove_remote_avatar(key)
	_remote_avatars.clear()
	_remote_avatar_model_keys.clear()
	_remote_avatar_last_anims.clear()
	_remote_avatar_target_positions.clear()
	_remote_avatar_target_yaws.clear()
	_remote_last_flash_cd.clear()
	_remote_last_haste_active.clear()
	_remote_last_skill_event_seq.clear()

func _reset_local_skill_event_runtime(prime_from_hero: bool) -> void:
	_local_skill_event_seq = 0
	_local_last_skill_event.clear()
	_local_prev_explicit_skill_event_seq = -1
	_local_prev_flash_cd = 0.0
	_local_prev_haste_active = false
	if not prime_from_hero:
		return
	var hero_controller: Node = _get_hero_controller()
	if hero_controller == null:
		return
	_local_prev_flash_cd = _float_from_variant(hero_controller.get("_flash_cooldown"), 0.0)
	_local_prev_haste_active = _bool_from_variant(hero_controller.get("_haste_active"), false)

func _update_local_skill_event_from_state(state: Dictionary) -> void:
	var flash_cd: float = _float_from_variant(state.get("flash_cd", _local_prev_flash_cd), _local_prev_flash_cd)
	var just_cast_q: bool = flash_cd > 0.2 and (_local_prev_flash_cd <= 0.05 or flash_cd > _local_prev_flash_cd + 0.35)
	if just_cast_q:
		_local_skill_event_seq += 1
		_local_last_skill_event = {
			"seq": _local_skill_event_seq,
			"type": "q",
			"skill_id": _int_from_variant(state.get("skill_q_id", 0), 0),
			"t_ms": Time.get_ticks_msec()
		}
	_local_prev_flash_cd = flash_cd

	var haste_active: bool = _bool_from_variant(state.get("haste_active", _local_prev_haste_active), _local_prev_haste_active)
	var just_cast_w: bool = haste_active and not _local_prev_haste_active
	if just_cast_w:
		_local_skill_event_seq += 1
		_local_last_skill_event = {
			"seq": _local_skill_event_seq,
			"type": "w",
			"skill_id": _int_from_variant(state.get("skill_w_id", 0), 0),
			"t_ms": Time.get_ticks_msec()
		}
	_local_prev_haste_active = haste_active

func _disable_collisions_recursive(root: Node) -> void:
	if root == null:
		return
	var collision_obj: CollisionObject3D = root as CollisionObject3D
	if collision_obj != null:
		collision_obj.collision_layer = 0
		collision_obj.collision_mask = 0
	for child in root.get_children():
		var child_node: Node = child as Node
		if child_node != null:
			_disable_collisions_recursive(child_node)

func _ensure_remote_players_root() -> void:
	var existing: Node3D = get_node_or_null(remote_players_root_path) as Node3D
	if existing != null:
		_remote_players_root = existing
		return
	var parent_node: Node3D = get_parent() as Node3D
	if parent_node == null:
		_remote_players_root = null
		return
	var fallback_root: Node3D = Node3D.new()
	fallback_root.name = "NetworkPlayers"
	parent_node.add_child(fallback_root)
	_remote_players_root = fallback_root

func _apply_network_authority_mode() -> void:
	var use_local_authority: bool = true
	if network_mode.strip_edges().to_lower() == "client" and _is_network_running:
		use_local_authority = false

	var boss_controller: Node = _get_boss_controller()
	if boss_controller != null and boss_controller.has_method("set_network_authority"):
		boss_controller.call("set_network_authority", use_local_authority)

	var spawner: Node = _get_tauren_spawner()
	if spawner != null and spawner.has_method("set_network_authority"):
		spawner.call("set_network_authority", use_local_authority)

func _get_hero_controller() -> Node:
	return get_node_or_null(hero_controller_path)

func _get_game_ui() -> Node:
	return get_node_or_null(game_ui_path)

func _get_boss_controller() -> Node:
	return get_node_or_null(boss_controller_path)

func _get_tauren_spawner() -> Node:
	return get_node_or_null(tauren_spawner_path)

func _get_local_hero() -> Node3D:
	var controller: Node = _get_hero_controller()
	if controller != null:
		var hero_variant: Variant = controller.get("_hero")
		if hero_variant is Node3D:
			var hero_node: Node3D = hero_variant as Node3D
			if hero_node != null and is_instance_valid(hero_node):
				return hero_node
	var fallback: Node3D = get_node_or_null(fallback_local_hero_path) as Node3D
	if fallback != null and is_instance_valid(fallback):
		return fallback
	return null

func _pump_steam_callbacks_if_needed() -> void:
	if net_transport_mode.strip_edges().to_lower() != "steam_relay":
		return
	if steam_embed_callbacks:
		return
	var steam: Object = _get_steam_singleton()
	if steam == null:
		return
	if steam.has_method("run_callbacks"):
		steam.call("run_callbacks")

func _get_steam_singleton() -> Object:
	if _steam_singleton != null:
		return _steam_singleton
	if Engine.has_singleton("Steam"):
		_steam_singleton = Engine.get_singleton("Steam")
	return _steam_singleton

func _ensure_steam_initialized() -> Dictionary:
	var steam: Object = _get_steam_singleton()
	if steam == null:
		return {
			"ok": false,
			"err": ERR_UNAVAILABLE,
			"hint": "start_failed(steam_missing_singleton)"
		}

	if _steam_initialized:
		return {
			"ok": true,
			"steam": steam
		}

	var init_ok: bool = false
	var init_status: int = 1
	var init_variant: Variant = null
	if steam.has_method("steamInitEx"):
		init_variant = steam.call("steamInitEx", steam_app_id, steam_embed_callbacks)
	elif steam.has_method("steamInit"):
		init_variant = steam.call("steamInit", steam_app_id, steam_embed_callbacks)
	else:
		return {
			"ok": false,
			"err": ERR_UNAVAILABLE,
			"hint": "start_failed(steam_init_method_missing)"
		}

	if init_variant is Dictionary:
		var init_dict: Dictionary = init_variant
		init_status = _int_from_variant(init_dict.get("status", 1), 1)
		init_ok = init_status == 0
	elif init_variant is bool:
		init_ok = bool(init_variant)
		init_status = 0 if init_ok else 1
	else:
		init_ok = init_variant != null
		init_status = 0 if init_ok else 1

	if not init_ok:
		var init_debug_text: String = str(init_variant)
		if steam.has_method("get_steam_init_result"):
			init_debug_text = str(steam.call("get_steam_init_result"))
		return {
			"ok": false,
			"err": ERR_CANT_OPEN,
			"hint": "start_failed(steam_init status=%d data=%s)" % [init_status, init_debug_text]
		}

	_steam_initialized = true
	return {
		"ok": true,
		"steam": steam
	}

func _resolve_target_steam_host_id(mode: String) -> String:
	var host_id: String = steam_target_host_id.strip_edges()
	if host_id.is_empty() and mode == "host":
		host_id = _resolve_effective_steam_local_id()
	if host_id.is_empty():
		host_id = server_host.strip_edges()
	return host_id

func _parse_steam_id_text(raw_text: String) -> int:
	var text: String = raw_text.strip_edges()
	if text.is_empty():
		return 0
	if not text.is_valid_int():
		return 0
	var parsed: int = text.to_int()
	if parsed <= 0:
		return 0
	return parsed

func _create_steam_relay_peer(mode: String) -> Dictionary:
	var init_result: Dictionary = _ensure_steam_initialized()
	if not bool(init_result.get("ok", false)):
		return init_result
	if not ClassDB.class_exists("SteamMultiplayerPeer"):
		return {
			"ok": false,
			"err": ERR_UNAVAILABLE,
			"hint": "start_failed(steam_relay_peer_class_missing)"
		}

	var peer_obj: Object = ClassDB.instantiate("SteamMultiplayerPeer")
	if peer_obj == null:
		return {
			"ok": false,
			"err": ERR_CANT_CREATE,
			"hint": "start_failed(steam_relay_peer_create_failed)"
		}
	if not (peer_obj is MultiplayerPeer):
		return {
			"ok": false,
			"err": ERR_CANT_CREATE,
			"hint": "start_failed(steam_relay_peer_invalid_type)"
		}
	var steam_peer: MultiplayerPeer = peer_obj as MultiplayerPeer
	var virtual_port: int = maxi(steam_virtual_port, 0)
	var local_id: String = _resolve_effective_steam_local_id()
	var err: int = ERR_CANT_CREATE

	if mode == "host":
		if steam_peer.has_method("create_host"):
			err = _int_from_variant(steam_peer.call("create_host", virtual_port), ERR_CANT_CREATE)
		else:
			err = ERR_UNAVAILABLE
		if err != OK:
			if steam_peer.has_method("close"):
				steam_peer.call("close")
			return {
				"ok": false,
				"err": err,
				"hint": "start_failed(steam_relay_host err=%d)" % err
			}
		return {
			"ok": true,
			"err": OK,
			"peer": steam_peer,
			"hint": "network_started(steam_relay app=%d local=%s host_id=%s vport=%d)" % [
				steam_app_id,
				local_id if not local_id.is_empty() else "-",
				local_id if not local_id.is_empty() else "-",
				virtual_port
			]
		}

	var target_host_id: String = _resolve_target_steam_host_id(mode)
	var target_host_steam_id: int = _parse_steam_id_text(target_host_id)
	if target_host_steam_id <= 0:
		return {
			"ok": false,
			"err": ERR_INVALID_PARAMETER,
			"hint": "start_failed(steam_relay_invalid_host_id=%s)" % target_host_id
		}
	if steam_peer.has_method("create_client"):
		err = _int_from_variant(steam_peer.call("create_client", target_host_steam_id, virtual_port), ERR_CANT_CREATE)
	else:
		err = ERR_UNAVAILABLE
	if err != OK:
		if steam_peer.has_method("close"):
			steam_peer.call("close")
		return {
			"ok": false,
			"err": err,
			"hint": "start_failed(steam_relay_client err=%d host=%s)" % [err, target_host_id]
		}
	return {
		"ok": true,
		"err": OK,
		"peer": steam_peer,
		"hint": "network_started(steam_relay app=%d local=%s host_id=%s vport=%d)" % [
			steam_app_id,
			local_id if not local_id.is_empty() else "-",
			target_host_id,
			virtual_port
		]
	}

func _resolve_effective_steam_local_id() -> String:
	var local_id: String = steam_local_id.strip_edges()
	if not local_id.is_empty():
		return local_id
	var steam: Object = _get_steam_singleton()
	if steam != null and steam.has_method("getSteamID"):
		var steam_id_variant: Variant = steam.call("getSteamID")
		var steam_id_text: String = str(steam_id_variant).strip_edges()
		if not steam_id_text.is_empty() and steam_id_text != "0":
			return steam_id_text
	if multiplayer.multiplayer_peer != null:
		var uid: int = multiplayer.get_unique_id()
		if uid > 0:
			return str(uid)
	return ""

func _refresh_steam_stub_endpoint_map() -> void:
	_steam_stub_endpoint_map = _parse_endpoint_map_csv(steam_stub_endpoint_map_csv)

func _resolve_steam_stub_endpoint(target_host_id: String) -> Dictionary:
	var target: String = target_host_id.strip_edges()
	if not target.is_empty() and _steam_stub_endpoint_map.has(target):
		var mapped_variant: Variant = _steam_stub_endpoint_map[target]
		if mapped_variant is Dictionary:
			return mapped_variant

	var fallback_host: String = steam_stub_default_remote_host.strip_edges()
	if fallback_host.is_empty():
		fallback_host = server_host.strip_edges()
	if fallback_host.is_empty():
		return {}
	var fallback_port: int = maxi(steam_stub_default_remote_port, 1)
	if fallback_port <= 0:
		fallback_port = maxi(server_port, 1)
	return {
		"host": fallback_host,
		"port": fallback_port
	}

func _parse_endpoint_map_csv(raw_text: String) -> Dictionary:
	var output: Dictionary = {}
	var tokens: PackedStringArray = raw_text.split(",", false)
	for token_sn in tokens:
		var token: String = String(token_sn).strip_edges()
		if token.is_empty():
			continue
		var eq_idx: int = token.find("=")
		if eq_idx <= 0:
			continue
		var steam_id: String = token.substr(0, eq_idx).strip_edges()
		var endpoint: String = token.substr(eq_idx + 1).strip_edges()
		if steam_id.is_empty() or endpoint.is_empty():
			continue

		var host: String = endpoint
		var port: int = maxi(steam_stub_default_remote_port, 1)
		var colon_idx: int = endpoint.rfind(":")
		if colon_idx > 0 and colon_idx < endpoint.length() - 1:
			host = endpoint.substr(0, colon_idx).strip_edges()
			var port_text: String = endpoint.substr(colon_idx + 1).strip_edges()
			if port_text.is_valid_int():
				port = maxi(port_text.to_int(), 1)
		host = host.strip_edges()
		if host.is_empty():
			continue
		output[steam_id] = {
			"host": host,
			"port": port
		}
	return output

func _pick_remote_peer_by_mouse_position(mouse_pos: Vector2) -> int:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return 0
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return 0
	var pick_radius: float = maxf(remote_select_screen_radius, 8.0)
	var best_distance: float = pick_radius
	var best_peer: int = 0
	for key_variant in _remote_avatars.keys():
		var peer_id: int = int(key_variant)
		var avatar: Node3D = _remote_avatars[peer_id] as Node3D
		if avatar == null or not is_instance_valid(avatar):
			continue
		if not avatar.visible:
			continue
		var world_pos: Vector3 = avatar.global_position + Vector3(0.0, 90.0, 0.0)
		if camera.is_position_behind(world_pos):
			continue
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		var distance: float = mouse_pos.distance_to(screen_pos)
		if distance <= best_distance:
			best_distance = distance
			best_peer = peer_id
	return best_peer

func _is_click_on_local_hero(mouse_pos: Vector2) -> bool:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return false
	var camera: Camera3D = viewport.get_camera_3d()
	if camera == null:
		return false
	var hero: Node3D = _get_local_hero()
	if hero == null or not is_instance_valid(hero):
		return false
	var world_pos: Vector3 = hero.global_position + Vector3(0.0, 90.0, 0.0)
	if camera.is_position_behind(world_pos):
		return false
	var screen_pos: Vector2 = camera.unproject_position(world_pos)
	return mouse_pos.distance_to(screen_pos) <= maxf(remote_select_screen_radius, 8.0)

func _notify_game_ui_observe_peer(peer_id: int) -> void:
	var ui: Node = _get_game_ui()
	if ui == null:
		return
	if ui.has_method("set_observed_peer"):
		ui.call("set_observed_peer", maxi(peer_id, 0))

func get_ui_self_peer_id() -> int:
	if multiplayer.multiplayer_peer != null:
		return multiplayer.get_unique_id()
	return 0

func get_ui_peer_hero_state(peer_id: int) -> Dictionary:
	if _peer_latest_hero_state.has(peer_id):
		var state_variant: Variant = _peer_latest_hero_state[peer_id]
		if state_variant is Dictionary:
			return state_variant
	return {}

func get_ui_peer_equipment_state(peer_id: int) -> Dictionary:
	if _peer_latest_equipment_state.has(peer_id):
		var state_variant: Variant = _peer_latest_equipment_state[peer_id]
		if state_variant is Dictionary:
			return state_variant
	return {}

func _create_status_overlay() -> void:
	_status_layer = CanvasLayer.new()
	_status_layer.name = "NetStatusLayer"
	_status_layer.layer = 20
	add_child(_status_layer)

	_status_panel = PanelContainer.new()
	_status_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_status_panel.offset_left = 12.0
	_status_panel.offset_top = 12.0
	_status_panel.offset_right = 720.0
	_status_panel.offset_bottom = 130.0
	_status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_layer.add_child(_status_panel)

	var panel_style: StyleBoxFlat = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.06, 0.08, 0.85)
	panel_style.border_color = Color(0.88, 0.72, 0.22, 1.0)
	panel_style.set_border_width_all(1)
	_status_panel.add_theme_stylebox_override("panel", panel_style)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	_status_panel.add_child(margin)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_status_label.add_theme_font_size_override("font_size", 14)
	margin.add_child(_status_label)

func _refresh_status_text() -> void:
	if _status_label == null:
		return
	var mode_raw: String = network_mode.strip_edges().to_lower()
	var mode: String = mode_raw.to_upper()
	var self_id: int = 0
	if multiplayer.multiplayer_peer != null:
		self_id = multiplayer.get_unique_id()
	var room_ids: Array[int] = _get_room_player_ids()
	var peers_count: int = maxi(room_ids.size() - 1, 0)
	var room_ids_text: String = _format_player_ids(room_ids)
	var state_text: String = _get_link_state_text(mode_raw, peers_count)
	var running_text: String = "OFF"
	if _is_network_running:
		running_text = "ON"
	var text: String = "NET[%s] mode=%s state=%s self=%d peers=%d %s:%d\nroom_ids=%s" % [
		running_text,
		mode,
		state_text,
		self_id,
		peers_count,
		server_host,
		server_port,
		room_ids_text
	]
	var transport_mode: String = net_transport_mode.strip_edges().to_lower()
	if transport_mode == "steam_relay":
		var local_id_relay: String = _resolve_effective_steam_local_id()
		var target_relay_id: String = _resolve_target_steam_host_id(mode_raw)
		var steam_ready: String = "off"
		if _steam_initialized:
			steam_ready = "on"
		text += "\ntransport=steam_relay app=%d local=%s host_id=%s vport=%d steam=%s" % [
			steam_app_id,
			local_id_relay if not local_id_relay.is_empty() else "-",
			target_relay_id if not target_relay_id.is_empty() else "-",
			maxi(steam_virtual_port, 0),
			steam_ready
		]
	elif transport_mode == "steam_stub":
		var local_id: String = _resolve_effective_steam_local_id()
		var target_id: String = steam_target_host_id.strip_edges()
		var endpoint: Dictionary = _resolve_steam_stub_endpoint(target_id)
		var endpoint_host: String = str(endpoint.get("host", "")).strip_edges()
		var endpoint_port: int = _int_from_variant(endpoint.get("port", steam_stub_default_remote_port), steam_stub_default_remote_port)
		var endpoint_text: String = "-"
		if not endpoint_host.is_empty() and endpoint_port > 0:
			endpoint_text = "%s:%d" % [endpoint_host, endpoint_port]
		text += "\ntransport=steam_stub app=%d local=%s host_id=%s endpoint=%s" % [
			steam_app_id,
			local_id if not local_id.is_empty() else "-",
			target_id if not target_id.is_empty() else "-",
			endpoint_text
		]
	else:
		text += "\ntransport=enet_direct"
	var hero_summary: String = _build_hero_summary(room_ids)
	if not hero_summary.is_empty():
		text += "\nheroes=%s" % hero_summary
	var equip_summary: String = _build_equipment_summary(room_ids)
	if not equip_summary.is_empty():
		text += "\nequip=%s" % equip_summary
	var active_world_ms: int = int(round(_get_active_world_sync_interval_sec() * 1000.0))
	var hero_sync_ms: int = int(round(maxf(hero_sync_interval_sec, 0.02) * 1000.0))
	var chunk_size_info: int = world_mob_chunk_size
	if adaptive_world_sync_enabled:
		chunk_size_info = _dynamic_world_mob_chunk_size
	text += "\nsync=hero/%dms world/%dms chunk=%d pkt=%dB adaptive=%s" % [
		hero_sync_ms,
		active_world_ms,
		chunk_size_info,
		_last_world_packet_bytes,
		"on" if adaptive_world_sync_enabled else "off"
	]
	if not _status_event_hint.is_empty():
		text += "\nevent=%s" % _status_event_hint
	_set_status_text(text)

func _build_hero_summary(room_ids: Array[int]) -> String:
	var parts: Array[String] = []
	for peer_id in room_ids:
		if not _peer_latest_hero_state.has(peer_id):
			continue
		var state_variant: Variant = _peer_latest_hero_state[peer_id]
		if not (state_variant is Dictionary):
			continue
		var state: Dictionary = state_variant
		var hp: int = _int_from_variant(state.get("hp", 0), 0)
		var max_hp: int = _int_from_variant(state.get("max_hp", 0), 0)
		var mana: int = _int_from_variant(state.get("mana", 0), 0)
		var max_mana: int = _int_from_variant(state.get("max_mana", 0), 0)
		var profile: String = str(state.get("hero_profile", "-"))
		parts.append("P%d hp=%d/%d mp=%d/%d profile=%s" % [peer_id, hp, max_hp, mana, max_mana, profile])
	return " | ".join(parts)

func _build_equipment_summary(room_ids: Array[int]) -> String:
	var parts: Array[String] = []
	for peer_id in room_ids:
		if not _peer_latest_equipment_state.has(peer_id):
			continue
		var state_variant: Variant = _peer_latest_equipment_state[peer_id]
		if not (state_variant is Dictionary):
			continue
		var state: Dictionary = state_variant
		var inv_text: String = "[]"
		var inv_variant: Variant = state.get("inventory", [])
		if inv_variant is Array:
			inv_text = _format_int_array(inv_variant)
		var gold: int = _int_from_variant(state.get("gold", -1), -1)
		var shop_level: int = _int_from_variant(state.get("shop_level", -1), -1)
		parts.append("P%d inv=%s gold=%d shop=%d" % [peer_id, inv_text, gold, shop_level])
	return " | ".join(parts)

func _set_status_text(text: String) -> void:
	_last_status_text = text
	if _status_label != null:
		_status_label.text = text

func _get_room_player_ids() -> Array[int]:
	var ids: Array[int] = []
	if not _is_network_running:
		return ids
	if multiplayer.multiplayer_peer == null:
		return ids
	var self_id: int = multiplayer.get_unique_id()
	if self_id > 0:
		ids.append(self_id)
	for peer_variant in multiplayer.get_peers():
		var peer_id: int = int(peer_variant)
		if peer_id <= 0:
			continue
		if peer_id == self_id:
			continue
		ids.append(peer_id)
	ids.sort()
	return ids

func _format_player_ids(ids: Array[int]) -> String:
	if ids.is_empty():
		return "[]"
	var parts: Array[String] = []
	for player_id in ids:
		parts.append(str(player_id))
	return "[" + ",".join(parts) + "]"

func _format_int_array(values: Array) -> String:
	if values.is_empty():
		return "[]"
	var parts: Array[String] = []
	for value in values:
		parts.append(str(int(value)))
	return "[" + ",".join(parts) + "]"

func _get_link_state_text(mode: String, peers_count: int) -> String:
	if mode == "offline":
		return "OFFLINE"
	if not _is_network_running:
		return "STOPPED"
	if mode == "host":
		if peers_count > 0:
			return "LISTENING_CONNECTED"
		return "LISTENING_WAITING"
	if mode == "client":
		if peers_count > 0:
			return "CONNECTED"
		return "CONNECTING"
	return "RUNNING"

func _normalize_transport_mode(raw_mode: String) -> String:
	var mode: String = raw_mode.strip_edges().to_lower()
	match mode:
		"enet", "enet_direct", "enet-direct":
			return "enet_direct"
		"sdr", "steam_relay", "steam-relay", "relay":
			return "steam_relay"
		"steam_stub", "steam-stub":
			return "steam_stub"
		_:
			return mode

func _set_transport_mode(raw_mode: String) -> void:
	var normalized: String = _normalize_transport_mode(raw_mode)
	match normalized:
		"enet_direct", "steam_stub", "steam_relay":
			net_transport_mode = normalized
		_:
			pass

func _apply_transport_config_overrides() -> void:
	if not transport_config_enabled:
		return
	var cfg_path: String = transport_config_path.strip_edges()
	if cfg_path.is_empty():
		return
	var cfg: ConfigFile = ConfigFile.new()
	var err: int = cfg.load(cfg_path)
	if err != OK:
		return

	var transport_variant: Variant = cfg.get_value("network", "transport", null)
	if transport_variant != null:
		_set_transport_mode(str(transport_variant))

	var app_id_variant: Variant = cfg.get_value("network", "steam_app_id", null)
	if app_id_variant != null:
		steam_app_id = _int_from_variant(app_id_variant, steam_app_id)

	var embed_variant: Variant = cfg.get_value("network", "steam_embed_callbacks", null)
	if embed_variant != null:
		steam_embed_callbacks = _bool_from_variant(embed_variant, steam_embed_callbacks)

	var vport_variant: Variant = cfg.get_value("network", "steam_virtual_port", null)
	if vport_variant != null:
		steam_virtual_port = _int_from_variant(vport_variant, steam_virtual_port)

	var local_id_variant: Variant = cfg.get_value("network", "steam_local_id", null)
	if local_id_variant != null:
		steam_local_id = str(local_id_variant).strip_edges()

	var host_id_variant: Variant = cfg.get_value("network", "steam_host_id", null)
	if host_id_variant != null:
		steam_target_host_id = str(host_id_variant).strip_edges()

func _apply_cmdline_overrides() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for raw_arg in args:
		var arg: String = raw_arg.strip_edges()
		if arg.is_empty():
			continue
		var key: String = arg
		var value: String = "true"
		var eq_idx: int = arg.find("=")
		if eq_idx >= 0:
			key = arg.substr(0, eq_idx)
			value = arg.substr(eq_idx + 1)
		key = key.strip_edges().to_lower()
		if key.begins_with("--"):
			key = key.substr(2)
		value = value.strip_edges()
		_apply_cmdline_kv(key, value)

func _apply_cmdline_kv(key: String, value: String) -> void:
	match key:
		"net", "network", "mode", "net-mode", "net_mode":
			network_mode = value.strip_edges().to_lower()
		"transport", "net-transport", "net_transport":
			_set_transport_mode(value)
		"host", "server", "server-host", "server_host":
			server_host = value
		"port", "server-port", "server_port":
			server_port = _parse_int_or_default(value, server_port)
		"steam-app-id", "steam_app_id", "appid", "app_id":
			steam_app_id = _parse_int_or_default(value, steam_app_id)
		"steam-embed-callbacks", "steam_embed_callbacks":
			steam_embed_callbacks = _parse_bool_or_default(value, steam_embed_callbacks)
		"steam-virtual-port", "steam_virtual_port", "virtual-port", "virtual_port":
			steam_virtual_port = _parse_int_or_default(value, steam_virtual_port)
		"steam-id", "steam_id", "local-steam-id", "local_steam_id":
			steam_local_id = value.strip_edges()
		"steam-host-id", "steam_host_id", "target-host-id", "target_host_id":
			steam_target_host_id = value.strip_edges()
		"steam-listen-port", "steam_listen_port", "listen-port", "listen_port":
			steam_stub_listen_port = _parse_int_or_default(value, steam_stub_listen_port)
		"steam-remote-host", "steam_remote_host", "remote-host", "remote_host":
			steam_stub_default_remote_host = value.strip_edges()
		"steam-remote-port", "steam_remote_port", "remote-port", "remote_port":
			steam_stub_default_remote_port = _parse_int_or_default(value, steam_stub_default_remote_port)
		"steam-endpoint-map", "steam_endpoint_map", "endpoint-map", "endpoint_map":
			steam_stub_endpoint_map_csv = value
		"auto-connect", "auto_connect", "autostart", "auto_start_network":
			auto_start_network = _parse_bool_or_default(value, auto_start_network)
		_:
			pass

func _parse_int_or_default(raw: String, fallback: int) -> int:
	var text: String = raw.strip_edges()
	if text.is_empty():
		return fallback
	if not text.is_valid_int():
		return fallback
	return text.to_int()

func _parse_bool_or_default(raw: String, fallback: bool) -> bool:
	var text: String = raw.strip_edges().to_lower()
	if text.is_empty():
		return fallback
	if text == "1" or text == "true" or text == "yes" or text == "on":
		return true
	if text == "0" or text == "false" or text == "no" or text == "off":
		return false
	return fallback

func _int_from_variant(value: Variant, fallback: int) -> int:
	if value == null:
		return fallback
	if value is int:
		return value
	if value is float:
		return int(round(value))
	if value is String and value.is_valid_int():
		return value.to_int()
	return fallback

func _float_from_variant(value: Variant, fallback: float) -> float:
	if value == null:
		return fallback
	if value is float:
		return value
	if value is int:
		return float(value)
	if value is String and value.is_valid_float():
		return value.to_float()
	return fallback

func _bool_from_variant(value: Variant, fallback: bool) -> bool:
	if value == null:
		return fallback
	if value is bool:
		return value
	if value is int:
		return value != 0
	if value is float:
		return absf(value) > 0.0001
	if value is String:
		var lower: String = value.strip_edges().to_lower()
		if lower == "true" or lower == "1" or lower == "yes" or lower == "on":
			return true
		if lower == "false" or lower == "0" or lower == "no" or lower == "off":
			return false
	return fallback
