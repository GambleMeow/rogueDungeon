extends Node
class_name RuntimeDataLoaderV1

var bundle: Dictionary = {}
var hero_by_id: Dictionary = {}
var boss_by_id: Dictionary = {}
var terrain_template_by_id: Dictionary = {}
var terrain_instance_by_id: Dictionary = {}
var terrain_rule_by_id: Dictionary = {}
var campaign_data: Dictionary = {}
var hero_model_binding_by_id: Dictionary = {}
var boss_model_binding_by_id: Dictionary = {}
var boss_behavior_by_id: Dictionary = {}
var ability_effect_binding_by_id: Dictionary = {}
var ability_texture_fallback_by_id: Dictionary = {}

func load_bundle(path: String = "res://runtime_bundle_v1.json") -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	bundle = parsed
	_index_bundle()
	return true

func _index_bundle() -> void:
	hero_by_id.clear()
	boss_by_id.clear()
	terrain_template_by_id.clear()
	terrain_instance_by_id.clear()
	terrain_rule_by_id.clear()
	hero_model_binding_by_id.clear()
	boss_model_binding_by_id.clear()
	boss_behavior_by_id.clear()
	ability_effect_binding_by_id.clear()
	ability_texture_fallback_by_id.clear()
	var runtime = bundle.get("runtime", {})
	var hero = runtime.get("hero", {})
	var boss = runtime.get("boss", {})
	var terrain = runtime.get("terrain", {})
	campaign_data = runtime.get("campaign", {})
	var entity_bindings = runtime.get("godotEntityBindings", {})
	var texture_fallback = runtime.get("godotTextureFallback", {})

	for h in hero.get("heroes", []):
		hero_by_id[h.get("heroId")] = h

	for b in boss.get("bosses", []):
		boss_by_id[b.get("id")] = b
	for bb in boss.get("bossBehavior21", []):
		boss_behavior_by_id[str(bb.get("bossId", ""))] = bb

	for t in terrain.get("templates", []):
		terrain_template_by_id[t.get("terrainId")] = t

	for i in terrain.get("instances", []):
		terrain_instance_by_id[i.get("terrainId")] = i

	for r in terrain.get("actionRules", []):
		terrain_rule_by_id[r.get("terrainId")] = r

	for h in entity_bindings.get("heroModelBindings", []):
		hero_model_binding_by_id[h.get("heroId")] = h

	for b in entity_bindings.get("bossModelBindings", []):
		boss_model_binding_by_id[b.get("bossId")] = b

	for a in entity_bindings.get("abilityEffectBindings", []):
		ability_effect_binding_by_id[str(a.get("abilityId"))] = a

	for f in texture_fallback.get("fallbackRows", []):
		var aid := str(f.get("abilityId", ""))
		if aid == "":
			continue
		if not ability_texture_fallback_by_id.has(aid):
			ability_texture_fallback_by_id[aid] = []
		ability_texture_fallback_by_id[aid].append(f)

func get_hero(hero_id: int) -> Dictionary:
	return hero_by_id.get(hero_id, {})

func get_boss(boss_id: String) -> Dictionary:
	return boss_by_id.get(boss_id, {})

func get_wave_boss_id(wave: int) -> String:
	var runtime = bundle.get("runtime", {})
	var boss = runtime.get("boss", {})
	for w in boss.get("waves", []):
		if int(w.get("wave", -1)) == wave:
			return str(w.get("bossId", ""))
	return ""

func get_terrain_for_wave(wave: int) -> Dictionary:
	var runtime = bundle.get("runtime", {})
	var terrain = runtime.get("terrain", {})
	for row in terrain.get("waves", []):
		if int(row.get("wave", -1)) == wave:
			var pool: Array = row.get("terrainPool", [])
			if pool.is_empty():
				break
			var idx: int = int(wave) % pool.size()
			var terrain_id: String = str(pool[idx])
			return {
				"terrainId": terrain_id,
				"template": terrain_template_by_id.get(terrain_id, {}),
				"instance": terrain_instance_by_id.get(terrain_id, {}),
				"rule": terrain_rule_by_id.get(terrain_id, {})
			}
	return {"terrainId": "", "template": {}, "instance": {}, "rule": {}}

func get_campaign_wave_plan(wave: int, boss_id: String, terrain_id: String) -> Dictionary:
	var plan := {
		"teamSelection": campaign_data.get("teamSelection", {}),
		"progression": campaign_data.get("progression", {}),
		"terrainBoost": {},
		"waveOverride": {},
		"bossOverride": {}
	}
	var terrain_map: Dictionary = campaign_data.get("terrainAdaptation", {})
	if terrain_map.has(terrain_id):
		plan["terrainBoost"] = terrain_map.get(terrain_id, {})
	for row in campaign_data.get("endgameWaveOverrides", []):
		if int(row.get("wave", -1)) == wave:
			plan["waveOverride"] = row
			break
	var boss_map: Dictionary = campaign_data.get("bossOverrides", {})
	if boss_map.has(boss_id):
		plan["bossOverride"] = boss_map.get(boss_id, {})
	return plan

func get_hero_model_binding(hero_id: int) -> Dictionary:
	return hero_model_binding_by_id.get(hero_id, {})

func get_boss_model_binding(boss_id: String) -> Dictionary:
	return boss_model_binding_by_id.get(boss_id, {})

func get_boss_behavior(boss_id: String) -> Dictionary:
	return boss_behavior_by_id.get(str(boss_id), {})

func _to_res_path(raw_path: String) -> String:
	var p := str(raw_path)
	if p == "":
		return ""
	if p.begins_with("res://"):
		return p
	var i := p.find("godot-assets/")
	if i >= 0:
		return "res://" + p.substr(i, p.length() - i)
	return ""

func get_hero_gltf_path(hero_id: int) -> String:
	var b := get_hero_model_binding(hero_id)
	var gltf_path := _to_res_path(str(b.get("gltfPath", "")))
	if gltf_path != "":
		return gltf_path
	return _to_res_path(str(b.get("modelPath", "")))

func get_boss_gltf_path(boss_id: String) -> String:
	var b := get_boss_model_binding(boss_id)
	var gltf_path := _to_res_path(str(b.get("gltfPath", "")))
	if gltf_path != "":
		return gltf_path
	return _to_res_path(str(b.get("modelPath", "")))

func instantiate_hero_model(hero_id: int) -> Node3D:
	var model_path := get_hero_gltf_path(hero_id)
	if model_path == "":
		return null
	var packed := load(model_path)
	if packed is PackedScene:
		var inst = packed.instantiate()
		if inst is Node3D:
			return inst
	return null

func instantiate_boss_model(boss_id: String) -> Node3D:
	var model_path := get_boss_gltf_path(boss_id)
	if model_path == "":
		return null
	var packed := load(model_path)
	if packed is PackedScene:
		var inst = packed.instantiate()
		if inst is Node3D:
			return inst
	return null

func get_ability_effect_binding(ability_id: String) -> Dictionary:
	return ability_effect_binding_by_id.get(str(ability_id), {})

func get_ability_texture_fallbacks(ability_id: String) -> Array:
	return ability_texture_fallback_by_id.get(str(ability_id), [])
