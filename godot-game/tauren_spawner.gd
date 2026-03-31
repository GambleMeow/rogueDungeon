extends Node3D

@export var unit_count: int = 10
@export var tauren_scene_path: String = "res://modles/Tauren.glb"
@export var fallback_tauren_scene: PackedScene = preload("res://modles/HeroTaurenChieftain.glb")
@export var unit_scale: Vector3 = Vector3.ONE
@export var spawn_radius: float = 520.0
@export var spawn_radius_jitter: float = 260.0
@export var spawn_height: float = 0.0
@export var min_spawn_distance: float = 220.0
@export var spawn_try_count: int = 24
@export var randomize_seed_on_ready: bool = true

const TAUREN_UNIT_SCENE: PackedScene = preload("res://tauren_unit.tscn")


func _ready() -> void:
	if randomize_seed_on_ready:
		randomize()

	var tauren_scene := _load_tauren_scene()
	if tauren_scene == null:
		push_warning("TaurenSpawner 无法加载小怪模型。")
		return

	_spawn_initial_units(tauren_scene)


func _load_tauren_scene() -> PackedScene:
	var loaded := load(tauren_scene_path) as PackedScene
	if loaded != null:
		return loaded
	if fallback_tauren_scene != null:
		push_warning("未找到 %s，已回退到 HeroTaurenChieftain.glb。" % tauren_scene_path)
	return fallback_tauren_scene


func _spawn_initial_units(model_scene: PackedScene) -> void:
	var count: int = maxi(unit_count, 0)
	var spawned_positions: Array[Vector3] = []
	for i in range(count):
		var unit := TAUREN_UNIT_SCENE.instantiate() as TaurenUnitAI
		if unit == null:
			continue

		var spawn_pos := _pick_spawn_position(spawned_positions)
		spawned_positions.append(spawn_pos)

		unit.setup_unit(model_scene, spawn_pos, unit_scale)
		add_child(unit)


func _pick_spawn_position(existing_positions: Array[Vector3]) -> Vector3:
	var min_radius: float = maxf(80.0, spawn_radius - spawn_radius_jitter)
	var max_radius: float = maxf(min_radius + 1.0, spawn_radius + spawn_radius_jitter)
	var result: Vector3 = global_position + Vector3(min_radius, spawn_height, 0.0)

	for _i in range(maxi(spawn_try_count, 1)):
		var angle := randf() * TAU
		var radius := randf_range(min_radius, max_radius)
		var candidate := global_position + Vector3(cos(angle) * radius, spawn_height, sin(angle) * radius)
		if _is_position_far_enough(candidate, existing_positions):
			return candidate
		result = candidate

	return result


func _is_position_far_enough(candidate: Vector3, existing_positions: Array[Vector3]) -> bool:
	for p in existing_positions:
		if candidate.distance_to(p) < min_spawn_distance:
			return false
	return true
