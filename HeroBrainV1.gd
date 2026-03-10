extends Node
class_name HeroBrainV1

var hero_data: Dictionary = {}
var combat_state: Dictionary = {}
var runtime_loader: RuntimeDataLoaderV1 = null
var hero_id: int = -1

func setup(data: Dictionary) -> void:
	hero_data = data
	hero_id = int(hero_data.get("heroId", -1))

func bind_runtime_loader(loader: RuntimeDataLoaderV1) -> void:
	runtime_loader = loader

func get_model_path() -> String:
	if runtime_loader == null:
		return ""
	if hero_id <= 0:
		hero_id = int(hero_data.get("heroId", -1))
	if hero_id <= 0:
		return ""
	return runtime_loader.get_hero_gltf_path(hero_id)

func instantiate_model() -> Node3D:
	if runtime_loader == null:
		return null
	if hero_id <= 0:
		hero_id = int(hero_data.get("heroId", -1))
	if hero_id <= 0:
		return null
	return runtime_loader.instantiate_hero_model(hero_id)

func tick(delta: float, state: Dictionary) -> Dictionary:
	combat_state = state
	var actions: Array = hero_data.get("actionBindings", [])
	var selected: Dictionary = {}
	var best_score: float = -999999.0
	for action in actions:
		if _can_cast(action):
			var score := _score_action(action)
			if score > best_score:
				best_score = score
				selected = action
	if not selected.is_empty():
		return {
			"cast": true,
			"actionId": selected.get("actionId", ""),
			"skillSlot": selected.get("skillSlot", "PRIMARY"),
			"targeting": selected.get("targeting", {}),
			"castTiming": selected.get("castTiming", {}),
			"animationTag": selected.get("animationTag", "cast_primary")
		}
	return {"cast": false, "actionId": "", "skillSlot": "PRIMARY"}

func _can_cast(action: Dictionary) -> bool:
	var condition: Dictionary = action.get("condition", {})
	var hp_ratio: float = float(combat_state.get("hpRatio", 1.0))
	var enemy_count: int = int(combat_state.get("enemyCountInRange", 1))
	var summon_count: int = int(combat_state.get("summonCount", 0))
	var in_round_end: bool = bool(combat_state.get("isRoundEnd", false))
	var distance_to_target: float = float(combat_state.get("targetDistance", 0.0))

	if condition.has("phase"):
		var phase = str(condition.get("phase"))
		if phase == "round_end" and not in_round_end:
			return false
		if phase == "combat" and in_round_end:
			return false

	if condition.get("hpBelow") != null:
		if hp_ratio > float(condition.get("hpBelow")):
			return false

	if condition.get("enemyCountMin") != null:
		if enemy_count < int(condition.get("enemyCountMin")):
			return false

	if condition.get("requireSummonBelow") != null:
		if summon_count >= int(condition.get("requireSummonBelow")):
			return false

	if condition.get("targetDistance") != null:
		var dr: Dictionary = condition.get("targetDistance")
		var min_d = float(dr.get("min", 0.0))
		var max_d = float(dr.get("max", 99999.0))
		if distance_to_target < min_d or distance_to_target > max_d:
			return false

	if not _cooldown_ready(action):
		return false

	return true

func _cooldown_ready(action: Dictionary) -> bool:
	var cooldown: Dictionary = action.get("cooldown", {})
	var cooldown_type: String = str(cooldown.get("type", "unknown"))
	if cooldown_type == "round_end_only":
		return bool(combat_state.get("isRoundEnd", false))
	return true

func _score_action(action: Dictionary) -> float:
	var score: float = float(action.get("priority", 0))
	var action_id: String = str(action.get("actionId", ""))
	var role: String = str(action.get("role", ""))
	var terrain_tags: Array = combat_state.get("terrainTags", [])
	var terrain_rule: Dictionary = combat_state.get("terrainRule", {})
	var plan: Dictionary = combat_state.get("campaignPlan", {})
	var terrain_boost: Dictionary = plan.get("terrainBoost", {})
	var wave_override: Dictionary = plan.get("waveOverride", {})

	var deny_list: Array = terrain_rule.get("actionDenyList", [])
	if deny_list.has(action_id):
		return -999999.0

	var require_tag_map: Dictionary = terrain_rule.get("actionRequireTag", {})
	if require_tag_map.has(action_id):
		var required_tag: String = str(require_tag_map.get(action_id, ""))
		if not terrain_tags.has(required_tag):
			return -999999.0

	var delta_map: Dictionary = terrain_rule.get("actionPriorityDelta", {})
	if delta_map.has(action_id):
		score += float(delta_map.get(action_id, 0))

	if terrain_tags.has("random_reposition_pressure") and role == "mobility":
		score += 8.0
	if terrain_tags.has("circle_aoe_zone") and role == "survival":
		score += 8.0
	if terrain_tags.has("spread_requirement") and role == "board_control":
		score -= 5.0

	if float(terrain_boost.get("damageMul", 1.0)) > 1.0 and role == "burst":
		score += 3.0
	if int(wave_override.get("wave", -1)) >= 16 and (role == "survival" or role == "control"):
		score += 4.0
	return score
