extends Node3D
class_name ModelSpawnHarnessV1

@export var runtime_bundle_path: String = "res://runtime_bundle_v1.json"
@export var preview_wave: int = 1
@export var preview_hero_ids: Array[int] = [1, 2, 3, 4, 5]
@export var hero_gap_x: float = 1.8
@export var hero_start_x: float = -5.0
@export var boss_spawn_x: float = 5.0
@export var spawn_height_y: float = 0.0

var runtime_loader: RuntimeDataLoaderV1
var _spawned_nodes: Array[Node3D] = []

func _ready() -> void:
	runtime_loader = RuntimeDataLoaderV1.new()
	if not runtime_loader.load_bundle(runtime_bundle_path):
		push_error("Runtime bundle load failed: %s" % runtime_bundle_path)
		return
	start_wave(preview_wave)

func clear_spawned() -> void:
	for n in _spawned_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_spawned_nodes.clear()

func start_wave(wave: int) -> void:
	if runtime_loader == null:
		return
	preview_wave = clampi(wave, 1, 21)
	clear_spawned()
	_spawn_heroes()
	_spawn_boss_for_wave(preview_wave)

func next_wave() -> void:
	start_wave(preview_wave + 1)

func prev_wave() -> void:
	start_wave(preview_wave - 1)

func _spawn_heroes() -> void:
	for i in range(preview_hero_ids.size()):
		var hero_id := int(preview_hero_ids[i])
		var hero_node := runtime_loader.instantiate_hero_model(hero_id)
		if hero_node == null:
			continue
		hero_node.position = Vector3(hero_start_x + float(i) * hero_gap_x, spawn_height_y, 0.0)
		add_child(hero_node)
		_spawned_nodes.append(hero_node)

func _spawn_boss_for_wave(wave: int) -> void:
	var boss_id := runtime_loader.get_wave_boss_id(wave)
	var boss_node := runtime_loader.instantiate_boss_model(boss_id)
	if boss_node != null:
		boss_node.position = Vector3(boss_spawn_x, spawn_height_y, 0.0)
		add_child(boss_node)
		_spawned_nodes.append(boss_node)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PERIOD:
			next_wave()
		elif event.keycode == KEY_COMMA:
			prev_wave()
