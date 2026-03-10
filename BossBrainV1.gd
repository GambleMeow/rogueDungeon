extends Node
class_name BossBrainV1

var boss_data: Dictionary = {}
var behavior_data: Dictionary = {}
var combat_state: Dictionary = {}

func setup(boss_info: Dictionary, behavior_info: Dictionary) -> void:
	boss_data = boss_info
	behavior_data = behavior_info

func tick(delta: float, state: Dictionary) -> Dictionary:
	combat_state = state
	var skills: Array = behavior_data.get("skills", [])
	var selected: Dictionary = {}
	for s in skills:
		if _can_cast_skill(s):
			selected = s
			break
	if selected.is_empty():
		return {"cast": false, "skillId": "", "target": "current_aggro"}
	return {
		"cast": true,
		"skillId": selected.get("skillId", ""),
		"target": selected.get("target", "current_aggro"),
		"trigger": selected.get("trigger", "combat_loop"),
		"cooldownHintSec": selected.get("cooldownHintSec", "unknown")
	}

func _can_cast_skill(skill: Dictionary) -> bool:
	var hp_ratio: float = float(combat_state.get("hpRatio", 1.0))
	var aggro_changed: bool = bool(combat_state.get("aggroChanged", false))
	var target_far: bool = bool(combat_state.get("targetIsFar", false))
	var in_round_end: bool = bool(combat_state.get("isRoundEnd", false))

	var trigger: String = str(skill.get("trigger", "combat_loop"))
	if in_round_end:
		return false
	if trigger == "aggro_changed_and_far":
		return aggro_changed and target_far
	if trigger == "anti_stuck":
		return bool(combat_state.get("stuckDetected", false))
	if trigger == "ultimate_cycle":
		return bool(combat_state.get("ultimateReady", false))
	if trigger == "reposition_event":
		return bool(combat_state.get("justRepositioned", false))
	if trigger == "on_hit_within_500":
		return bool(combat_state.get("wasHitWithin500", false))
	if trigger == "when_wind_or_fire_hit":
		return bool(combat_state.get("formSwapEvent", false))
	if trigger == "earth_form_cycle" or trigger == "fire_form_cycle" or trigger == "wind_form_cycle":
		return true
	if trigger == "combat_loop":
		return true
	return hp_ratio <= 1.0
