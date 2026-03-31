extends Node3D

const GATE_SCRIPT := preload("res://boss_gate.gd")
const DEFAULT_CAMERA_OFFSET := Vector3(0.0, 1700.0, 1050.0)

@export var navigation_region_path: NodePath = NodePath("NavigationRegion")
@export var shop_path: NodePath = NodePath("NavigationRegion/Shop")
@export var hero_controller_path: NodePath = NodePath("HeroController")
@export var hero_path: NodePath = NodePath("HeroController/herowarden")
@export var boss_path: NodePath = NodePath("EnemyAI/HeroTaurenChieftain2")
@export var camera_path: NodePath = NodePath("Camera3D")

@export var start_point: Vector3 = Vector3(-4500.0, 0.0, 0.0)
@export var hero_start_offset: Vector3 = Vector3(-220.0, 0.0, 140.0)
@export var host_start_extra_offset: Vector3 = Vector3(-180.0, 0.0, 0.0)
@export var client_start_extra_offset: Vector3 = Vector3(180.0, 0.0, 0.0)
@export var hero_spawn_min_radius: float = 560.0
@export var gate_offset: Vector3 = Vector3(0.0, 0.0, -280.0)
@export var boss_entry_offset: Vector3 = Vector3(-260.0, 0.0, -100.0)
@export var boss_battle_role_offset_scale: float = 1.0
@export var camera_focus_height: float = 120.0
@export var edge_scroll_enabled: bool = true
@export var edge_scroll_margin_px: int = 24
@export var edge_scroll_speed: float = 1800.0
@export var edge_scroll_accel_curve: float = 3
@export var camera_height_min: float = 500.0
@export var camera_height_max: float = 3200.0
@export var camera_height_wheel_step: float = 120.0
@export var camera_height_anim_duration: float = 0.18
@export var camera_refocus_double_tap_ms: int = 320

@export var gate_scene: PackedScene = preload("res://modles/CityEnteranceGate.glb")
@export var gate_model_scale: Vector3 = Vector3(1.3333334, 1.3333334, 1.3333334)
@export var gate_collider_size: Vector3 = Vector3(173.33334, 146.66667, 80.0)
@export var gate_max_hp: int = 100
@export var melee_hero_scene: PackedScene = preload("res://modles/herowarden.glb")
@export var ranged_hero_scene: PackedScene = preload("res://modles/Rifleman.glb")
@export var melee_hero_name: String = "近战"
@export var ranged_hero_name: String = "远程"

var _camera_offset_from_hero: Vector3 = DEFAULT_CAMERA_OFFSET
var _hero_selected: bool = false
var _hero_select_layer: CanvasLayer
var _camera_height_target: float = DEFAULT_CAMERA_OFFSET.y
var _camera_height_tween: Tween
var _network_role: String = "offline"
var _last_refocus_key_time_ms: int = -1000000
var _boss_battle_started: bool = false


func _ready() -> void:
	set_process(true)
	set_process_input(true)
	_parse_network_role_from_cmdline()
	var hero := _get_current_hero()
	var camera := get_node_or_null(camera_path) as Camera3D
	if hero != null and camera != null:
		_camera_offset_from_hero = camera.global_position - hero.global_position
		_camera_height_target = camera.global_position.y

	_move_shop_to_start_point()
	_spawn_gate_near_shop()
	_move_hero_to_start_point()

	hero = _get_current_hero()
	if hero != null and camera != null:
		_focus_camera_on(hero.global_position, camera)
	_show_hero_select_ui()


func _input(event: InputEvent) -> void:
	if not _hero_selected:
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_1 or key_event.keycode == KEY_KP_1):
			var now_ms: int = Time.get_ticks_msec()
			var elapsed_ms: int = now_ms - _last_refocus_key_time_ms
			_last_refocus_key_time_ms = now_ms
			if elapsed_ms <= maxi(camera_refocus_double_tap_ms, 1):
				_refocus_camera_to_hero()
			return
	if not (event is InputEventMouseButton):
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_adjust_camera_height(-absf(camera_height_wheel_step))
	elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_adjust_camera_height(absf(camera_height_wheel_step))


func _refocus_camera_to_hero() -> void:
	var camera := get_node_or_null(camera_path) as Camera3D
	var hero := _get_current_hero()
	if camera == null or hero == null:
		return
	_focus_camera_on(hero.global_position, camera)


func _adjust_camera_height(delta_y: float) -> void:
	var camera := get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return
	var min_h: float = minf(camera_height_min, camera_height_max)
	var max_h: float = maxf(camera_height_min, camera_height_max)
	_camera_height_target = clampf(_camera_height_target + delta_y, min_h, max_h)
	_start_camera_height_tween(camera)


func _start_camera_height_tween(camera: Camera3D) -> void:
	if camera == null:
		return
	if _camera_height_tween != null and _camera_height_tween.is_valid():
		_camera_height_tween.kill()
	var from_h: float = camera.global_position.y
	var to_h: float = _camera_height_target
	if absf(to_h - from_h) <= 0.001:
		_apply_camera_height(to_h)
		return
	var duration: float = maxf(camera_height_anim_duration, 0.01)
	_camera_height_tween = create_tween()
	_camera_height_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_camera_height_tween.tween_method(Callable(self, "_apply_camera_height"), from_h, to_h, duration)


func _apply_camera_height(height: float) -> void:
	var camera := get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return
	var pos: Vector3 = camera.global_position
	pos.y = height
	camera.global_position = pos
	var hero := _get_current_hero()
	if hero != null:
		_camera_offset_from_hero.y = height - hero.global_position.y


func _process(delta: float) -> void:
	if not _hero_selected:
		return
	if not edge_scroll_enabled:
		return
	var camera := get_node_or_null(camera_path) as Camera3D
	if camera == null:
		return
	var viewport := get_viewport()
	if viewport == null:
		return
	var view_size: Vector2 = viewport.get_visible_rect().size
	if view_size.x <= 1.0 or view_size.y <= 1.0:
		return
	var mouse_pos: Vector2 = viewport.get_mouse_position()

	var margin: float = float(maxi(edge_scroll_margin_px, 1))
	var planar_right: Vector3 = camera.global_basis.x
	planar_right.y = 0.0
	planar_right = planar_right.normalized()
	var planar_forward: Vector3 = -camera.global_basis.z
	planar_forward.y = 0.0
	planar_forward = planar_forward.normalized()
	if planar_right.length() <= 0.001 or planar_forward.length() <= 0.001:
		return

	var left_strength: float = clampf((margin - mouse_pos.x) / margin, 0.0, 1.0)
	var right_strength: float = clampf((mouse_pos.x - (view_size.x - margin)) / margin, 0.0, 1.0)
	var top_strength: float = clampf((margin - mouse_pos.y) / margin, 0.0, 1.0)
	var bottom_strength: float = clampf((mouse_pos.y - (view_size.y - margin)) / margin, 0.0, 1.0)

	var move_axis := Vector2(right_strength - left_strength, top_strength - bottom_strength)
	if move_axis.length() <= 0.001:
		return

	var move_dir: Vector3 = planar_right * move_axis.x + planar_forward * move_axis.y
	if move_dir.length() <= 0.001:
		return
	move_dir = move_dir.normalized()

	var intensity: float = clampf(move_axis.length(), 0.0, 1.0)
	intensity = pow(intensity, maxf(edge_scroll_accel_curve, 0.01))
	camera.global_position += move_dir * edge_scroll_speed * intensity * delta


func _get_hero_controller() -> Node:
	return get_node_or_null(hero_controller_path)


func _get_current_hero() -> Node3D:
	var hero_controller := _get_hero_controller()
	if hero_controller != null:
		var hero_variant: Variant = hero_controller.get("_hero")
		if hero_variant is Node3D:
			var hero_node := hero_variant as Node3D
			if hero_node != null and is_instance_valid(hero_node):
				return hero_node
	var fallback := get_node_or_null(hero_path) as Node3D
	if fallback != null and is_instance_valid(fallback):
		return fallback
	return null


func _set_hero_control_enabled(enabled: bool) -> void:
	var hero_controller := _get_hero_controller()
	if hero_controller == null:
		return
	hero_controller.set_process(enabled)
	hero_controller.set_process_input(enabled)


func _show_hero_select_ui() -> void:
	_set_hero_control_enabled(false)
	_hero_selected = false
	if _hero_select_layer != null and is_instance_valid(_hero_select_layer):
		_hero_select_layer.queue_free()

	_hero_select_layer = CanvasLayer.new()
	_hero_select_layer.name = "HeroSelectLayer"
	add_child(_hero_select_layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_hero_select_layer.add_child(root)

	var mask := ColorRect.new()
	mask.set_anchors_preset(Control.PRESET_FULL_RECT)
	mask.color = Color(0.0, 0.0, 0.0, 0.62)
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(mask)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -110
	panel.offset_bottom = 110
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(panel)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.07, 0.12, 0.96)
	panel_style.border_color = Color(0.78, 0.66, 0.2, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", panel_style)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20
	vbox.offset_right = -20
	vbox.offset_top = 16
	vbox.offset_bottom = -16
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "请选择英雄"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78, 1.0))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "近战: 守望者    远程: 火枪手"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.72, 0.72, 0.72, 1.0))
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 18)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var melee_btn := Button.new()
	melee_btn.text = melee_hero_name
	melee_btn.custom_minimum_size = Vector2(160, 52)
	melee_btn.pressed.connect(func() -> void:
		_on_hero_selected(false)
	)
	btn_row.add_child(melee_btn)

	var ranged_btn := Button.new()
	ranged_btn.text = ranged_hero_name
	ranged_btn.custom_minimum_size = Vector2(160, 52)
	ranged_btn.pressed.connect(func() -> void:
		_on_hero_selected(true)
	)
	btn_row.add_child(ranged_btn)


func _on_hero_selected(use_ranged: bool) -> void:
	var hero_controller := _get_hero_controller()
	if hero_controller != null and hero_controller.has_method("apply_hero_profile_by_id"):
		hero_controller.call("apply_hero_profile_by_id", 2 if use_ranged else 1)
	elif hero_controller != null and hero_controller.has_method("apply_hero_profile"):
		if use_ranged:
			hero_controller.call("apply_hero_profile", "远程")
		else:
			hero_controller.call("apply_hero_profile", "近战")
	if hero_controller != null and hero_controller.has_method("select_hero_model"):
		if use_ranged:
			hero_controller.call("select_hero_model", ranged_hero_scene, ranged_hero_name)
		else:
			hero_controller.call("select_hero_model", melee_hero_scene, melee_hero_name)

	_move_hero_to_start_point()
	var camera := get_node_or_null(camera_path) as Camera3D
	var hero := _get_current_hero()
	if camera != null and hero != null:
		_focus_camera_on(hero.global_position, camera)

	if _hero_select_layer != null and is_instance_valid(_hero_select_layer):
		_hero_select_layer.queue_free()
	_hero_select_layer = null
	_hero_selected = true
	_set_hero_control_enabled(true)


func _move_shop_to_start_point() -> void:
	var shop := get_node_or_null(shop_path) as Node3D
	if shop == null:
		return
	shop.global_position = start_point


func _spawn_gate_near_shop() -> void:
	var nav_root := get_node_or_null(navigation_region_path) as Node3D
	if nav_root == null:
		return

	var old_gate := nav_root.get_node_or_null("CityEnteranceGate")
	if old_gate != null:
		old_gate.queue_free()

	var gate := Node3D.new()
	gate.name = "CityEnteranceGate"
	gate.set_script(GATE_SCRIPT)
	gate.set("max_hp", maxi(gate_max_hp, 1))
	gate.global_position = start_point + gate_offset
	nav_root.add_child(gate)

	var gate_body := Node3D.new()
	gate_body.name = "GateBody"
	gate_body.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	gate.add_child(gate_body)

	if gate_scene != null:
		var gate_model := gate_scene.instantiate()
		if gate_model != null:
			gate_model.name = "Model"
			if gate_model is Node3D:
				(gate_model as Node3D).scale = gate_model_scale
			_disable_collision_on_model(gate_model)
			gate_body.add_child(gate_model)

	var collision_body := StaticBody3D.new()
	collision_body.name = "CollisionBody"
	collision_body.add_to_group("enemy")
	gate_body.add_child(collision_body)

	var shape := BoxShape3D.new()
	shape.size = gate_collider_size
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	collision_shape.shape = shape
	collision_shape.position = Vector3(0.0, gate_collider_size.y * 0.5, 0.0)
	collision_body.add_child(collision_shape)

	if gate.has_signal("gate_destroyed"):
		gate.connect("gate_destroyed", Callable(self, "_on_gate_destroyed"))


func _move_hero_to_start_point() -> void:
	var hero := _get_current_hero()
	if hero == null:
		return
	var target: Vector3 = _get_spawn_position_around_shop()
	target.y = hero.global_position.y
	hero.global_position = target
	_reset_hero_controller_state(target)


func _on_gate_destroyed() -> void:
	if _boss_battle_started:
		return
	var boss := get_node_or_null(boss_path) as Node3D
	if boss == null:
		return
	var boss_anchor: Vector3 = boss.global_position
	if _network_role == "host" and multiplayer.multiplayer_peer != null:
		rpc("rpc_start_boss_battle", boss_anchor)
	elif _network_role == "client":
		# 客户端等待 host 广播统一开战时机，避免本地误触发。
		return
	_start_boss_battle_locally(boss_anchor)


@rpc("authority", "call_remote", "reliable")
func rpc_start_boss_battle(boss_anchor: Vector3) -> void:
	_start_boss_battle_locally(boss_anchor)


func _start_boss_battle_locally(boss_anchor: Vector3) -> void:
	if _boss_battle_started:
		return
	var hero := _get_current_hero()
	if hero == null:
		return
	_boss_battle_started = true
	var entry_position := _get_boss_battle_entry_position(boss_anchor)
	entry_position.y = hero.global_position.y
	hero.global_position = entry_position
	_reset_hero_controller_state(entry_position)

	var camera := get_node_or_null(camera_path) as Camera3D
	if camera != null:
		_focus_camera_on(entry_position, camera)


func _reset_hero_controller_state(hero_position: Vector3) -> void:
	var hero_controller := get_node_or_null(hero_controller_path)
	if hero_controller == null:
		return

	hero_controller.set("_target_enemy", null)
	hero_controller.set("_has_move_target", false)
	hero_controller.set("_is_moving", false)
	hero_controller.set("_is_attacking", false)
	hero_controller.set("_focus_lock", false)
	hero_controller.set("_flash_mode", false)
	hero_controller.set("_attack_mode", false)
	hero_controller.set("_target_position", hero_position)

	if hero_controller.has_method("_stop_animation"):
		hero_controller.call("_stop_animation")


func _focus_camera_on(hero_position: Vector3, camera: Camera3D) -> void:
	var min_h: float = minf(camera_height_min, camera_height_max)
	var max_h: float = maxf(camera_height_min, camera_height_max)
	var target_pos := hero_position + _camera_offset_from_hero
	target_pos.y = clampf(target_pos.y, min_h, max_h)
	if _camera_height_tween != null and _camera_height_tween.is_valid():
		_camera_height_tween.kill()
	camera.global_position = target_pos
	_camera_height_target = target_pos.y
	_camera_offset_from_hero.y = target_pos.y - hero_position.y


func _disable_collision_on_model(root: Node) -> void:
	if root == null:
		return
	if root is CollisionObject3D:
		var collision_obj := root as CollisionObject3D
		collision_obj.collision_layer = 0
		collision_obj.collision_mask = 0
	for child in root.get_children():
		var child_node := child as Node
		if child_node != null:
			_disable_collision_on_model(child_node)


func _parse_network_role_from_cmdline() -> void:
	_network_role = "offline"
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
		value = value.strip_edges().to_lower()
		if key == "net" or key == "network" or key == "mode" or key == "net-mode" or key == "net_mode":
			if value == "host" or value == "client" or value == "offline":
				_network_role = value
				return


func _get_network_spawn_extra_offset() -> Vector3:
	if _network_role == "host":
		return host_start_extra_offset
	if _network_role == "client":
		return client_start_extra_offset
	return Vector3.ZERO


func _get_spawn_position_around_shop() -> Vector3:
	var center: Vector3 = _get_shop_center_position()
	var desired: Vector3 = hero_start_offset + _get_network_spawn_extra_offset()
	desired.y = 0.0
	if desired.length_squared() <= 0.0001:
		desired = Vector3(-1.0, 0.0, 0.0)
	var dir: Vector3 = desired.normalized()
	var spawn_radius: float = maxf(hero_spawn_min_radius, desired.length())
	return center + dir * spawn_radius


func _get_shop_center_position() -> Vector3:
	var shop := get_node_or_null(shop_path) as Node3D
	if shop != null:
		return shop.global_position
	return start_point


func _get_boss_battle_entry_position(boss_anchor: Vector3) -> Vector3:
	var role_offset: Vector3 = _get_network_spawn_extra_offset() * maxf(boss_battle_role_offset_scale, 0.0)
	return boss_anchor + boss_entry_offset + role_offset
