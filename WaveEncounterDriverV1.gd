extends Node3D
class_name WaveEncounterDriverV1

@export var runtime_bundle_path: String = "res://runtime_bundle_v1.json"
@export var current_wave: int = 1
@export var hero_lineup: Array[int] = [1, 2, 3, 4, 5]
@export var hero_gap_x: float = 1.8
@export var hero_start_x: float = -5.0
@export var boss_spawn_x: float = 5.0
@export var auto_simulate: bool = true
@export var tick_interval_sec: float = 0.35
@export var hero_base_hp: float = 120.0
@export var boss_base_hp: float = 1800.0
@export var hero_cast_damage: float = 42.0
@export var hero_idle_damage: float = 10.0
@export var boss_cast_damage: float = 55.0
@export var boss_idle_damage: float = 22.0
@export var auto_next_wave_on_win: bool = true
@export var max_tick_logs: int = 240
@export var auto_export_on_wave_end: bool = true
@export var replay_output_path: String = "user://battle_replay_godot_v1.json"
@export var tuning_override_path: String = "res://godot_tuning_overrides_v1.json"

var runtime_loader: RuntimeDataLoaderV1
var hero_brains: Array[HeroBrainV1] = []
var boss_brain: BossBrainV1 = null
var spawned_nodes: Array[Node3D] = []
var hero_hp: Array[float] = []
var boss_hp: float = 0.0
var tick_accum_sec: float = 0.0
var elapsed_sec: float = 0.0
var wave_active: bool = false
var last_tick_result: Dictionary = {}
var terrain_ctx: Dictionary = {}
var campaign_plan: Dictionary = {}
var tick_logs: Array[Dictionary] = []
var replay_waves: Array[Dictionary] = []
var hero_action_mul_map: Dictionary = {}
var boss_trigger_mul_map: Dictionary = {}
var hero_outgoing_mul: float = 1.0
var boss_incoming_mul: float = 1.0

func _ready() -> void:
	_init_default_multipliers()
	runtime_loader = RuntimeDataLoaderV1.new()
	if not runtime_loader.load_bundle(runtime_bundle_path):
		push_error("Runtime bundle load failed: %s" % runtime_bundle_path)
		return
	_load_tuning_overrides()
	start_wave(current_wave)

func start_wave(wave: int) -> void:
	if runtime_loader == null:
		return
	current_wave = clampi(wave, 1, 21)
	_clear_wave()
	_setup_hero_brains()
	_setup_boss_brain()
	_spawn_wave_models()
	_reset_combat_state()
	_refresh_wave_context()
	_log_wave_start()

func next_wave() -> void:
	start_wave(current_wave + 1)

func prev_wave() -> void:
	start_wave(current_wave - 1)

func tick_brains(delta: float, combat_state: Dictionary) -> Dictionary:
	var hero_actions: Array = []
	for b in hero_brains:
		hero_actions.append(b.tick(delta, combat_state))
	var boss_action: Dictionary = {}
	if boss_brain != null:
		boss_action = boss_brain.tick(delta, combat_state)
	return {
		"wave": current_wave,
		"heroActions": hero_actions,
		"bossAction": boss_action
	}

func _process(delta: float) -> void:
	if not auto_simulate:
		return
	if not wave_active:
		return
	tick_accum_sec += delta
	elapsed_sec += delta
	if tick_accum_sec < tick_interval_sec:
		return
	tick_accum_sec = 0.0
	_run_one_tick(tick_interval_sec)

func _setup_hero_brains() -> void:
	hero_brains.clear()
	for hero_id in hero_lineup:
		var hero_data := runtime_loader.get_hero(int(hero_id))
		if hero_data.is_empty():
			continue
		var brain := HeroBrainV1.new()
		brain.setup(hero_data)
		brain.bind_runtime_loader(runtime_loader)
		hero_brains.append(brain)

func _setup_boss_brain() -> void:
	var boss_id := runtime_loader.get_wave_boss_id(current_wave)
	var boss_data := runtime_loader.get_boss(boss_id)
	var behavior := runtime_loader.get_boss_behavior(boss_id)
	if boss_data.is_empty():
		boss_brain = null
		return
	boss_brain = BossBrainV1.new()
	boss_brain.setup(boss_data, behavior)
	boss_brain.bind_runtime_loader(runtime_loader)

func _spawn_wave_models() -> void:
	for i in range(hero_brains.size()):
		var hero_node := hero_brains[i].instantiate_model()
		if hero_node == null:
			continue
		hero_node.position = Vector3(hero_start_x + float(i) * hero_gap_x, 0.0, 0.0)
		add_child(hero_node)
		spawned_nodes.append(hero_node)
	if boss_brain != null:
		var boss_node := boss_brain.instantiate_model()
		if boss_node != null:
			boss_node.position = Vector3(boss_spawn_x, 0.0, 0.0)
			add_child(boss_node)
			spawned_nodes.append(boss_node)

func _clear_wave() -> void:
	for n in spawned_nodes:
		if is_instance_valid(n):
			n.queue_free()
	spawned_nodes.clear()
	wave_active = false

func _reset_combat_state() -> void:
	hero_hp.clear()
	for _i in range(hero_brains.size()):
		hero_hp.append(hero_base_hp)
	boss_hp = boss_base_hp + float(current_wave - 1) * 90.0
	elapsed_sec = 0.0
	tick_accum_sec = 0.0
	wave_active = true
	tick_logs.clear()

func _refresh_wave_context() -> void:
	terrain_ctx = runtime_loader.get_terrain_for_wave(current_wave)
	var boss_id := runtime_loader.get_wave_boss_id(current_wave)
	var terrain_id := str(terrain_ctx.get("terrainId", ""))
	campaign_plan = runtime_loader.get_campaign_wave_plan(current_wave, boss_id, terrain_id)

func _build_combat_state() -> Dictionary:
	var alive_count := 0
	var sum_ratio := 0.0
	for hp in hero_hp:
		if hp > 0.0:
			alive_count += 1
			sum_ratio += clampf(hp / max(hero_base_hp, 1.0), 0.0, 1.0)
	var team_hp_ratio := 0.0
	if alive_count > 0:
		team_hp_ratio = sum_ratio / float(alive_count)
	return {
		"hpRatio": team_hp_ratio,
		"enemyCountInRange": 1,
		"summonCount": 0,
		"isRoundEnd": false,
		"targetDistance": 2.0,
		"aggroChanged": false,
		"targetIsFar": false,
		"stuckDetected": false,
		"ultimateReady": true,
		"justRepositioned": false,
		"wasHitWithin500": false,
		"formSwapEvent": false,
		"bossHpRatio": clampf(boss_hp / max(boss_base_hp, 1.0), 0.0, 1.0),
		"terrainTags": terrain_ctx.get("instance", {}).get("tags", []),
		"terrainRule": terrain_ctx.get("rule", {}),
		"campaignPlan": campaign_plan
	}

func _run_one_tick(dt: float) -> void:
	var state := _build_combat_state()
	var result := tick_brains(dt, state)
	last_tick_result = result

	var hero_actions: Array = result.get("heroActions", [])
	var hero_dmg := 0.0
	for action in hero_actions:
		var casted := bool(action.get("cast", false))
		var base := hero_cast_damage if casted else hero_idle_damage
		hero_dmg += base * _hero_action_mul(action) * hero_outgoing_mul
	boss_hp -= hero_dmg

	var boss_action: Dictionary = result.get("bossAction", {})
	var boss_casted := bool(boss_action.get("cast", false))
	var incoming := (boss_cast_damage if boss_casted else boss_idle_damage) * _boss_action_mul(boss_action) * boss_incoming_mul
	var alive_idx: Array[int] = []
	for i in range(hero_hp.size()):
		if hero_hp[i] > 0.0:
			alive_idx.append(i)
	if not alive_idx.is_empty():
		var hit_idx: int = alive_idx[randi() % alive_idx.size()]
		hero_hp[hit_idx] = max(0.0, hero_hp[hit_idx] - incoming)

	_append_tick_log(hero_dmg, incoming, result)

	_check_wave_end()

func _hero_action_mul(action: Dictionary) -> float:
	var m := 1.0
	var action_id := str(action.get("actionId", ""))
	m *= float(hero_action_mul_map.get(action_id, 1.0))
	var terrain_boost: Dictionary = campaign_plan.get("terrainBoost", {})
	var wave_override: Dictionary = campaign_plan.get("waveOverride", {})
	m *= float(terrain_boost.get("damageMul", 1.0))
	m *= float(wave_override.get("damageMul", 1.0))
	return m

func _boss_action_mul(action: Dictionary) -> float:
	var m := 1.0
	var trigger := str(action.get("trigger", ""))
	m *= float(boss_trigger_mul_map.get(trigger, 1.0))
	var wave_override: Dictionary = campaign_plan.get("waveOverride", {})
	m *= float(wave_override.get("hpMul", 1.0))
	return m

func _init_default_multipliers() -> void:
	hero_action_mul_map = {
		"burst_or_execute": 1.30,
		"control_cast": 1.05,
		"defensive_window": 0.80,
		"mobility_reposition": 0.90,
		"primary_pattern": 1.12,
		"summon_maintenance": 0.95
	}
	boss_trigger_mul_map = {
		"ultimate_cycle": 1.35,
		"aggro_changed_and_far": 1.15,
		"anti_stuck": 0.85
	}
	hero_outgoing_mul = 1.0
	boss_incoming_mul = 1.0

func _load_tuning_overrides() -> void:
	if tuning_override_path == "":
		return
	if not FileAccess.file_exists(tuning_override_path):
		return
	var f := FileAccess.open(tuning_override_path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var hero_overrides: Dictionary = parsed.get("heroActionMul", {})
	for k in hero_overrides.keys():
		hero_action_mul_map[str(k)] = float(hero_overrides.get(k, 1.0))
	var boss_overrides: Dictionary = parsed.get("bossTriggerMul", {})
	for k in boss_overrides.keys():
		boss_trigger_mul_map[str(k)] = float(boss_overrides.get(k, 1.0))
	var scalar: Dictionary = parsed.get("scalar", {})
	hero_outgoing_mul = float(scalar.get("heroOutgoingMul", 1.0))
	boss_incoming_mul = float(scalar.get("bossIncomingMul", 1.0))

func _append_tick_log(hero_dmg: float, incoming: float, result: Dictionary) -> void:
	var row := {
		"wave": current_wave,
		"t": snapped(elapsed_sec, 0.01),
		"bossHp": snapped(max(boss_hp, 0.0), 0.01),
		"heroHp": hero_hp.duplicate(),
		"heroDamage": snapped(hero_dmg, 0.01),
		"bossDamage": snapped(incoming, 0.01),
		"bossAction": result.get("bossAction", {}),
		"heroActions": result.get("heroActions", [])
	}
	tick_logs.append(row)
	if tick_logs.size() > max_tick_logs:
		tick_logs.remove_at(0)

func get_tick_logs() -> Array[Dictionary]:
	return tick_logs

func export_replay_json(path: String = "") -> bool:
	var out_path := path if path != "" else replay_output_path
	var payload := {
		"meta": {
			"version": "1.0-godot-battle-replay-v1",
			"driver": "WaveEncounterDriverV1",
			"currentWave": current_wave
		},
		"config": {
			"heroLineup": hero_lineup,
			"tickIntervalSec": tick_interval_sec,
			"heroBaseHp": hero_base_hp,
			"bossBaseHp": boss_base_hp
		},
		"waves": replay_waves
	}
	var text := JSON.stringify(payload, "\t")
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("Replay export failed: %s" % out_path)
		return false
	f.store_string(text)
	f.close()
	print("Replay exported: %s waves=%d" % [out_path, replay_waves.size()])
	return true

func _append_wave_summary(result: String) -> void:
	var boss_id := runtime_loader.get_wave_boss_id(current_wave)
	var terrain_id := str(terrain_ctx.get("terrainId", ""))
	var hero_action_counts: Dictionary = {}
	var boss_skill_counts: Dictionary = {}
	for t in tick_logs:
		for a in t.get("heroActions", []):
			var action_id := str(a.get("actionId", "none"))
			hero_action_counts[action_id] = int(hero_action_counts.get(action_id, 0)) + 1
		var ba: Dictionary = t.get("bossAction", {})
		var skill_id := str(ba.get("skillId", "none"))
		boss_skill_counts[skill_id] = int(boss_skill_counts.get(skill_id, 0)) + 1
	var row := {
		"wave": current_wave,
		"bossId": boss_id,
		"terrainId": terrain_id,
		"result": result,
		"elapsedSec": snapped(elapsed_sec, 0.01),
		"bossHpEnd": snapped(max(boss_hp, 0.0), 0.01),
		"heroHpEnd": hero_hp.duplicate(),
		"heroActionCounts": hero_action_counts,
		"bossSkillCounts": boss_skill_counts,
		"ticks": tick_logs.duplicate(true)
	}
	replay_waves.append(row)
	if auto_export_on_wave_end:
		export_replay_json()

func _check_wave_end() -> void:
	if boss_hp <= 0.0:
		wave_active = false
		_append_wave_summary("win")
		print("[Wave %d] WIN elapsed=%.2fs" % [current_wave, elapsed_sec])
		if auto_next_wave_on_win:
			next_wave()
		return
	var team_alive := false
	for hp in hero_hp:
		if hp > 0.0:
			team_alive = true
			break
	if not team_alive:
		wave_active = false
		_append_wave_summary("lose")
		print("[Wave %d] LOSE elapsed=%.2fs" % [current_wave, elapsed_sec])

func _log_wave_start() -> void:
	var boss_id := runtime_loader.get_wave_boss_id(current_wave)
	var terrain_id := str(terrain_ctx.get("terrainId", ""))
	print("[Wave %d] START boss=%s terrain=%s heroes=%s" % [current_wave, boss_id, terrain_id, str(hero_lineup)])

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_PERIOD:
			next_wave()
		elif event.keycode == KEY_COMMA:
			prev_wave()
		elif event.keycode == KEY_F6:
			export_replay_json()
