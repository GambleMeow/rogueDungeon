extends Node

@export var backend_base_url: String = "http://127.0.0.1:8080/v1"
@export var backend_access_token: String = ""
@export var enable_backend_session: bool = true
@export var run_id: String = ""
@export var local_steam_id: String = ""
@export var auto_start_on_ready: bool = false
@export_enum("simulated", "steam_stub") var p2p_transport_mode: String = "simulated"
@export var simulated_connect_delay_sec: float = 0.15
@export var simulated_fail_hosts_csv: String = ""
@export var steam_stub_listen_port: int = 19090
@export var steam_stub_remote_host: String = ""
@export var steam_stub_remote_port: int = 19090
@export var steam_stub_endpoint_map_csv: String = ""
@export var p2p_only_manual_host_steam_id: String = ""
@export var auto_switch_p2p_on_host_change: bool = true
@export var auto_return_to_lobby_on_failure: bool = true

const LOCAL_RUN_ID := "local_test_001"
const LOCAL_HOST_STEAM_ID := "76561198000000001"
const LOCAL_CLIENT_STEAM_ID := "76561198000000002"
const LOCAL_ENDPOINT_MAP := "76561198000000001=127.0.0.1:19090,76561198000000002=127.0.0.1:19091"

const BACKEND_API_SCRIPT_PATH := "res://scripts/backend_api.gd"
const HOST_MIGRATION_CONTROLLER_SCRIPT_PATH := "res://scripts/host_migration_controller.gd"
const P2P_SESSION_ADAPTER_SCRIPT_PATH := "res://scripts/p2p_session_adapter.gd"
const LOBBY_FLOW_CONTROLLER_SCRIPT_PATH := "res://scripts/lobby_flow_controller.gd"
const STEAM_P2P_TRANSPORT_SCRIPT_PATH := "res://scripts/steam_p2p_transport.gd"
const SIMULATED_P2P_TRANSPORT_SCRIPT_PATH := "res://scripts/simulated_p2p_transport.gd"

# Keep local enum values in sync with host_migration_controller.gd NetState.
const NET_STATE_RUNNING := 0
const NET_STATE_MIGRATION_WAIT := 1
const NET_STATE_MIGRATION_CANDIDATE := 2
const NET_STATE_MIGRATION_FOLLOWER := 3
const NET_STATE_ABORTED := 4

var _api = null
var _migration = null
var _p2p = null
var _lobby = null
var _host_switch_in_flight: bool = false
var _pending_host_target: String = ""

var _base_url_input: LineEdit
var _token_input: LineEdit
var _backend_enabled_checkbox: CheckBox
var _run_id_input: LineEdit
var _steam_id_input: LineEdit
var _manual_host_input: LineEdit
var _manual_connect_button: Button
var _manual_disconnect_button: Button
var _sim_fail_hosts_input: LineEdit
var _sim_connect_delay_input: LineEdit
var _steam_listen_port_input: LineEdit
var _steam_remote_host_input: LineEdit
var _steam_remote_port_input: LineEdit
var _steam_endpoint_map_input: LineEdit
var _transport_mode_select: OptionButton
var _auto_switch_checkbox: CheckBox
var _auto_return_checkbox: CheckBox
var _state_label: Label
var _host_label: Label
var _countdown_label: Label
var _error_label: Label
var _p2p_role_label: Label
var _p2p_conn_label: Label
var _p2p_transport_label: Label
var _lobby_state_label: Label
var _log_output: RichTextLabel
var _start_button: Button
var _stop_button: Button

func _ready() -> void:
	_apply_cmdline_overrides()
	_build_debug_ui()
	_seed_inputs()
	_set_status("IDLE", Color(0.7, 0.7, 0.7))
	_set_host_text("-")
	_set_countdown_text("-")
	_set_error_text("-")
	_set_p2p_role_text("-")
	_set_p2p_connection_text("DISCONNECTED")
	_set_p2p_transport_text("-")
	_set_lobby_state_text("IDLE")

	if auto_start_on_ready and not run_id.is_empty() and not local_steam_id.is_empty():
		_start_integration()

func _exit_tree() -> void:
	_stop_integration()

func _build_debug_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 16)
	panel.size = Vector2(720, 520)
	layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Host Migration V1 Integration Panel"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	_base_url_input = _add_labeled_line_edit(root, "Base URL")
	_token_input = _add_labeled_line_edit(root, "Access Token")
	_token_input.secret = true
	_backend_enabled_checkbox = CheckBox.new()
	_backend_enabled_checkbox.text = "Enable Backend Session Polling"
	_backend_enabled_checkbox.button_pressed = enable_backend_session
	_backend_enabled_checkbox.toggled.connect(_on_backend_enabled_toggled)
	root.add_child(_backend_enabled_checkbox)
	_run_id_input = _add_labeled_line_edit(root, "Run ID")
	_steam_id_input = _add_labeled_line_edit(root, "Local Steam ID")
	_manual_host_input = _add_labeled_line_edit(root, "P2P Only Manual Host")
	_transport_mode_select = _add_labeled_option_button(root, "P2P Transport")
	_transport_mode_select.add_item("simulated")
	_transport_mode_select.add_item("steam_stub")
	_transport_mode_select.item_selected.connect(_on_transport_mode_selected)
	_sim_connect_delay_input = _add_labeled_line_edit(root, "Sim Connect Delay (sec)")
	_sim_fail_hosts_input = _add_labeled_line_edit(root, "Sim Fail Hosts (CSV)")
	_steam_listen_port_input = _add_labeled_line_edit(root, "Stub Listen Port")
	_steam_remote_host_input = _add_labeled_line_edit(root, "Stub Remote Host")
	_steam_remote_port_input = _add_labeled_line_edit(root, "Stub Remote Port")
	_steam_endpoint_map_input = _add_labeled_line_edit(root, "Stub Endpoint Map")

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	root.add_child(button_row)

	_start_button = Button.new()
	_start_button.text = "Start"
	_start_button.pressed.connect(_on_start_pressed)
	button_row.add_child(_start_button)

	_stop_button = Button.new()
	_stop_button.text = "Stop"
	_stop_button.disabled = true
	_stop_button.pressed.connect(_on_stop_pressed)
	button_row.add_child(_stop_button)

	var manual_row := HBoxContainer.new()
	manual_row.add_theme_constant_override("separation", 8)
	root.add_child(manual_row)

	_manual_connect_button = Button.new()
	_manual_connect_button.text = "Manual Connect"
	_manual_connect_button.disabled = true
	_manual_connect_button.pressed.connect(_on_manual_connect_pressed)
	manual_row.add_child(_manual_connect_button)

	_manual_disconnect_button = Button.new()
	_manual_disconnect_button.text = "Manual Disconnect"
	_manual_disconnect_button.disabled = true
	_manual_disconnect_button.pressed.connect(_on_manual_disconnect_pressed)
	manual_row.add_child(_manual_disconnect_button)

	_auto_return_checkbox = CheckBox.new()
	_auto_return_checkbox.text = "Auto Return To Lobby On Failure"
	_auto_return_checkbox.button_pressed = auto_return_to_lobby_on_failure
	_auto_return_checkbox.toggled.connect(_on_auto_return_toggled)
	root.add_child(_auto_return_checkbox)

	_auto_switch_checkbox = CheckBox.new()
	_auto_switch_checkbox.text = "Auto Switch P2P On Host Change"
	_auto_switch_checkbox.button_pressed = auto_switch_p2p_on_host_change
	_auto_switch_checkbox.toggled.connect(_on_auto_switch_toggled)
	root.add_child(_auto_switch_checkbox)

	_state_label = _add_labeled_value(root, "State")
	_host_label = _add_labeled_value(root, "Current Host")
	_countdown_label = _add_labeled_value(root, "Migration Countdown")
	_error_label = _add_labeled_value(root, "Last Error")
	_p2p_role_label = _add_labeled_value(root, "P2P Role")
	_p2p_conn_label = _add_labeled_value(root, "P2P Connection")
	_p2p_transport_label = _add_labeled_value(root, "P2P Transport")
	_lobby_state_label = _add_labeled_value(root, "Lobby State")

	var log_title := Label.new()
	log_title.text = "Event Log"
	root.add_child(log_title)

	_log_output = RichTextLabel.new()
	_log_output.custom_minimum_size = Vector2(0, 200)
	_log_output.bbcode_enabled = false
	_log_output.fit_content = false
	root.add_child(_log_output)

func _add_labeled_line_edit(parent: Control, label_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)

	var input := LineEdit.new()
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return input

func _add_labeled_option_button(parent: Control, label_text: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(170, 0)
	row.add_child(label)

	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option

func _add_labeled_value(parent: Control, label_text: String) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var title := Label.new()
	title.text = label_text
	title.custom_minimum_size = Vector2(170, 0)
	row.add_child(title)

	var value := Label.new()
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)
	return value

func _seed_inputs() -> void:
	_base_url_input.text = backend_base_url
	_token_input.text = backend_access_token
	_backend_enabled_checkbox.button_pressed = enable_backend_session
	_run_id_input.text = run_id
	_steam_id_input.text = local_steam_id
	_manual_host_input.text = p2p_only_manual_host_steam_id
	_sim_connect_delay_input.text = str(simulated_connect_delay_sec)
	_sim_fail_hosts_input.text = simulated_fail_hosts_csv
	_steam_listen_port_input.text = str(steam_stub_listen_port)
	_steam_remote_host_input.text = steam_stub_remote_host
	_steam_remote_port_input.text = str(steam_stub_remote_port)
	_steam_endpoint_map_input.text = steam_stub_endpoint_map_csv
	_select_transport_mode_in_ui(p2p_transport_mode)
	_auto_return_checkbox.button_pressed = auto_return_to_lobby_on_failure
	_auto_switch_checkbox.button_pressed = auto_switch_p2p_on_host_change
	_update_transport_dependent_inputs()
	_update_backend_dependent_inputs()

func _apply_cmdline_overrides() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		return
	for raw_arg in args:
		var arg := raw_arg.strip_edges()
		if arg.is_empty():
			continue
		var key := arg
		var value := "true"
		var eq_idx := arg.find("=")
		if eq_idx >= 0:
			key = arg.substr(0, eq_idx)
			value = arg.substr(eq_idx + 1)
		key = key.strip_edges().to_lower()
		if key.begins_with("--"):
			key = key.substr(2)
		_apply_cmdline_pair(key, value.strip_edges())

func _apply_cmdline_pair(key: String, value: String) -> void:
	match key:
		"instance", "profile":
			_apply_local_instance_profile(value)
		"run-id", "run_id":
			run_id = value
		"steam-id", "steam_id":
			local_steam_id = value
		"backend", "enable-backend", "enable_backend":
			enable_backend_session = _parse_bool_or_default(value, enable_backend_session)
		"auto-start", "auto_start":
			auto_start_on_ready = _parse_bool_or_default(value, auto_start_on_ready)
		"transport", "p2p-transport", "p2p_transport":
			p2p_transport_mode = value
		"listen-port", "listen_port":
			steam_stub_listen_port = _parse_int_or_default(value, steam_stub_listen_port)
		"remote-host", "remote_host":
			steam_stub_remote_host = value
		"remote-port", "remote_port":
			steam_stub_remote_port = _parse_int_or_default(value, steam_stub_remote_port)
		"endpoint-map", "endpoint_map":
			steam_stub_endpoint_map_csv = value
		"manual-host", "manual_host":
			p2p_only_manual_host_steam_id = value
		"sim-fail-hosts", "sim_fail_hosts":
			simulated_fail_hosts_csv = value
		"sim-delay", "sim_delay":
			simulated_connect_delay_sec = _parse_float_or_default(value, simulated_connect_delay_sec)

func _apply_local_instance_profile(profile_raw: String) -> void:
	var profile := profile_raw.strip_edges().to_lower()
	if profile == "host" or profile == "a" or profile == "1":
		enable_backend_session = false
		auto_start_on_ready = true
		p2p_transport_mode = "steam_stub"
		run_id = LOCAL_RUN_ID
		local_steam_id = LOCAL_HOST_STEAM_ID
		p2p_only_manual_host_steam_id = LOCAL_HOST_STEAM_ID
		steam_stub_listen_port = 19090
		steam_stub_remote_host = "127.0.0.1"
		steam_stub_remote_port = 19090
		steam_stub_endpoint_map_csv = LOCAL_ENDPOINT_MAP
		return

	if profile == "client" or profile == "b" or profile == "2":
		enable_backend_session = false
		auto_start_on_ready = true
		p2p_transport_mode = "steam_stub"
		run_id = LOCAL_RUN_ID
		local_steam_id = LOCAL_CLIENT_STEAM_ID
		p2p_only_manual_host_steam_id = LOCAL_HOST_STEAM_ID
		steam_stub_listen_port = 19091
		steam_stub_remote_host = "127.0.0.1"
		steam_stub_remote_port = 19090
		steam_stub_endpoint_map_csv = LOCAL_ENDPOINT_MAP

func _on_start_pressed() -> void:
	_start_integration()

func _on_stop_pressed() -> void:
	_stop_integration()

func _on_manual_connect_pressed() -> void:
	if _p2p == null:
		_set_error_text("P2P_NOT_STARTED")
		return
	var target := _manual_host_input.text.strip_edges()
	if target.is_empty():
		_set_error_text("MANUAL_HOST_EMPTY")
		return
	_enqueue_host_switch(target)

func _on_manual_disconnect_pressed() -> void:
	if _p2p == null:
		return
	_p2p.disconnect_session("MANUAL_DISCONNECT")
	_set_p2p_role_text("none")
	_set_p2p_connection_text(_p2p.get_connection_state_text())

func _on_auto_return_toggled(enabled: bool) -> void:
	auto_return_to_lobby_on_failure = enabled

func _on_auto_switch_toggled(enabled: bool) -> void:
	auto_switch_p2p_on_host_change = enabled

func _on_backend_enabled_toggled(enabled: bool) -> void:
	enable_backend_session = enabled
	_update_backend_dependent_inputs()

func _on_transport_mode_selected(index: int) -> void:
	p2p_transport_mode = _transport_mode_select.get_item_text(index)
	_update_transport_dependent_inputs()

func _select_transport_mode_in_ui(mode: String) -> void:
	var target := mode.strip_edges()
	for idx in range(_transport_mode_select.item_count):
		if _transport_mode_select.get_item_text(idx) == target:
			_transport_mode_select.select(idx)
			return
	_transport_mode_select.select(0)
	p2p_transport_mode = _transport_mode_select.get_item_text(0)

func _update_transport_dependent_inputs() -> void:
	var is_simulated := p2p_transport_mode == "simulated"
	var is_steam_stub := p2p_transport_mode == "steam_stub"
	_sim_connect_delay_input.editable = is_simulated
	_sim_fail_hosts_input.editable = is_simulated
	_steam_listen_port_input.editable = is_steam_stub
	_steam_remote_host_input.editable = is_steam_stub
	_steam_remote_port_input.editable = is_steam_stub
	_steam_endpoint_map_input.editable = is_steam_stub

func _update_backend_dependent_inputs() -> void:
	var running := _start_button != null and _start_button.disabled
	var backend_enabled := enable_backend_session
	_base_url_input.editable = backend_enabled and not running
	_token_input.editable = backend_enabled and not running
	_backend_enabled_checkbox.disabled = running

	var manual_controls_enabled := (not backend_enabled) and running and _p2p != null
	_manual_host_input.editable = not backend_enabled
	_manual_connect_button.disabled = not manual_controls_enabled
	_manual_disconnect_button.disabled = not manual_controls_enabled

func _start_integration() -> void:
	_stop_integration()

	backend_base_url = _base_url_input.text.strip_edges()
	backend_access_token = _token_input.text.strip_edges()
	enable_backend_session = _backend_enabled_checkbox.button_pressed
	run_id = _run_id_input.text.strip_edges()
	local_steam_id = _steam_id_input.text.strip_edges()
	p2p_only_manual_host_steam_id = _manual_host_input.text.strip_edges()
	var selected_transport_idx := _transport_mode_select.selected
	if selected_transport_idx < 0:
		selected_transport_idx = 0
	p2p_transport_mode = _transport_mode_select.get_item_text(selected_transport_idx)
	simulated_fail_hosts_csv = _sim_fail_hosts_input.text.strip_edges()
	simulated_connect_delay_sec = _parse_float_or_default(_sim_connect_delay_input.text, 0.15)
	steam_stub_listen_port = _parse_int_or_default(_steam_listen_port_input.text, 19090)
	steam_stub_remote_host = _steam_remote_host_input.text.strip_edges()
	steam_stub_remote_port = _parse_int_or_default(_steam_remote_port_input.text, 19090)
	steam_stub_endpoint_map_csv = _steam_endpoint_map_input.text.strip_edges()

	if run_id.is_empty() or local_steam_id.is_empty():
		_set_error_text("run_id / local_steam_id cannot be empty")
		_append_log("Start rejected: required input is empty.")
		return
	if enable_backend_session and (backend_base_url.is_empty() or backend_access_token.is_empty()):
		_set_error_text("base_url / token required when backend mode is enabled")
		_append_log("Start rejected: backend mode requires base_url and token.")
		return

	if enable_backend_session:
		_api = _new_script_instance(BACKEND_API_SCRIPT_PATH)
		if _api == null:
			_set_error_text("BACKEND_API_SCRIPT_MISSING")
			_append_log("Start rejected: backend api script missing.")
			return
		_api.base_url = backend_base_url
		_api.access_token = backend_access_token
		add_child(_api)

	var transport = _create_p2p_transport()
	if transport == null:
		if _api != null:
			_api.queue_free()
			_api = null
		_set_error_text("P2P_TRANSPORT_CREATE_FAILED")
		_append_log("Start rejected: transport create failed.")
		return

	_p2p = _new_script_instance(P2P_SESSION_ADAPTER_SCRIPT_PATH)
	if _p2p == null:
		if _api != null:
			_api.queue_free()
			_api = null
		_set_error_text("P2P_ADAPTER_SCRIPT_MISSING")
		_append_log("Start rejected: p2p adapter script missing.")
		return
	add_child(_p2p)
	_p2p.setup(run_id, local_steam_id, transport)
	_p2p.role_changed.connect(_on_p2p_role_changed)
	_p2p.connection_state_changed.connect(_on_p2p_connection_state_changed)
	_p2p.connection_failed.connect(_on_p2p_connection_failed)
	_p2p.transport_event.connect(_on_p2p_transport_event)

	_lobby = _new_script_instance(LOBBY_FLOW_CONTROLLER_SCRIPT_PATH)
	if _lobby == null:
		_p2p.queue_free()
		_p2p = null
		if _api != null:
			_api.queue_free()
			_api = null
		_set_error_text("LOBBY_SCRIPT_MISSING")
		_append_log("Start rejected: lobby script missing.")
		return
	add_child(_lobby)
	_lobby.lobby_state_changed.connect(_on_lobby_state_changed)
	_lobby.lobby_event.connect(_on_lobby_event)
	_lobby.enter_match(run_id)

	_host_switch_in_flight = false
	_pending_host_target = ""

	if enable_backend_session:
		_migration = _new_script_instance(HOST_MIGRATION_CONTROLLER_SCRIPT_PATH)
		if _migration == null:
			_stop_integration()
			_set_error_text("MIGRATION_SCRIPT_MISSING")
			_append_log("Start rejected: migration script missing.")
			return
		add_child(_migration)
		_migration.setup(_api, run_id, local_steam_id)
		_migration.state_changed.connect(_on_state_changed)
		_migration.countdown_updated.connect(_on_countdown_updated)
		_migration.host_changed.connect(_on_host_changed)
		_migration.migration_failed.connect(_on_migration_failed)
		_migration.session_updated.connect(_on_session_updated)
		_migration.start()
	else:
		_set_status("P2P_ONLY", Color(0.45, 0.75, 1.0))
		_set_countdown_text("-")
		if not p2p_only_manual_host_steam_id.is_empty():
			_enqueue_host_switch(p2p_only_manual_host_steam_id)
		else:
			_append_log("P2P only mode ready. Use Manual Connect button.")

	_set_error_text("-")
	_set_p2p_role_text("none")
	_set_p2p_connection_text("DISCONNECTED")
	_set_p2p_transport_text(_p2p.get_transport_name())
	_append_log(
		"Integration started mode=%s run_id=%s local_steam_id=%s" % [
			"backend" if enable_backend_session else "p2p_only",
			run_id,
			local_steam_id
		]
	)
	_start_button.disabled = true
	_stop_button.disabled = false
	_auto_return_checkbox.disabled = true
	_auto_switch_checkbox.disabled = true
	_transport_mode_select.disabled = true
	_sim_connect_delay_input.editable = false
	_sim_fail_hosts_input.editable = false
	_steam_listen_port_input.editable = false
	_steam_remote_host_input.editable = false
	_steam_remote_port_input.editable = false
	_steam_endpoint_map_input.editable = false
	_update_backend_dependent_inputs()

func _stop_integration() -> void:
	if _migration != null:
		_migration.stop()
		_migration.queue_free()
		_migration = null
	if _p2p != null:
		_p2p.disconnect_session("MANUAL_STOP")
		_p2p.queue_free()
		_p2p = null
	if _lobby != null:
		_lobby.reset_to_idle()
		_lobby.queue_free()
		_lobby = null
	if _api != null:
		_api.queue_free()
		_api = null
	_host_switch_in_flight = false
	_pending_host_target = ""
	_set_p2p_role_text("-")
	_set_p2p_connection_text("DISCONNECTED")
	_set_p2p_transport_text("-")
	_set_lobby_state_text("IDLE")
	_start_button.disabled = false
	_stop_button.disabled = true
	_auto_return_checkbox.disabled = false
	_auto_switch_checkbox.disabled = false
	_transport_mode_select.disabled = false
	_update_transport_dependent_inputs()
	_update_backend_dependent_inputs()

func _on_state_changed(next_state: int) -> void:
	var text := _state_to_text(next_state)
	var color := Color(0.7, 0.7, 0.7)
	match next_state:
		NET_STATE_RUNNING:
			color = Color(0.2, 0.8, 0.2)
		NET_STATE_MIGRATION_WAIT:
			color = Color(0.95, 0.85, 0.2)
		NET_STATE_MIGRATION_CANDIDATE:
			color = Color(0.95, 0.6, 0.2)
		NET_STATE_MIGRATION_FOLLOWER:
			color = Color(0.7, 0.7, 1.0)
		NET_STATE_ABORTED:
			color = Color(1.0, 0.3, 0.3)
	_set_status(text, color)
	_append_log("state => %s" % text)

func _on_countdown_updated(seconds_left: int) -> void:
	_set_countdown_text("%ss" % seconds_left)

func _on_host_changed(new_host_steam_id: String) -> void:
	_set_host_text(new_host_steam_id)
	_append_log("currentHostSteamId => %s" % new_host_steam_id)
	if auto_switch_p2p_on_host_change:
		_enqueue_host_switch(new_host_steam_id)

func _on_migration_failed(reason_code: String) -> void:
	_set_error_text(reason_code)
	_append_log("migration_failed => %s" % reason_code)
	if auto_return_to_lobby_on_failure:
		_begin_return_to_lobby(reason_code)

func _on_session_updated(session: Dictionary) -> void:
	if session.has("currentHostSteamId"):
		var host := str(session.get("currentHostSteamId", ""))
		if not host.is_empty():
			_set_host_text(host)

func _enqueue_host_switch(target_host_steam_id: String) -> void:
	var target := target_host_steam_id.strip_edges()
	if target.is_empty():
		return
	_pending_host_target = target
	if _host_switch_in_flight:
		return
	call_deferred("_drain_host_switch_queue")

func _drain_host_switch_queue() -> void:
	if _host_switch_in_flight or _p2p == null:
		return
	_host_switch_in_flight = true
	while not _pending_host_target.is_empty() and _p2p != null:
		var target := _pending_host_target
		_pending_host_target = ""
		_append_log("switch p2p target => %s" % target)
		var result = await _p2p.switch_host(target)
		if not bool(result.get("ok", false)):
			var code := str(result.get("code", "P2P_SWITCH_FAILED"))
			_set_error_text(code)
			_append_log("p2p switch failed => %s" % code)
			if auto_return_to_lobby_on_failure:
				_begin_return_to_lobby("P2P_SWITCH_FAILED")
			break
		var role := str(result.get("role", "unknown"))
		_set_p2p_role_text(role)
		_append_log("p2p switch success role=%s host=%s" % [role, target])
	_host_switch_in_flight = false

func _begin_return_to_lobby(reason_code: String) -> void:
	if _lobby == null:
		return
	_lobby.begin_return_to_lobby(reason_code)

func _on_p2p_role_changed(next_role: String) -> void:
	_set_p2p_role_text(next_role)
	_append_log("[p2p] role => %s" % next_role)

func _on_p2p_connection_state_changed(next_state: String) -> void:
	_set_p2p_connection_text(next_state)

func _on_p2p_connection_failed(reason_code: String) -> void:
	_set_error_text(reason_code)
	_append_log("[p2p] connection_failed => %s" % reason_code)
	if auto_return_to_lobby_on_failure:
		_begin_return_to_lobby(reason_code)

func _on_p2p_transport_event(message: String) -> void:
	_append_log("[p2p] %s" % message)

func _on_lobby_state_changed(next_state: String) -> void:
	_set_lobby_state_text(next_state)
	_append_log("[lobby] state => %s" % next_state)

func _on_lobby_event(message: String) -> void:
	_append_log("[lobby] %s" % message)

func _new_script_instance(script_path: String):
	var script = load(script_path)
	if script == null:
		push_error("failed to load script: %s" % script_path)
		return null
	if not (script is GDScript):
		push_error("resource is not GDScript: %s" % script_path)
		return null
	if not script.can_instantiate():
		push_error("script cannot instantiate: %s" % script_path)
		return null
	return script.new()

func _create_p2p_transport():
	match p2p_transport_mode:
		"steam_stub":
			var stub = _new_script_instance(STEAM_P2P_TRANSPORT_SCRIPT_PATH)
			if stub == null:
				return null
			stub.listen_port = max(steam_stub_listen_port, 1)
			stub.default_remote_host = steam_stub_remote_host
			stub.default_remote_port = max(steam_stub_remote_port, 1)
			stub.endpoint_map_csv = steam_stub_endpoint_map_csv
			return stub
		_:
			var sim = _new_script_instance(SIMULATED_P2P_TRANSPORT_SCRIPT_PATH)
			if sim == null:
				return null
			sim.connect_delay_sec = max(simulated_connect_delay_sec, 0.01)
			sim.simulated_fail_hosts = _parse_csv_hosts(simulated_fail_hosts_csv)
			return sim

func _parse_float_or_default(raw_text: String, fallback: float) -> float:
	var text := raw_text.strip_edges()
	if text.is_empty():
		return fallback
	if not text.is_valid_float():
		return fallback
	return text.to_float()

func _parse_int_or_default(raw_text: String, fallback: int) -> int:
	var text := raw_text.strip_edges()
	if text.is_empty():
		return fallback
	if not text.is_valid_int():
		return fallback
	return text.to_int()

func _parse_bool_or_default(raw_text: String, fallback: bool) -> bool:
	var text := raw_text.strip_edges().to_lower()
	if text.is_empty():
		return fallback
	if text == "1" or text == "true" or text == "yes" or text == "on":
		return true
	if text == "0" or text == "false" or text == "no" or text == "off":
		return false
	return fallback

func _parse_csv_hosts(raw_text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for token in raw_text.split(",", false):
		var host := token.strip_edges()
		if host.is_empty():
			continue
		out.append(host)
	return out

func _set_status(text: String, color: Color) -> void:
	_state_label.text = text
	_state_label.modulate = color

func _set_host_text(text: String) -> void:
	_host_label.text = text

func _set_countdown_text(text: String) -> void:
	_countdown_label.text = text

func _set_error_text(text: String) -> void:
	_error_label.text = text

func _set_p2p_role_text(text: String) -> void:
	_p2p_role_label.text = text

func _set_p2p_connection_text(text: String) -> void:
	_p2p_conn_label.text = text

func _set_p2p_transport_text(text: String) -> void:
	_p2p_transport_label.text = text

func _set_lobby_state_text(text: String) -> void:
	_lobby_state_label.text = text

func _append_log(message: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_log_output.append_text("[%s] %s\n" % [stamp, message])
	var line_count := _log_output.get_line_count()
	if line_count > 0:
		_log_output.scroll_to_line(line_count - 1)

func _state_to_text(state: int) -> String:
	match state:
		NET_STATE_RUNNING:
			return "RUNNING"
		NET_STATE_MIGRATION_WAIT:
			return "MIGRATION_WAIT"
		NET_STATE_MIGRATION_CANDIDATE:
			return "MIGRATION_CANDIDATE"
		NET_STATE_MIGRATION_FOLLOWER:
			return "MIGRATION_FOLLOWER"
		NET_STATE_ABORTED:
			return "ABORTED"
		_:
			return "UNKNOWN"
