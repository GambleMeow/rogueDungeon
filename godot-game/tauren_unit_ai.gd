extends CharacterBody3D
class_name TaurenUnitAI

@export var move_speed: float = 140.0
@export var attack_range: float = 280.0
@export var engage_range: float = 900.0
@export var max_hp: int = 1050
@export var damage_per_hit: int = 12
@export var attack_speed: float = 1.1
@export var target_group_name: StringName = &"hero"
@export var idle_animation: String = "Stand - 1_GLTF"
@export var walk_animation: String = "Walk_GLTF"
@export var death_animation: String = "Death_GLTF"
@export var attack_animation_1: String = "Attack - 1_GLTF"
@export var attack_animation_2: String = ""
@export var attack_animation_3: String = ""
@export var hp_bar_height: float = 260.0
@export var hp_bar_width: float = 170.0
@export var collision_radius: float = 72.0
@export var collision_height: float = 192.0
@export_flags_3d_physics var movement_collision_layer: int = 8
@export_flags_3d_physics var movement_collision_mask: int = 9
@export_flags_3d_physics var click_collision_layer: int = 2
@export_flags_3d_physics var click_collision_mask: int = 0

var _model: Node3D
var _target: Node3D = null
var _animation_player: AnimationPlayer
var _nav_agent: NavigationAgent3D
var _move_collision_shape: CollisionShape3D
var _hp_bar: MeshInstance3D
var _hp_bar_material: ShaderMaterial
var _current_hp: int = 0
var _is_dead: bool = false
var _is_moving: bool = false
var _is_attacking: bool = false
var _attack_cooldown: float = 0.0
var _attack_anims: Array[String] = []
var _resolved_idle_animation: String = ""
var _resolved_walk_animation: String = ""
var _resolved_death_animation: String = ""
var _warned_missing_walk: bool = false
var _pending_idle_after_animation: bool = false


func setup_unit(model_scene: PackedScene, spawn_pos: Vector3, spawn_scale: Vector3) -> void:
	global_position = spawn_pos
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = model_scene.instantiate() as Node3D
	if _model == null:
		return
	_model.name = "Model"
	add_child(_model)
	_model.scale = spawn_scale
	_setup_movement_collision()
	_setup_collision_body()
	if is_inside_tree():
		_bind_runtime_after_model_ready()


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = movement_collision_layer
	collision_mask = movement_collision_mask
	velocity = Vector3.ZERO

	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 20.0
	_nav_agent.target_desired_distance = 20.0
	add_child(_nav_agent)

	_current_hp = max_hp

	if _model == null:
		push_warning("TaurenUnitAI 缺少模型实例。等待 setup_unit 初始化。")
		return

	_bind_runtime_after_model_ready()


func _bind_runtime_after_model_ready() -> void:
	if _model == null:
		return
	if _hp_bar == null or not is_instance_valid(_hp_bar):
		_create_hp_bar()
	_update_hp_bar()
	_animation_player = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_resolve_animations()
	_play_idle_animation()
	if _animation_player != null and not _animation_player.animation_finished.is_connected(_on_animation_finished):
		_animation_player.animation_finished.connect(_on_animation_finished)


func _process(delta: float) -> void:
	if _is_dead:
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta

	_update_target()
	if _target == null:
		velocity = Vector3.ZERO
		if _is_attacking:
			_is_attacking = false
			_queue_idle_after_current_animation()
		else:
			_stop_move_and_idle()
		return

	var target_pos: Vector3 = _target.global_position
	var distance: float = _distance_xz(global_position, target_pos)

	if _is_attacking:
		if distance > attack_range:
			_interrupt_attack_for_chase()
			return
		_face_toward(target_pos)
		return

	if distance > attack_range:
		_chase_target(target_pos)
	else:
		_stop_move_and_idle()
		_face_toward(target_pos)
		if _attack_cooldown <= 0.0:
			_start_attack()


func apply_damage(amount: int, attacker: Node3D = null) -> void:
	if _is_dead:
		return
	_current_hp = max(_current_hp - max(amount, 0), 0)
	_update_hp_bar()
	if amount > 0 and _current_hp > 0:
		_retarget_to_attacker(attacker)
	if _current_hp <= 0:
		_die()


func _retarget_to_attacker(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if _is_target_dead(attacker):
		return
	_target = attacker
	if _is_attacking:
		_interrupt_attack_for_chase()
	_pending_idle_after_animation = false
	_face_toward(attacker.global_position)
	if not _is_moving:
		_is_moving = true
		_play_walk_animation()


func is_dead() -> bool:
	return _is_dead


func _setup_movement_collision() -> void:
	_move_collision_shape = get_node_or_null("MovementCollision") as CollisionShape3D
	if _move_collision_shape == null:
		_move_collision_shape = CollisionShape3D.new()
		_move_collision_shape.name = "MovementCollision"
		add_child(_move_collision_shape)

	var capsule := CapsuleShape3D.new()
	capsule.radius = collision_radius
	capsule.height = collision_height
	_move_collision_shape.shape = capsule
	_move_collision_shape.position = Vector3(0.0, collision_height * 0.5, 0.0)


func _setup_collision_body() -> void:
	if _model == null:
		return
	var collision_body := _model.get_node_or_null("CollisionBody") as StaticBody3D
	if collision_body == null:
		collision_body = StaticBody3D.new()
		collision_body.name = "CollisionBody"
		_model.add_child(collision_body)
	collision_body.collision_layer = click_collision_layer
	collision_body.collision_mask = click_collision_mask
	collision_body.add_to_group("enemy")

	var collision_shape := collision_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		collision_body.add_child(collision_shape)

	var capsule := CapsuleShape3D.new()
	capsule.radius = collision_radius
	capsule.height = collision_height
	collision_shape.shape = capsule
	collision_shape.position = Vector3(0.0, collision_height * 0.5, 0.0)


func _update_target() -> void:
	# 一旦锁定目标，只在目标死亡/失效时才丢失
	if _target != null and is_instance_valid(_target) and not _is_target_dead(_target):
		return
	# 仅在索敌范围内获取新目标
	_target = _find_nearest_target()


func _find_nearest_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	for node in get_tree().get_nodes_in_group(target_group_name):
		var target := node as Node3D
		if target == null:
			continue
		if _is_target_dead(target):
			continue
		var distance: float = _distance_xz(global_position, target.global_position)
		if distance > engage_range:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = target
	return nearest


func _is_target_dead(target: Node3D) -> bool:
	var controller := target.get_parent()
	if controller != null and controller.has_method("is_dead"):
		return bool(controller.call("is_dead"))
	return false


func _chase_target(target_pos: Vector3) -> void:
	_nav_agent.target_position = target_pos
	var move_target := target_pos
	if not _nav_agent.is_navigation_finished():
		var next_nav := _nav_agent.get_next_path_position()
		if _distance_xz(next_nav, global_position) > 1.0:
			move_target = next_nav

	var move_dir := move_target - global_position
	move_dir.y = 0.0
	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()
		velocity = Vector3(move_dir.x * move_speed, 0.0, move_dir.z * move_speed)
		move_and_slide()
	else:
		velocity = Vector3.ZERO

	_look_at_target(move_target)
	if not _is_moving:
		_is_moving = true
		_play_walk_animation()


func _start_attack() -> void:
	_is_attacking = true
	velocity = Vector3.ZERO
	_attack_cooldown = _get_attack_interval()
	var attack_anim := _choose_attack_animation()
	if _animation_player != null and attack_anim != "":
		var anim := _animation_player.get_animation(attack_anim)
		if anim != null:
			anim.loop_mode = Animation.LOOP_NONE
		_animation_player.play(attack_anim, -1.0, _get_attack_speed_scale(), false)
	_try_apply_damage_to_target()


func _choose_attack_animation() -> String:
	if _attack_anims.is_empty():
		return ""
	return _attack_anims[randi() % _attack_anims.size()]


func _try_apply_damage_to_target() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if _is_target_dead(_target):
		return
	var distance: float = _distance_xz(global_position, _target.global_position)
	if distance > attack_range:
		return
	var target_controller := _target.get_parent()
	if target_controller != null and target_controller.has_method("apply_damage"):
		if _model != null:
			target_controller.call("apply_damage", damage_per_hit, false, _model)
		else:
			target_controller.call("apply_damage", damage_per_hit)
		if _is_target_dead(_target):
			_target = _find_nearest_target()
			if _target == null:
				_is_attacking = false
				_queue_idle_after_current_animation()


func _on_animation_finished(_anim_name: StringName) -> void:
	if _is_attacking:
		_is_attacking = false
	if _pending_idle_after_animation:
		_pending_idle_after_animation = false
		_play_idle_animation()


func _stop_move_and_idle() -> void:
	velocity = Vector3.ZERO
	if _is_moving:
		_is_moving = false
	_play_idle_animation()


func _queue_idle_after_current_animation() -> void:
	if _animation_player == null:
		_play_idle_animation()
		return
	if not _animation_player.is_playing():
		_play_idle_animation()
		return
	var current_anim_name: String = String(_animation_player.current_animation)
	if current_anim_name == _resolved_idle_animation:
		return
	if _resolved_walk_animation != "" and current_anim_name == _resolved_walk_animation:
		_play_idle_animation()
		return
	var current_anim: Animation = _animation_player.get_animation(_animation_player.current_animation)
	if current_anim != null and current_anim.loop_mode == Animation.LOOP_NONE:
		_pending_idle_after_animation = true
		return
	_play_idle_animation()


func _interrupt_attack_for_chase() -> void:
	if not _is_attacking:
		return
	_is_attacking = false
	if _animation_player != null and _animation_player.is_playing():
		_animation_player.stop()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	_is_attacking = false
	_pending_idle_after_animation = false
	_is_moving = false
	velocity = Vector3.ZERO
	_target = null
	if _hp_bar != null:
		_hp_bar.visible = false
	if _animation_player != null and _resolved_death_animation != "":
		var anim := _animation_player.get_animation(_resolved_death_animation)
		if anim != null:
			anim.loop_mode = Animation.LOOP_NONE
		_animation_player.play(_resolved_death_animation, -1.0, 1.0, false)
		var death_duration := 0.8
		if anim != null:
			death_duration = maxf(anim.length, 0.1)
		get_tree().create_timer(death_duration).timeout.connect(queue_free)
	else:
		queue_free()


func _resolve_animations() -> void:
	if _animation_player == null:
		return
	_resolved_idle_animation = _resolve_animation(idle_animation, ["stand", "idle", "wait"])
	_resolved_walk_animation = _resolve_animation(walk_animation, ["walk", "run", "move", "locomotion", "go"])
	_resolved_death_animation = _resolve_animation(death_animation, ["death", "die"])
	_resolve_attack_animations()
	if _resolved_walk_animation == "":
		_resolved_walk_animation = _fallback_walk_animation()
	if _resolved_walk_animation == "" and not _warned_missing_walk:
		_warned_missing_walk = true
		push_warning("TaurenUnitAI 未找到行走动画，可用动画: %s" % [str(_animation_player.get_animation_list())])


func _resolve_animation(preferred_name: String, keywords: Array[String]) -> String:
	if preferred_name != "" and _animation_player.has_animation(preferred_name):
		return preferred_name
	var anim_list: PackedStringArray = _animation_player.get_animation_list()
	for anim_name_sn in anim_list:
		var anim_name: String = String(anim_name_sn)
		var lower: String = anim_name.to_lower()
		for kw in keywords:
			if lower.find(kw) >= 0:
				return anim_name
	return ""


func _resolve_attack_animations() -> void:
	_attack_anims.clear()
	if _animation_player == null:
		return
	var preferred: Array[String] = [attack_animation_1, attack_animation_2, attack_animation_3]
	for anim_name in preferred:
		if anim_name != "" and _animation_player.has_animation(anim_name) and anim_name not in _attack_anims:
			_attack_anims.append(anim_name)

	if _attack_anims.is_empty():
		var anim_list: PackedStringArray = _animation_player.get_animation_list()
		for anim_name_sn in anim_list:
			var anim_name: String = String(anim_name_sn)
			var lower: String = anim_name.to_lower()
			if lower.find("attack") >= 0 and lower.find("slam") < 0 and lower.find("spell") < 0:
				_attack_anims.append(anim_name)
				if _attack_anims.size() >= 3:
					break
		if _attack_anims.is_empty():
			for anim_name_sn in anim_list:
				var anim_name: String = String(anim_name_sn)
				if anim_name.to_lower().find("attack") >= 0:
					_attack_anims.append(anim_name)
					break


func _fallback_walk_animation() -> String:
	if _animation_player == null:
		return ""
	var anim_list: PackedStringArray = _animation_player.get_animation_list()
	for anim_name_sn in anim_list:
		var anim_name: String = String(anim_name_sn)
		var lower: String = anim_name.to_lower()
		if anim_name == _resolved_idle_animation or anim_name == _resolved_death_animation:
			continue
		if lower.find("attack") >= 0 or lower.find("spell") >= 0 or lower.find("slam") >= 0:
			continue
		if lower.find("death") >= 0 or lower.find("die") >= 0 or lower.find("stand") >= 0 or lower.find("idle") >= 0:
			continue
		return anim_name
	return ""


func _play_idle_animation() -> void:
	if _animation_player == null or _resolved_idle_animation == "":
		return
	if _animation_player.is_playing() and _animation_player.current_animation == _resolved_idle_animation:
		return
	var anim := _animation_player.get_animation(_resolved_idle_animation)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(_resolved_idle_animation, -1.0, 1.0, false)


func _play_walk_animation() -> void:
	if _animation_player == null or _resolved_walk_animation == "":
		return
	if _animation_player.is_playing() and _animation_player.current_animation == _resolved_walk_animation:
		return
	var anim := _animation_player.get_animation(_resolved_walk_animation)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(_resolved_walk_animation, -1.0, 1.0, false)


func _look_at_target(target_pos: Vector3) -> void:
	var direction := target_pos - global_position
	direction.y = 0.0
	if direction.length() > 0.01:
		rotation.y = atan2(direction.x, direction.z) - PI / 2.0


func _face_toward(target_pos: Vector3) -> void:
	var direction := target_pos - global_position
	direction.y = 0.0
	if direction.length() > 0.01:
		rotation.y = atan2(direction.x, direction.z) - PI / 2.0


func _distance_xz(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()


func _get_attack_speed_scale() -> float:
	return maxf(attack_speed, 0.05)


func _get_attack_interval() -> float:
	return 1.0 / _get_attack_speed_scale()


func _create_hp_bar() -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\nuniform float hp_ratio : hint_range(0.0, 1.0) = 1.0;\nvoid vertex() {\n\tMODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);\n\tMODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);\n}\nvoid fragment() {\n\tvec2 uv = UV;\n\tfloat bw = 0.04;\n\tfloat bh = 0.12;\n\tif (uv.x < bw || uv.x > 1.0 - bw || uv.y < bh || uv.y > 1.0 - bh) {\n\t\tALBEDO = vec3(0.0);\n\t\tALPHA = 0.9;\n\t} else {\n\t\tfloat ix = (uv.x - bw) / (1.0 - 2.0 * bw);\n\t\tif (ix <= hp_ratio) {\n\t\t\tALBEDO = vec3(1.0 - hp_ratio, hp_ratio, 0.0);\n\t\t\tALPHA = 0.9;\n\t\t} else {\n\t\t\tALBEDO = vec3(0.15);\n\t\t\tALPHA = 0.5;\n\t\t}\n\t}\n}\n"
	_hp_bar_material = ShaderMaterial.new()
	_hp_bar_material.shader = shader
	_hp_bar_material.set_shader_parameter("hp_ratio", 1.0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(hp_bar_width, 20.0)
	_hp_bar = MeshInstance3D.new()
	_hp_bar.mesh = mesh
	_hp_bar.material_override = _hp_bar_material
	_hp_bar.position = Vector3(0.0, hp_bar_height, 0.0)
	add_child(_hp_bar)


func _update_hp_bar() -> void:
	if _hp_bar_material == null:
		return
	if max_hp <= 0:
		_hp_bar_material.set_shader_parameter("hp_ratio", 0.0)
		return
	_hp_bar_material.set_shader_parameter("hp_ratio", float(_current_hp) / float(max_hp))
