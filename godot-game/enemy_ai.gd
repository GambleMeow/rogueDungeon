extends Node3D

@export var enemy_path: NodePath = NodePath("boss_027")
@export var hero_path: NodePath = NodePath("../herowarden")
@export var hero_group_name: StringName = &"hero"
@export var move_speed: float = 150.0
@export var attack_range: float = 450.0
@export var engage_range_multiplier: float = 3.0
@export var max_hp: int = 10000
@export var damage_per_hit: int = 20
@export var attack_speed: float = 1.0
@export var death_animation: String = "Death_GLTF"
@export var hp_bar_height: float = 300.0
@export var hp_bar_width: float = 300.0
@export var idle_animation: String = "Idle"
@export var walk_animation: String = "walk"
@export var attack_animation_1: String = "attack1"
@export var attack_animation_2: String = "attack2"
@export var attack_animation_3: String = "attack3"
@export var skill_animation: String = "Skill"
@export var skill_range_multiplier: float = 2.0
@export var skill_cast_time: float = 4.0
@export var skill_damage: int = 50
@export var skill_cooldown_time: float = 15.0
@export var skill2_animation: String = "Skill2"
@export var skill2_distance_multiplier: float = 2.5
@export var skill2_cast_time: float = 1.5
@export var skill2_damage: int = 50
@export var skill2_cooldown_time: float = 10.0
@export var skill2_hit_range: float = 150.0
@export var network_authoritative: bool = true
@export var remote_sync_position_smooth_speed: float = 12.0
@export var remote_sync_rotation_smooth_speed: float = 10.0
@export var remote_sync_snap_distance: float = 320.0
@export var remote_sync_prediction_sec: float = 0.10

var _enemy: Node3D
var _hero: Node3D
var _animation_player: AnimationPlayer
var _is_moving: bool = false
var _is_attacking: bool = false
var _attack_cooldown: float = 0.0
var _current_attack_index: int = 0
var _attack_animations: Array[String] = []
var _engage_initialized: bool = false
var _was_in_engage_range: bool = false
var _is_engaged: bool = false
var _current_hp: int = 0
var _is_dead: bool = false
var _hp_bar: MeshInstance3D
var _hp_bar_material: ShaderMaterial
var _death_finalized: bool = false
var _nav_agent: NavigationAgent3D
var _is_casting_skill: bool = false
var _skill_cast_timer: float = 0.0
var _skill_cooldown: float = 0.0
var _skill_warning: MeshInstance3D = null
var _engage_timer: float = 0.0
var _chase_timer: float = 0.0
var _target_lock_active: bool = false
var _is_casting_skill2: bool = false
var _skill2_timer: float = 0.0
var _skill2_cooldown: float = 0.0
var _skill2_start_pos: Vector3
var _skill2_end_pos: Vector3
var _skill2_total_time: float = 0.0
var _skill2_hit_applied: bool = false
var _pending_idle_after_animation: bool = false
var _remote_target_position: Vector3 = Vector3.ZERO
var _remote_target_yaw: float = 0.0
var _remote_velocity: Vector3 = Vector3.ZERO
var _remote_last_receive_ms: int = 0
var _remote_has_target: bool = false
const OBSTACLE_RAY_MASK: int = 1 << 0
const OBSTACLE_STEER_ANGLES := [20.0, -20.0, 40.0, -40.0, 60.0, -60.0, 80.0, -80.0, 100.0, -100.0]


func _ready() -> void:
	_enemy = get_node_or_null(enemy_path) as Node3D
	if _enemy == null:
		push_warning("enemy_path 未指向有效的 Node3D。")
		set_process(false)
		return
	
	_hero = get_node_or_null(hero_path) as Node3D
	if _hero == null:
		push_warning("hero_path 未指向有效的 Node3D，将使用最近英雄分组目标。")
	
	var initial_rotation := _enemy.rotation
	initial_rotation.z = 0.0
	_enemy.rotation = initial_rotation
	
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 20.0
	_nav_agent.target_desired_distance = 20.0
	_enemy.add_child(_nav_agent)
	
	_animation_player = _enemy.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		push_warning("未在小怪中找到 AnimationPlayer 节点。")
	elif not _animation_player.animation_finished.is_connected(_on_attack_finished):
		_animation_player.animation_finished.connect(_on_attack_finished)
	
	var _raw := [attack_animation_1, attack_animation_2, attack_animation_3].filter(func(a): return a != "")
	_attack_animations.clear()
	for a in _raw:
		_attack_animations.append(a)
	_current_hp = max_hp
	_remote_target_position = _enemy.global_position
	_remote_target_yaw = _enemy.rotation.y
	_remote_last_receive_ms = Time.get_ticks_msec()
	_remote_has_target = true
	_create_hp_bar()
	_update_hp_bar()
	_play_idle_animation()


func _play_idle_animation() -> void:
	if _animation_player != null and _animation_player.has_animation(idle_animation):
		var anim = _animation_player.get_animation(idle_animation)
		if anim != null:
			anim.loop_mode = Animation.LOOP_LINEAR
		_animation_player.play(idle_animation)


func _process(delta: float) -> void:
	if _enemy == null or _is_dead:
		return
	if not network_authoritative:
		_update_remote_sync_smoothing(delta)
		return
	
	if _hero == null or not is_instance_valid(_hero) or _is_hero_dead(_hero) or not _hero.visible:
		_hero = _find_nearest_hero()
		_target_lock_active = false
	elif not _target_lock_active and not _is_casting_skill and not _is_casting_skill2:
		var nearest := _find_nearest_hero()
		if nearest != null:
			_hero = nearest

	if _hero == null:
		_is_engaged = false
		_target_lock_active = false
		_engage_timer = 0.0
		_chase_timer = 0.0
		if _is_attacking or _is_casting_skill or _is_casting_skill2:
			_is_attacking = false
			_is_casting_skill = false
			_is_casting_skill2 = false
			_hide_skill_warning()
			_queue_idle_after_current_animation()
			return
		if _is_moving:
			_is_moving = false
			_stop_animation()
		return
	
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if _skill_cooldown > 0.0:
		_skill_cooldown -= delta
	if _skill2_cooldown > 0.0:
		_skill2_cooldown -= delta
	
	if _is_casting_skill2:
		_skill2_timer += delta
		var progress := clampf(_skill2_timer / _skill2_total_time, 0.0, 1.0)
		_enemy.global_position = _skill2_start_pos.lerp(_skill2_end_pos, progress)
		if not _skill2_hit_applied and _hero != null and is_instance_valid(_hero) and not _is_hero_dead(_hero):
			var dist := _distance_xz(_enemy.global_position, _hero.global_position)
			if dist <= skill2_hit_range:
				_skill2_hit_applied = true
				var hero_controller := _hero.get_parent()
				var handled: bool = false
				if hero_controller != null and hero_controller.has_method("apply_damage"):
					hero_controller.call("apply_damage", skill2_damage, false, _enemy)
					handled = true
				if hero_controller != null and hero_controller.has_method("apply_temporary_slow"):
					hero_controller.call("apply_temporary_slow", 50.0, 1.5)
				if not handled:
					var target_peer_id: int = _get_remote_target_peer_id(_hero)
					if target_peer_id > 0:
						var net_ctrl: Node = _get_network_session_controller()
						if net_ctrl != null:
							if net_ctrl.has_method("request_damage_remote_hero"):
								net_ctrl.call("request_damage_remote_hero", target_peer_id, skill2_damage, false)
							if net_ctrl.has_method("request_slow_remote_hero"):
								net_ctrl.call("request_slow_remote_hero", target_peer_id, 50.0, 1.5)
		if _skill2_timer >= _skill2_total_time:
			_finish_skill2()
		return
	
	if _is_casting_skill:
		_skill_cast_timer -= delta
		if _hero != null and is_instance_valid(_hero):
			_face_toward(_hero.global_position)
		if _skill_warning != null:
			_skill_warning.position = Vector3(_enemy.global_position.x, 1.0, _enemy.global_position.z)
			if _skill_cast_timer <= skill_cast_time - 2.5:
				_hide_skill_warning()
		if _skill_cast_timer <= 0.0:
			_finish_skill()
		return
	
	if _is_attacking:
		if _hero == null or not is_instance_valid(_hero) or _is_hero_dead(_hero):
			_is_attacking = false
			_current_attack_index = 0
			_hero = null
			_is_engaged = false
			_target_lock_active = false
			_queue_idle_after_current_animation()
			return
		
		_face_toward(_hero.global_position)
		
		var attack_distance := _distance_xz(_enemy.global_position, _hero.global_position)
		if attack_distance > attack_range:
			_interrupt_attack_for_chase()
		
		return
	
	var enemy_pos := _enemy.global_position
	var hero_pos := _hero.global_position
	var distance := _distance_xz(enemy_pos, hero_pos)
	var engage_range := attack_range * engage_range_multiplier
	var in_engage_range := distance <= engage_range
	
	if not _engage_initialized:
		_engage_initialized = true
		return
	
	if not _is_engaged:
		if in_engage_range:
			_is_engaged = true
			_target_lock_active = true
			_chase_timer = 0.0
	
	if not _is_engaged:
		_engage_timer = 0.0
		if _is_moving:
			_is_moving = false
			_stop_animation()
		return
	
	if distance <= attack_range:
		_chase_timer = 0.0
	else:
		_chase_timer += delta
	
	_engage_timer += delta
	
	if _engage_timer >= 1.0 and _skill2_cooldown <= 0.0 and distance <= engage_range:
		if _is_moving:
			_is_moving = false
		_start_skill2()
		return
	
	var skill_range := attack_range * skill_range_multiplier
	
	if _engage_timer >= 1.0 and _skill_cooldown <= 0.0 and distance <= skill_range:
		if _is_moving:
			_is_moving = false
		_face_toward(hero_pos)
		_start_skill()
		return
	
	if distance <= attack_range:
		if _is_moving:
			_is_moving = false
			_stop_animation()
		
		_face_toward(hero_pos)
		
		if _attack_cooldown <= 0.0:
			_start_attack()
		return
	
	if distance > engage_range and not _target_lock_active:
		if _is_moving:
			_is_moving = false
			_stop_animation()
		return
	
	_nav_agent.target_position = hero_pos
	var move_target := hero_pos
	if not _nav_agent.is_navigation_finished():
		var next_nav := _nav_agent.get_next_path_position()
		if _distance_xz(next_nav, enemy_pos) > 1.0:
			move_target = next_nav
	var next := _compute_next_move_with_obstacle_avoidance(enemy_pos, move_target, move_speed * delta)
	next.y = enemy_pos.y
	_enemy.global_position = next
	_look_at_target(move_target)
	
	if not _is_moving:
		_is_moving = true
		_play_walk_animation()


func _look_at_target(target_pos: Vector3) -> void:
	var direction = target_pos - _enemy.global_position
	direction.y = 0
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		_enemy.rotation.y = target_rotation - PI / 2.0


func _face_toward(target_pos: Vector3) -> void:
	var direction = target_pos - _enemy.global_position
	direction.y = 0
	if direction.length() > 0.01:
		_enemy.rotation.y = atan2(direction.x, direction.z) - PI / 2.0


func _start_attack() -> void:
	if _animation_player == null:
		return
	
	_is_attacking = true
	_attack_cooldown = _get_attack_interval()
	_current_attack_index = 0
	
	if not _animation_player.animation_finished.is_connected(_on_attack_finished):
		_animation_player.animation_finished.connect(_on_attack_finished)
	
	_play_current_attack_animation()


func _play_current_attack_animation() -> void:
	if _animation_player == null:
		return
	
	if _current_attack_index >= _attack_animations.size():
		return
	
	var anim_name = _attack_animations[_current_attack_index]
	
	if not _animation_player.has_animation(anim_name):
		push_warning("未找到攻击动画: " + anim_name)
		_current_attack_index += 1
		if _current_attack_index < _attack_animations.size():
			_play_current_attack_animation()
		else:
			_is_attacking = false
		return
	
	var anim = _animation_player.get_animation(anim_name)
	if anim != null:
		anim.loop_mode = Animation.LOOP_NONE
	
	_animation_player.play(anim_name, -1.0, _get_attack_speed_scale(), false)
	_try_apply_damage_to_hero()


func _play_walk_animation() -> void:
	if _animation_player != null and _animation_player.has_animation(walk_animation):
		if not _animation_player.is_playing() or _animation_player.current_animation != walk_animation:
			_animation_player.play(walk_animation, -1, 1.0, false)
			var anim = _animation_player.get_animation(walk_animation)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR


func _on_attack_finished(_anim_name: StringName) -> void:
	if _is_attacking:
		_current_attack_index += 1
		
		if _current_attack_index < _attack_animations.size():
			_play_current_attack_animation()
		else:
			_is_attacking = false
	if _pending_idle_after_animation:
		_pending_idle_after_animation = false
		_play_idle_animation()


func _stop_animation() -> void:
	if _animation_player == null:
		return
	_animation_player.stop()
	_play_idle_animation()


func _queue_idle_after_current_animation() -> void:
	if _animation_player == null:
		_play_idle_animation()
		return
	if not _animation_player.is_playing():
		_play_idle_animation()
		return
	var current_anim_name: StringName = _animation_player.current_animation
	if current_anim_name == StringName(idle_animation):
		return
	if current_anim_name == StringName(walk_animation):
		_play_idle_animation()
		return
	var current_anim: Animation = _animation_player.get_animation(current_anim_name)
	if current_anim != null and current_anim.loop_mode == Animation.LOOP_NONE:
		_pending_idle_after_animation = true
		return
	_play_idle_animation()


func _distance_xz(a: Vector3, b: Vector3) -> float:
	var delta := a - b
	delta.y = 0.0
	return delta.length()


func _is_obstacle_collider(collider: Node) -> bool:
	var cursor: Node = collider
	while cursor != null:
		if cursor.name == "Obstacles":
			return true
		cursor = cursor.get_parent()
	return false


func _is_move_segment_blocked(from_pos: Vector3, to_pos: Vector3, probe_half_width: float, probe_height: float) -> bool:
	var horizontal: Vector3 = to_pos - from_pos
	horizontal.y = 0.0
	if horizontal.length() <= 0.01:
		return false

	var right: Vector3 = horizontal.cross(Vector3.UP)
	if right.length() > 0.001:
		right = right.normalized() * probe_half_width
	else:
		right = Vector3.ZERO

	var offsets: Array[Vector3] = [Vector3.ZERO, right, -right]
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for offset in offsets:
		var start: Vector3 = from_pos + offset + Vector3(0.0, probe_height, 0.0)
		var finish: Vector3 = to_pos + offset + Vector3(0.0, probe_height, 0.0)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start, finish)
		query.collision_mask = OBSTACLE_RAY_MASK
		var hit: Dictionary = space_state.intersect_ray(query)
		if hit.is_empty() or not hit.has("collider"):
			continue
		var collider_node: Node = hit["collider"] as Node
		if collider_node != null and _is_obstacle_collider(collider_node):
			return true
	return false


func _compute_next_move_with_obstacle_avoidance(current: Vector3, move_target: Vector3, max_step: float) -> Vector3:
	var to_target: Vector3 = move_target - current
	to_target.y = 0.0
	if to_target.length() <= 0.01 or max_step <= 0.0:
		return current

	var step: float = minf(max_step, to_target.length())
	var forward_dir: Vector3 = to_target.normalized()
	var direct_next: Vector3 = current + forward_dir * step
	if not _is_move_segment_blocked(current, direct_next, 50.0, 42.0):
		return direct_next

	var best_next: Vector3 = current
	var best_score: float = -INF
	for angle_deg in OBSTACLE_STEER_ANGLES:
		var steer_dir: Vector3 = forward_dir.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var candidate_next: Vector3 = current + steer_dir * step
		if _is_move_segment_blocked(current, candidate_next, 50.0, 42.0):
			continue
		var remain: Vector3 = move_target - candidate_next
		remain.y = 0.0
		var score: float = -remain.length()
		if score > best_score:
			best_score = score
			best_next = candidate_next
	return best_next


func _find_nearest_hero(max_distance: float = INF) -> Node3D:
	var nearest: Node3D = null
	var nearest_distance := INF
	
	var candidates := get_tree().get_nodes_in_group(hero_group_name)
	for candidate in candidates:
		var hero := candidate as Node3D
		if hero == null:
			continue
		if not hero.visible:
			continue
		if _is_hero_dead(hero):
			continue
		
		var distance := _distance_xz(_enemy.global_position, hero.global_position)
		if distance > max_distance:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = hero
	
	if nearest != null:
		return nearest
	
	var fallback := get_node_or_null(hero_path) as Node3D
	if fallback != null and is_instance_valid(fallback) and fallback.visible and not _is_hero_dead(fallback):
		var fallback_distance := _distance_xz(_enemy.global_position, fallback.global_position)
		if fallback_distance <= max_distance:
			return fallback
	return null


func _try_apply_damage_to_hero() -> void:
	if _hero == null or not is_instance_valid(_hero):
		return
	if _is_hero_dead(_hero):
		return
	
	var distance := _distance_xz(_enemy.global_position, _hero.global_position)
	if distance > attack_range:
		return
	
	var hero_controller := _hero.get_parent()
	if hero_controller != null and hero_controller.has_method("apply_damage"):
		hero_controller.call("apply_damage", damage_per_hit, false, _enemy)
		if _is_hero_dead(_hero):
			_retarget_hero_after_kill()
		return
	var target_peer_id: int = _get_remote_target_peer_id(_hero)
	if target_peer_id > 0:
		var net_ctrl: Node = _get_network_session_controller()
		if net_ctrl != null and net_ctrl.has_method("request_damage_remote_hero"):
			net_ctrl.call("request_damage_remote_hero", target_peer_id, damage_per_hit, false)


func _retarget_hero_after_kill() -> void:
	var engage_range: float = attack_range * engage_range_multiplier
	_hero = _find_nearest_hero(engage_range)
	_target_lock_active = _hero != null
	if _hero != null:
		_is_engaged = true
		_chase_timer = 0.0
	else:
		_is_engaged = false
		_engage_timer = 0.0
		_chase_timer = 0.0


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
	if _is_hero_dead(attacker):
		return
	_hero = attacker
	_is_engaged = true
	_target_lock_active = true
	_engage_initialized = true
	_engage_timer = 0.0
	_chase_timer = 0.0
	if _is_casting_skill or _is_casting_skill2:
		_is_casting_skill = false
		_is_casting_skill2 = false
		_skill_cast_timer = 0.0
		_skill2_timer = 0.0
		_skill2_hit_applied = false
		_hide_skill_warning()
	if _is_attacking:
		_interrupt_attack_for_chase()
	_face_toward(attacker.global_position)


func is_dead() -> bool:
	return _is_dead


func _die() -> void:
	if _is_dead:
		return
	
	_is_dead = true
	_is_attacking = false
	_pending_idle_after_animation = false
	_is_moving = false
	_is_engaged = false
	_target_lock_active = false
	_is_casting_skill = false
	_is_casting_skill2 = false
	_hero = null
	_hide_skill_warning()
	
	if _animation_player != null:
		_animation_player.stop()
		if _animation_player.has_animation(death_animation):
			var anim = _animation_player.get_animation(death_animation)
			if anim != null:
				anim.loop_mode = Animation.LOOP_NONE
			_animation_player.play(death_animation, -1.0, 1.5, false)
			var death_duration := 0.1
			if anim != null:
				death_duration = maxf(anim.length / 1.5, 0.1)
			_schedule_finalize_death(death_duration)
		else:
			_animation_player.stop()
			_finalize_death()
	else:
		_finalize_death()


func _create_hp_bar() -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\nuniform float hp_ratio : hint_range(0.0, 1.0) = 1.0;\nvoid vertex() {\n\tMODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);\n\tMODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);\n}\nvoid fragment() {\n\tvec2 uv = UV;\n\tfloat bw = 0.04;\n\tfloat bh = 0.12;\n\tif (uv.x < bw || uv.x > 1.0 - bw || uv.y < bh || uv.y > 1.0 - bh) {\n\t\tALBEDO = vec3(0.0);\n\t\tALPHA = 0.9;\n\t} else {\n\t\tfloat ix = (uv.x - bw) / (1.0 - 2.0 * bw);\n\t\tif (ix <= hp_ratio) {\n\t\t\tALBEDO = vec3(1.0 - hp_ratio, hp_ratio, 0.0);\n\t\t\tALPHA = 0.9;\n\t\t} else {\n\t\t\tALBEDO = vec3(0.15);\n\t\t\tALPHA = 0.5;\n\t\t}\n\t}\n}\n"
	_hp_bar_material = ShaderMaterial.new()
	_hp_bar_material.shader = shader
	_hp_bar_material.set_shader_parameter("hp_ratio", 1.0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(hp_bar_width, 25.5)
	_hp_bar = MeshInstance3D.new()
	_hp_bar.mesh = mesh
	_hp_bar.material_override = _hp_bar_material
	_hp_bar.position = Vector3(0.0, hp_bar_height, 0.0)
	_enemy.add_child(_hp_bar)


func _update_hp_bar() -> void:
	if _hp_bar_material == null:
		return
	_hp_bar_material.set_shader_parameter("hp_ratio", float(_current_hp) / float(max_hp))


func _is_hero_dead(hero: Node3D) -> bool:
	var hero_controller := hero.get_parent()
	if hero_controller != null and hero_controller.has_method("is_dead"):
		return bool(hero_controller.call("is_dead"))
	return false


func _get_network_session_controller() -> Node:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("net_session_controller")


func _get_remote_target_peer_id(target: Node3D) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	if not target.has_meta("network_peer_id"):
		return 0
	var peer_variant: Variant = target.get_meta("network_peer_id")
	if peer_variant is int:
		return int(peer_variant)
	if peer_variant is String and String(peer_variant).is_valid_int():
		return int(String(peer_variant).to_int())
	return 0


func _get_attack_speed_scale() -> float:
	return maxf(attack_speed, 0.05)


func _get_attack_interval() -> float:
	return 1.0 / _get_attack_speed_scale()


func _start_skill() -> void:
	if _animation_player == null:
		return
	_is_casting_skill = true
	_is_attacking = false
	_skill_cast_timer = skill_cast_time
	if _animation_player.has_animation(skill_animation):
		var anim = _animation_player.get_animation(skill_animation)
		if anim != null:
			anim.loop_mode = Animation.LOOP_NONE
		var speed_scale := 1.0
		if anim != null and anim.length > 0.0:
			speed_scale = anim.length / skill_cast_time
		_animation_player.play(skill_animation, -1.0, speed_scale, false)
	_show_skill_warning()


func _finish_skill() -> void:
	_is_casting_skill = false
	_skill_cooldown = skill_cooldown_time
	_hide_skill_warning()
	
	if _hero != null and is_instance_valid(_hero) and not _is_hero_dead(_hero):
		var distance := _distance_xz(_enemy.global_position, _hero.global_position)
		var skill_range := attack_range * skill_range_multiplier
		if distance <= skill_range:
			var hero_controller := _hero.get_parent()
			if hero_controller != null and hero_controller.has_method("apply_damage"):
				hero_controller.call("apply_damage", skill_damage, false, _enemy)
	
	_stop_animation()
	_resume_target_after_skill()


func _start_skill2() -> void:
	if _animation_player == null:
		return
	_is_casting_skill2 = true
	_is_attacking = false
	_is_moving = false
	_skill2_hit_applied = false
	_skill2_timer = 0.0
	_skill2_total_time = skill2_cast_time
	
	_skill2_start_pos = _enemy.global_position
	var angle := _enemy.rotation.y + PI / 2.0
	var forward := Vector3(sin(angle), 0.0, cos(angle))
	if forward.length() < 0.01:
		forward = Vector3(0, 0, -1)
	var charge_distance := attack_range * skill2_distance_multiplier
	_skill2_end_pos = _skill2_start_pos + forward * charge_distance
	_skill2_end_pos.y = _skill2_start_pos.y
	
	if _animation_player.has_animation(skill2_animation):
		var anim = _animation_player.get_animation(skill2_animation)
		if anim != null:
			anim.loop_mode = Animation.LOOP_NONE
		var speed_scale := 1.0
		if anim != null and anim.length > 0.0:
			speed_scale = anim.length / skill2_cast_time
		_animation_player.play(skill2_animation, -1.0, speed_scale, false)


func _finish_skill2() -> void:
	_is_casting_skill2 = false
	_skill2_cooldown = skill2_cooldown_time
	_stop_animation()
	_resume_target_after_skill()


func _resume_target_after_skill() -> void:
	if _enemy == null:
		return
	if _hero == null or not is_instance_valid(_hero) or _is_hero_dead(_hero):
		var engage_range: float = attack_range * engage_range_multiplier
		_hero = _find_nearest_hero(engage_range)
		if _hero == null:
			if _is_moving:
				_is_moving = false
			_stop_animation()
			return

	var hero_pos: Vector3 = _hero.global_position
	var enemy_pos: Vector3 = _enemy.global_position
	var distance: float = _distance_xz(enemy_pos, hero_pos)
	var engage_range: float = attack_range * engage_range_multiplier

	_is_engaged = true
	_target_lock_active = true
	_chase_timer = 0.0
	_face_toward(hero_pos)

	if distance <= attack_range:
		_is_moving = false
		if _attack_cooldown <= 0.0:
			_start_attack()
		else:
			_play_idle_animation()
	elif distance <= engage_range:
		_nav_agent.target_position = hero_pos
		_is_moving = true
		_play_walk_animation()
	else:
		_is_moving = false
		_stop_animation()


func _show_skill_warning() -> void:
	if _skill_warning != null:
		return
	
	var skill_range := attack_range * skill_range_multiplier
	
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\nvoid fragment() {\n\tvec2 uv = UV * 2.0 - 1.0;\n\tfloat dist = length(uv);\n\tif (dist > 1.0) { discard; }\n\tif (dist > 0.96) {\n\t\tALBEDO = vec3(1.0, 0.0, 0.0);\n\t\tALPHA = 0.85;\n\t} else {\n\t\tALBEDO = vec3(1.0, 0.2, 0.2);\n\t\tALPHA = 0.25;\n\t}\n}\n"
	
	var mat := ShaderMaterial.new()
	mat.shader = shader
	
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(skill_range * 2.0, skill_range * 2.0)
	
	_skill_warning = MeshInstance3D.new()
	_skill_warning.mesh = mesh
	_skill_warning.material_override = mat
	_skill_warning.position = Vector3(_enemy.global_position.x, 1.0, _enemy.global_position.z)
	
	get_parent().add_child(_skill_warning)


func _hide_skill_warning() -> void:
	if _skill_warning != null and is_instance_valid(_skill_warning):
		_skill_warning.get_parent().remove_child(_skill_warning)
		_skill_warning.queue_free()
	_skill_warning = null


func _interrupt_attack_for_chase() -> void:
	if not _is_attacking:
		return
	
	_is_attacking = false
	_current_attack_index = 0
	if _animation_player != null and _animation_player.is_playing():
		_animation_player.stop()


func _schedule_finalize_death(delay_sec: float) -> void:
	var timer := get_tree().create_timer(maxf(delay_sec, 0.05))
	timer.timeout.connect(_finalize_death)


func _finalize_death() -> void:
	if _death_finalized:
		return
	_death_finalized = true
	
	if _hp_bar != null:
		_hp_bar.visible = false
	
	if _enemy != null:
		_enemy.visible = false


func set_network_authority(enabled: bool) -> void:
	network_authoritative = enabled
	if enabled:
		if _enemy != null and is_instance_valid(_enemy):
			_remote_target_position = _enemy.global_position
			_remote_target_yaw = _enemy.rotation.y
			_remote_velocity = Vector3.ZERO
			_remote_last_receive_ms = Time.get_ticks_msec()
			_remote_has_target = true
		return
	_is_moving = false
	_is_attacking = false
	_is_casting_skill = false
	_is_casting_skill2 = false
	_pending_idle_after_animation = false
	_hide_skill_warning()
	if _enemy != null and is_instance_valid(_enemy):
		_remote_target_position = _enemy.global_position
		_remote_target_yaw = _enemy.rotation.y
		_remote_velocity = Vector3.ZERO
		_remote_last_receive_ms = Time.get_ticks_msec()
		_remote_has_target = true


func export_network_state() -> Dictionary:
	var state: Dictionary = {}
	if _enemy != null and is_instance_valid(_enemy):
		state["pos"] = _enemy.global_position
		state["yaw"] = _enemy.rotation.y
		state["visible"] = _enemy.visible
	state["hp"] = _current_hp
	state["max_hp"] = max_hp
	state["dead"] = _is_dead
	state["is_moving"] = _is_moving
	state["is_attacking"] = _is_attacking
	state["casting_skill"] = _is_casting_skill
	state["casting_skill2"] = _is_casting_skill2
	var warning_visible: bool = _skill_warning != null and is_instance_valid(_skill_warning)
	state["skill_warning_visible"] = warning_visible
	if warning_visible:
		state["skill_warning_pos"] = _skill_warning.global_position
	if _animation_player != null:
		state["anim_name"] = String(_animation_player.current_animation)
		state["anim_playing"] = _animation_player.is_playing()
		state["anim_speed"] = _animation_player.speed_scale
	return state


func apply_network_state(state: Dictionary) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	var pos_variant: Variant = state.get("pos", _enemy.global_position)
	if pos_variant is Vector3:
		_on_remote_enemy_position_received(pos_variant)
	_on_remote_enemy_yaw_received(float(state.get("yaw", _enemy.rotation.y)))

	if state.has("max_hp"):
		max_hp = maxi(int(state["max_hp"]), 1)
	if state.has("hp"):
		_current_hp = clampi(int(state["hp"]), 0, maxi(max_hp, 1))
	if state.has("dead"):
		_is_dead = bool(state["dead"])
	if state.has("is_moving"):
		_is_moving = bool(state["is_moving"])
	if state.has("is_attacking"):
		_is_attacking = bool(state["is_attacking"])
	if state.has("casting_skill"):
		_is_casting_skill = bool(state["casting_skill"])
	if state.has("casting_skill2"):
		_is_casting_skill2 = bool(state["casting_skill2"])

	var visible_target: bool = not _is_dead
	if state.has("visible"):
		visible_target = bool(state["visible"])
	_enemy.visible = visible_target
	if _hp_bar != null:
		_hp_bar.visible = visible_target and not _is_dead
	var warning_visible: bool = bool(state.get("skill_warning_visible", false))
	if _is_dead:
		warning_visible = false
	if warning_visible:
		_show_skill_warning()
		var warning_pos_variant: Variant = state.get("skill_warning_pos", null)
		if warning_pos_variant is Vector3 and _skill_warning != null:
			_skill_warning.global_position = warning_pos_variant
	else:
		_hide_skill_warning()
	_update_hp_bar()
	_apply_network_animation_state(state)


func _apply_network_animation_state(state: Dictionary) -> void:
	if _animation_player == null:
		return
	var desired_anim: String = str(state.get("anim_name", "")).strip_edges()
	var should_play: bool = bool(state.get("anim_playing", true))
	var speed_scale: float = clampf(float(state.get("anim_speed", 1.0)), 0.05, 8.0)

	if desired_anim != "" and _animation_player.has_animation(desired_anim):
		if should_play:
			if not _animation_player.is_playing() or String(_animation_player.current_animation) != desired_anim:
				_animation_player.play(desired_anim)
			_animation_player.speed_scale = speed_scale
		elif _animation_player.is_playing():
			_animation_player.stop()
		return

	if _is_dead:
		if death_animation != "" and _animation_player.has_animation(death_animation):
			if String(_animation_player.current_animation) != death_animation:
				_animation_player.play(death_animation, -1.0, 1.0, false)
		return
	if _is_casting_skill2 and skill2_animation != "" and _animation_player.has_animation(skill2_animation):
		if String(_animation_player.current_animation) != skill2_animation:
			_animation_player.play(skill2_animation, -1.0, 1.0, false)
		return
	if _is_casting_skill and skill_animation != "" and _animation_player.has_animation(skill_animation):
		if String(_animation_player.current_animation) != skill_animation:
			_animation_player.play(skill_animation, -1.0, 1.0, false)
		return
	if _is_attacking and _attack_animations.size() > 0:
		var fallback_attack_anim: String = String(_attack_animations[0])
		if fallback_attack_anim != "" and _animation_player.has_animation(fallback_attack_anim):
			if String(_animation_player.current_animation) != fallback_attack_anim:
				_animation_player.play(fallback_attack_anim, -1.0, maxf(_get_attack_speed_scale(), 0.05), false)
			return
	if _is_moving:
		_play_walk_animation()
	else:
		_play_idle_animation()


func _on_remote_enemy_position_received(incoming_pos: Vector3) -> void:
	if network_authoritative:
		_enemy.global_position = incoming_pos
		return
	var now_ms: int = Time.get_ticks_msec()
	if _remote_has_target:
		var delta_sec: float = maxf(float(now_ms - _remote_last_receive_ms) * 0.001, 0.016)
		var delta_pos: Vector3 = incoming_pos - _remote_target_position
		delta_pos.y = 0.0
		_remote_velocity = delta_pos / delta_sec
	else:
		_remote_velocity = Vector3.ZERO
	_remote_target_position = incoming_pos
	_remote_last_receive_ms = now_ms
	_remote_has_target = true
	if _enemy.global_position.distance_to(incoming_pos) >= maxf(remote_sync_snap_distance, 1.0):
		_enemy.global_position = incoming_pos


func _on_remote_enemy_yaw_received(incoming_yaw: float) -> void:
	if network_authoritative:
		var rot: Vector3 = _enemy.rotation
		rot.y = incoming_yaw
		_enemy.rotation = rot
		return
	_remote_target_yaw = incoming_yaw


func _update_remote_sync_smoothing(delta: float) -> void:
	if _enemy == null or not is_instance_valid(_enemy):
		return
	if not _remote_has_target:
		return
	var safe_delta: float = maxf(delta, 0.0)
	if safe_delta <= 0.0:
		return
	var pos_alpha: float = 1.0 - exp(-maxf(remote_sync_position_smooth_speed, 0.01) * safe_delta)
	var rot_alpha: float = 1.0 - exp(-maxf(remote_sync_rotation_smooth_speed, 0.01) * safe_delta)
	var predicted_pos: Vector3 = _remote_target_position
	var predict_sec: float = maxf(remote_sync_prediction_sec, 0.0)
	if predict_sec > 0.0:
		var projected_vel: Vector3 = _remote_velocity
		projected_vel.y = 0.0
		predicted_pos += projected_vel * predict_sec
	predicted_pos.y = _remote_target_position.y
	_enemy.global_position = _enemy.global_position.lerp(predicted_pos, pos_alpha)
	var next_rot: Vector3 = _enemy.rotation
	next_rot.y = lerp_angle(next_rot.y, _remote_target_yaw, rot_alpha)
	_enemy.rotation = next_rot
