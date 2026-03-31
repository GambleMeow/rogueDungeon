extends Node3D

@export var hero_path: NodePath = NodePath("herowarden")
@export var move_speed: float = 200.0
@export var attack_range: float = 250.0
@export var engage_range: float = 900.0
@export var auto_attack_on_enemy_engage: bool = true
@export var enemy_group_name: StringName = &"enemy"
@export var max_hp: int = 800
@export var damage_per_hit: int = 20
@export var attack_speed: float = 2.0
@export var hero_level: int = 1
@export var primary_attribute: String = "敏捷"
@export var strength_base: int = 24
@export var agility_base: int = 12
@export var intelligence_base: int = 14
@export var strength_growth: float = 2.5
@export var agility_growth: float = 2.0
@export var intelligence_growth: float = 1.8
@export var base_hp_flat: int = 200
@export var base_mana_flat: int = 100
@export var base_damage_flat: int = 8
@export var base_armor_flat: float = 3.3
@export var base_attack_speed: float = 2.0
@export var base_physical_crit_chance: float = 0.0
@export var base_physical_crit_multiplier: float = 2.0
@export var base_spell_crit_chance: float = 0.0
@export var base_spell_crit_multiplier: float = 2.0
@export var base_hp_regen_flat: float = 0.0
@export var base_mana_regen_flat: float = 0.0
@export var base_cooldown_reduction_percent: float = 0.0
@export var death_animation: String = "Death_GLTF"
@export var hp_bar_height: float = 300.0
@export var hp_bar_width: float = 180.0
@export var attack_count_label_height_offset: float = 14.0
@export var attack_count_label_pixel_size: float = 0.0007
@export var attack_count_label_font_size: int = 64
@export var idle_animation: String = "Idle"
@export var walk_animation: String = "Run"
@export var attack_animation_1: String = "Attack - 1_GLTF"
@export var attack_animation_2: String = "Attack - 2_GLTF"
@export var attack_animation_3: String = "Attack - 3_GLTF"
@export var flash_max_distance: float = 2000.0
@export var flash_cooldown_time: float = 0.0
@export var flash_origin_damage_radius: float = 700.0
@export var flash_destination_damage_radius: float = 400.0
@export var flash_damage: int = 100
@export var haste_multiplier: float = 2.0
@export var haste_duration: float = 5.0
@export var haste_cooldown_time: float = 10.0
@export var poison_damage_per_second: int = 30
@export var poison_duration: float = 5.0
@export var poison_tick_interval: float = 1.0
@export var passive_transform_attack_count: int = 20
@export var transform_duration: float = 8.0
@export var transformed_attack_speed_multiplier: float = 2.0
@export var transformed_attack_animation_1: String = "Attack - 1_GLTF"
@export var transformed_attack_animation_2: String = "Attack - 2_GLTF"
@export var transformed_model_scene: PackedScene = preload("res://modles/SpiritOfVengeance.before_trim.glb")
@export var flash_effect_scene: PackedScene = preload("res://effects/HeroWarden/FanOfKnivesCaster/FanOfKnivesCaster.glb")
@export var move_confirmation_scene: PackedScene = preload("res://modles/Confirmation.glb")
@export var move_confirmation_scale: Vector3 = Vector3.ONE
@export var move_confirmation_lifetime: float = 2.0
@export var cursor_default_texture: Texture2D = preload("res://icons/passives/frame_00_r0c0.png")
@export var cursor_enemy_texture: Texture2D = preload("res://icons/passives/frame_24_r3c0_red_variant.png")
@export var cursor_attack_default_texture: Texture2D = preload("res://icons/passives/frame_19_r2c3.png")
@export var cursor_attack_enemy_texture: Texture2D = preload("res://icons/passives/frame_23_r2c7_red_variant.png")
@export var cursor_hotspot: Vector2 = Vector2.ZERO
@export var melee_skill_q_name: String = "闪现"
@export var melee_skill_w_name: String = "急速"
@export var melee_skill_passive_name: String = "恶灵变身"
@export var ranged_skill_q_name: String = "战术翻滚"
@export var ranged_skill_w_name: String = "火力全开"
@export var ranged_skill_passive_name: String = "连射"
@export var ranged_attack_range: float = 1600.0
@export var ranged_flash_max_distance: float = 1400.0
@export var ranged_flash_cooldown_time: float = 6.0
@export var ranged_flash_damage: int = 120
@export var ranged_haste_multiplier: float = 2.4
@export var ranged_haste_duration: float = 2.0
@export var ranged_haste_cooldown_time: float = 8.0
@export var ranged_haste_move_speed_bonus: float = 600.0
@export var ranged_haste_walk_anim_speed_multiplier: float = 3.0
@export var ranged_poison_damage_per_second: int = 20
@export var ranged_poison_duration: float = 4.0
@export var ranged_poison_tick_interval: float = 0.5
@export var ranged_passive_transform_attack_count: int = 16
@export var ranged_idle_animation: String = "Stand_GLTF"
@export var ranged_walk_animation: String = "Walk_GLTF"
@export var ranged_death_animation: String = "Death_GLTF"
@export var ranged_attack_animation_1: String = "Attack_GLTF"
@export var ranged_attack_animation_2: String = ""
@export var ranged_attack_animation_3: String = ""
@export var ranged_model_scale_multiplier: float = 1.6666667
@export var ranged_q_ray_length: float = 3000.0
@export var ranged_q_ray_damage: int = 100
@export var ranged_q_ray_hit_radius: float = 100.0
@export var ranged_q_backstep_distance: float = 200.0
@export var ranged_q_backstep_duration: float = 0.28
@export var ranged_q_ray_width: float = 24.0
@export var ranged_q_ray_thickness: float = 8.0
@export var ranged_q_ray_height_offset: float = 80.0
@export var ranged_q_ray_lifetime: float = 0.2
@export var dynamic_detour_enabled: bool = true
@export var dynamic_detour_duration_sec: float = 0.45
@export var dynamic_detour_side_strength: float = 0.95
@export var dynamic_blocker_avoid_radius: float = 88.0

var _hero: Node3D
var _animation_player: AnimationPlayer
var _target_position: Vector3
var _target_enemy: Node3D = null
var _plane_height: float = 0.0
var _has_move_target: bool = false
var _is_moving: bool = false
var _is_attacking: bool = false
var _attack_mode: bool = false
var _focus_lock: bool = false
var _current_attack_index: int = 0
var _attack_animations: Array[String] = []
var _auto_aggro_initialized: bool = false
var _was_in_enemy_engage_range: bool = false
var _last_auto_enemy: Node3D = null
var _attack_cooldown: float = 0.0
var _current_hp: int = 0
var _is_dead: bool = false
var _hp_bar: MeshInstance3D
var _attack_count_label: Label3D
var _hp_bar_material: ShaderMaterial
var _death_finalized: bool = false
var _flash_mode: bool = false
var _flash_cooldown: float = 0.0
var _haste_active: bool = false
var _haste_time_left: float = 0.0
var _haste_cooldown: float = 0.0
var _poison_targets: Dictionary = {}
var _attack_count: int = 0
var _is_transformed: bool = false
var _transform_time_left: float = 0.0
var _original_hero: Node3D = null
var _transformed_hero: Node3D = null
var strength: int = 0
var agility: int = 0
var intelligence: int = 0
var armor: float = 0.0
var max_mana: int = 0
var current_mana: int = 0
var hp_regen_per_second: float = 0.0
var mana_regen_per_second: float = 0.0
var attack_interval: float = 0.0
var attack_speed_percent_total: float = 0.0
var cooldown_reduction_percent_total: float = 0.0
var physical_crit_chance: float = 0.0
var physical_crit_multiplier: float = 2.0
var spell_crit_chance: float = 0.0
var spell_crit_multiplier: float = 2.0
var _equip_strength_bonus: int = 0
var _equip_agility_bonus: int = 0
var _equip_intelligence_bonus: int = 0
var _equip_hp_bonus: int = 0
var _equip_mana_bonus: int = 0
var _equip_damage_bonus: int = 0
var _equip_armor_bonus: float = 0.0
var _equip_attack_speed_percent_bonus: float = 0.0
var _equip_move_speed_bonus: float = 0.0
var _equip_cooldown_reduction_percent_bonus: float = 0.0
var _equip_physical_crit_chance_bonus: float = 0.0
var _equip_physical_crit_multiplier_bonus: float = 0.0
var _equip_spell_crit_chance_bonus: float = 0.0
var _equip_spell_crit_multiplier_bonus: float = 0.0
var _base_move_speed: float = -1.0
var _hp_regen_pool: float = 0.0
var _mana_regen_pool: float = 0.0
var _slow_percent: float = 0.0
var _slow_time_left: float = 0.0
var _last_stat_level: int = -1
var _nav_agent: NavigationAgent3D
var shop_clicked: bool = false
var inventory: Array = []
var _using_enemy_cursor: bool = false
var _using_attack_cursor: bool = false
var _using_selected_cursor: bool = false
var _cursor_initialized: bool = false
var _destroy_cursor_mode: bool = false
var _destroy_hover_item: bool = false
var hero_id: int = 1
var hero_profile: String = "近战"
var skill_q_id: int = 101
var skill_q_name: String = "闪现"
var skill_w_id: int = 102
var skill_w_name: String = "急速"
var skill_passive_id: int = 103
var skill_passive_name: String = "恶灵变身"
var _melee_profile_cache: Dictionary = {}
var _ranged_q_backstep_tween: Tween
var _ranged_q_backstep_active: bool = false
var _ranged_q_backstep_time_left: float = 0.0
var _ranged_q_backstep_total_time: float = 0.0
var _ranged_q_backstep_start_pos: Vector3 = Vector3.ZERO
var _ranged_q_backstep_end_pos: Vector3 = Vector3.ZERO
var _resolved_idle_animation: String = ""
var _resolved_walk_animation: String = ""
var _resolved_death_animation: String = ""
var _network_skill_event_seq: int = 0
var _network_last_skill_event: Dictionary = {}
var _dynamic_detour_time_left: float = 0.0
var _dynamic_detour_side: float = 1.0

const STR_HP_PER_POINT: int = 25
const INT_MANA_PER_POINT: int = 15
const AGI_ARMOR_PER_POINT: float = 0.14
const AGI_ATTACK_SPEED_PER_POINT: float = 0.01
const STR_HP_REGEN_PER_POINT: float = 0.05
const INT_MANA_REGEN_PER_POINT: float = 0.05
const WC3_MIN_MOVE_SPEED: float = 100.0
const WC3_MAX_MOVE_SPEED: float = 522.0
const WC3_IAS_MIN: float = -80.0
const WC3_IAS_MAX: float = 400.0
const MAX_COOLDOWN_REDUCTION_PERCENT: float = 80.0
const HERO_ID_MELEE: int = 1
const HERO_ID_RANGED: int = 2
const SKILL_ID_Q_FLASH: int = 101
const SKILL_ID_W_HASTE: int = 102
const SKILL_ID_PASSIVE_TRANSFORM: int = 103
const SKILL_ID_Q_RANGED_SHOT: int = 201
const SKILL_ID_W_RANGED_SPEED: int = 202
const SKILL_ID_PASSIVE_RANGED: int = 203
const INTERACTION_RAY_MASK: int = (1 << 0) | (1 << 1)
const OBSTACLE_RAY_MASK: int = 1 << 0
const OBSTACLE_STEER_ANGLES := [20.0, -20.0, 40.0, -40.0, 60.0, -60.0, 80.0, -80.0, 100.0, -100.0]


func _ready() -> void:
	_hero = get_node_or_null(hero_path) as Node3D
	if _hero == null:
		push_warning("hero_path 未指向有效的 Node3D。")
		set_process(false)
		return

	_target_position = _hero.global_position
	_plane_height = _hero.global_position.y
	_base_move_speed = move_speed
	_cache_melee_profile()
	apply_hero_profile("近战")
	var initial_rotation := _hero.rotation
	initial_rotation.z = 0.0
	_hero.rotation = initial_rotation
	
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 20.0
	_nav_agent.target_desired_distance = 20.0
	_hero.add_child(_nav_agent)
	
	_animation_player = _hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player == null:
		push_warning("未在英雄中找到 AnimationPlayer 节点。")
	_refresh_motion_animation_aliases()
	
	_recalculate_war3_stats(true)
	_refresh_attack_animations()
	_create_hp_bar()
	_update_hp_bar()
	_play_idle_animation()
	_apply_mouse_cursor(false, false, false)


func _exit_tree() -> void:
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


func _refresh_motion_animation_aliases() -> void:
	_resolved_idle_animation = _resolve_motion_animation(idle_animation, ["stand", "idle", "wait"])
	_resolved_walk_animation = _resolve_motion_animation(walk_animation, ["walk", "run", "move", "locomotion", "go"])
	_resolved_death_animation = _resolve_motion_animation(death_animation, ["death", "die"])


func _resolve_motion_animation(preferred: String, keywords: Array[String]) -> String:
	if _animation_player == null:
		return ""
	if preferred != "" and _animation_player.has_animation(preferred):
		return preferred
	var anim_list: PackedStringArray = _animation_player.get_animation_list()
	for anim_name_sn in anim_list:
		var anim_name: String = String(anim_name_sn)
		var lower_name: String = anim_name.to_lower()
		for kw in keywords:
			if lower_name.find(kw) >= 0:
				return anim_name
	return ""


func _play_idle_animation() -> void:
	if _animation_player == null:
		return
	if _resolved_idle_animation == "":
		_refresh_motion_animation_aliases()
	if _resolved_idle_animation == "":
		return
	if _animation_player.is_playing() and String(_animation_player.current_animation) == _resolved_idle_animation:
		return
	_animation_player.speed_scale = 1.0
	var anim = _animation_player.get_animation(_resolved_idle_animation)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR
	_animation_player.play(_resolved_idle_animation)


func _get_primary_attr_value() -> int:
	match primary_attribute:
		"力量":
			return strength
		"智力":
			return intelligence
		_:
			return agility


func _recalculate_war3_stats(reset_hp_mp: bool) -> void:
	var lv: int = maxi(hero_level, 1)
	hero_level = lv
	_last_stat_level = lv
	strength = int(round(strength_base + strength_growth * float(lv - 1))) + _equip_strength_bonus
	agility = int(round(agility_base + agility_growth * float(lv - 1))) + _equip_agility_bonus
	intelligence = int(round(intelligence_base + intelligence_growth * float(lv - 1))) + _equip_intelligence_bonus
	max_hp = base_hp_flat + _equip_hp_bonus + strength * STR_HP_PER_POINT
	max_mana = base_mana_flat + _equip_mana_bonus + intelligence * INT_MANA_PER_POINT
	damage_per_hit = base_damage_flat + _equip_damage_bonus + _get_primary_attr_value()
	armor = base_armor_flat + _equip_armor_bonus + float(agility) * AGI_ARMOR_PER_POINT
	physical_crit_chance = clampf(base_physical_crit_chance + _equip_physical_crit_chance_bonus, 0.0, 100.0)
	physical_crit_multiplier = maxf(base_physical_crit_multiplier + _equip_physical_crit_multiplier_bonus * 0.01, 1.0)
	spell_crit_chance = clampf(base_spell_crit_chance + _equip_spell_crit_chance_bonus, 0.0, 100.0)
	spell_crit_multiplier = maxf(base_spell_crit_multiplier + _equip_spell_crit_multiplier_bonus * 0.01, 1.0)
	cooldown_reduction_percent_total = _get_effective_cooldown_reduction_percent()
	hp_regen_per_second = base_hp_regen_flat + float(strength) * STR_HP_REGEN_PER_POINT
	mana_regen_per_second = base_mana_regen_flat + float(intelligence) * INT_MANA_REGEN_PER_POINT
	if _base_move_speed <= 0.0:
		_base_move_speed = move_speed
	move_speed = clampf(_base_move_speed + _equip_move_speed_bonus, WC3_MIN_MOVE_SPEED, WC3_MAX_MOVE_SPEED)
	_refresh_runtime_combat_stats()
	if reset_hp_mp:
		_current_hp = max_hp
		current_mana = max_mana
	else:
		_current_hp = clampi(_current_hp, 0, max_hp)
		current_mana = clampi(current_mana, 0, max_mana)


func apply_equipment_bonuses(bonuses: Dictionary) -> void:
	_equip_strength_bonus = int(bonuses.get("strength", 0))
	_equip_agility_bonus = int(bonuses.get("agility", 0))
	_equip_intelligence_bonus = int(bonuses.get("intelligence", 0))
	_equip_hp_bonus = int(bonuses.get("hp", 0))
	_equip_mana_bonus = int(bonuses.get("mana", 0))
	_equip_damage_bonus = int(bonuses.get("damage", 0))
	_equip_armor_bonus = float(bonuses.get("armor", 0.0))
	_equip_attack_speed_percent_bonus = float(bonuses.get("attack_speed_percent", 0.0))
	_equip_move_speed_bonus = float(bonuses.get("move_speed", 0.0))
	_equip_cooldown_reduction_percent_bonus = float(bonuses.get("cooldown_reduction_percent", 0.0))
	_equip_physical_crit_chance_bonus = float(bonuses.get("physical_crit_chance", 0.0))
	_equip_physical_crit_multiplier_bonus = float(bonuses.get("physical_crit_multiplier", 0.0))
	_equip_spell_crit_chance_bonus = float(bonuses.get("spell_crit_chance", 0.0))
	_equip_spell_crit_multiplier_bonus = float(bonuses.get("spell_crit_multiplier", 0.0))
	_recalculate_war3_stats(false)
	_update_hp_bar()


func _cache_melee_profile() -> void:
	if not _melee_profile_cache.is_empty():
		return
	_melee_profile_cache = {
		"attack_range": attack_range,
		"flash_max_distance": flash_max_distance,
		"flash_cooldown_time": flash_cooldown_time,
		"flash_damage": flash_damage,
		"haste_multiplier": haste_multiplier,
		"haste_duration": haste_duration,
		"haste_cooldown_time": haste_cooldown_time,
		"poison_damage_per_second": poison_damage_per_second,
		"poison_duration": poison_duration,
		"poison_tick_interval": poison_tick_interval,
		"passive_transform_attack_count": passive_transform_attack_count,
		"idle_animation": idle_animation,
		"walk_animation": walk_animation,
		"death_animation": death_animation,
		"attack_animation_1": attack_animation_1,
		"attack_animation_2": attack_animation_2,
		"attack_animation_3": attack_animation_3
	}


func _apply_profile_values(values: Dictionary) -> void:
	attack_range = float(values.get("attack_range", attack_range))
	flash_max_distance = float(values.get("flash_max_distance", flash_max_distance))
	flash_cooldown_time = float(values.get("flash_cooldown_time", flash_cooldown_time))
	flash_damage = int(values.get("flash_damage", flash_damage))
	haste_multiplier = float(values.get("haste_multiplier", haste_multiplier))
	haste_duration = float(values.get("haste_duration", haste_duration))
	haste_cooldown_time = float(values.get("haste_cooldown_time", haste_cooldown_time))
	poison_damage_per_second = int(values.get("poison_damage_per_second", poison_damage_per_second))
	poison_duration = float(values.get("poison_duration", poison_duration))
	poison_tick_interval = float(values.get("poison_tick_interval", poison_tick_interval))
	passive_transform_attack_count = int(values.get("passive_transform_attack_count", passive_transform_attack_count))
	idle_animation = str(values.get("idle_animation", idle_animation))
	walk_animation = str(values.get("walk_animation", walk_animation))
	death_animation = str(values.get("death_animation", death_animation))
	attack_animation_1 = str(values.get("attack_animation_1", attack_animation_1))
	attack_animation_2 = str(values.get("attack_animation_2", attack_animation_2))
	attack_animation_3 = str(values.get("attack_animation_3", attack_animation_3))


func _is_ranged_hero() -> bool:
	return hero_id == HERO_ID_RANGED


func _uses_transform_passive() -> bool:
	return skill_passive_id == SKILL_ID_PASSIVE_TRANSFORM


func get_skill_binding_ids() -> Dictionary:
	return {
		"hero_id": hero_id,
		"skill_q_id": skill_q_id,
		"skill_w_id": skill_w_id,
		"skill_passive_id": skill_passive_id
	}


func _should_show_attack_count_label() -> bool:
	return hero_id == HERO_ID_MELEE


func apply_hero_profile_by_id(target_hero_id: int) -> void:
	if target_hero_id == HERO_ID_RANGED:
		apply_hero_profile("远程")
		return
	apply_hero_profile("近战")


func apply_hero_profile(profile_name: String) -> void:
	_cache_melee_profile()
	if profile_name == "远程":
		hero_id = HERO_ID_RANGED
		hero_profile = "远程"
		skill_q_id = SKILL_ID_Q_RANGED_SHOT
		skill_q_name = ranged_skill_q_name
		skill_w_id = SKILL_ID_W_RANGED_SPEED
		skill_w_name = ranged_skill_w_name
		skill_passive_id = SKILL_ID_PASSIVE_RANGED
		skill_passive_name = ranged_skill_passive_name
		_apply_profile_values({
			"attack_range": ranged_attack_range,
			"flash_max_distance": ranged_flash_max_distance,
			"flash_cooldown_time": ranged_flash_cooldown_time,
			"flash_damage": ranged_flash_damage,
			"haste_multiplier": ranged_haste_multiplier,
			"haste_duration": ranged_haste_duration,
			"haste_cooldown_time": ranged_haste_cooldown_time,
			"poison_damage_per_second": ranged_poison_damage_per_second,
			"poison_duration": ranged_poison_duration,
			"poison_tick_interval": ranged_poison_tick_interval,
			"passive_transform_attack_count": ranged_passive_transform_attack_count,
			"idle_animation": ranged_idle_animation,
			"walk_animation": ranged_walk_animation,
			"death_animation": ranged_death_animation,
			"attack_animation_1": ranged_attack_animation_1,
			"attack_animation_2": ranged_attack_animation_2,
			"attack_animation_3": ranged_attack_animation_3
		})
	else:
		hero_id = HERO_ID_MELEE
		hero_profile = "近战"
		skill_q_id = SKILL_ID_Q_FLASH
		skill_q_name = melee_skill_q_name
		skill_w_id = SKILL_ID_W_HASTE
		skill_w_name = melee_skill_w_name
		skill_passive_id = SKILL_ID_PASSIVE_TRANSFORM
		skill_passive_name = melee_skill_passive_name
		_apply_profile_values(_melee_profile_cache)

	_poison_targets.clear()
	_haste_active = false
	_haste_time_left = 0.0
	_refresh_motion_animation_aliases()
	_refresh_attack_animations()
	_update_attack_count_label()
	_play_idle_animation()


func select_hero_model(model_scene: PackedScene, hero_name: String = "SelectedHero") -> void:
	if model_scene == null:
		return
	if _is_transformed:
		_revert_transform_model()
	if _hero == null or not is_instance_valid(_hero):
		return

	var old_hero: Node3D = _hero
	var parent_node: Node = old_hero.get_parent()
	if parent_node == null:
		return

	var new_hero: Node3D = model_scene.instantiate() as Node3D
	if new_hero == null:
		return

	var old_transform: Transform3D = old_hero.global_transform
	var old_scale: Vector3 = old_hero.scale
	var old_rotation: Vector3 = old_hero.rotation

	if _animation_player != null and _animation_player.is_playing():
		_animation_player.stop()
	_is_attacking = false
	_is_moving = false
	_has_move_target = false
	_focus_lock = false
	_target_enemy = null
	_ranged_q_backstep_active = false
	_ranged_q_backstep_time_left = 0.0
	_ranged_q_backstep_total_time = 0.0
	_current_attack_index = 0

	new_hero.name = hero_name
	parent_node.add_child(new_hero)
	new_hero.global_transform = old_transform
	if _is_ranged_hero():
		new_hero.scale = old_scale * maxf(ranged_model_scale_multiplier, 0.01)
	else:
		new_hero.scale = old_scale
	new_hero.rotation = old_rotation
	var fixed_rotation: Vector3 = new_hero.rotation
	fixed_rotation.z = 0.0
	new_hero.rotation = fixed_rotation

	if _nav_agent != null and _nav_agent.get_parent() != null:
		_nav_agent.reparent(new_hero)
	if _hp_bar != null and _hp_bar.get_parent() != null:
		_hp_bar.reparent(new_hero)
		_hp_bar.position = Vector3(0.0, hp_bar_height, 0.0)
	if _attack_count_label != null and _attack_count_label.get_parent() != null:
		_attack_count_label.reparent(new_hero)
		_attack_count_label.position = Vector3(0.0, hp_bar_height + attack_count_label_height_offset, 0.0)

	var old_collision_body := old_hero.get_node_or_null("CollisionBody") as Node3D
	if old_collision_body != null and old_collision_body.get_parent() != null:
		old_collision_body.reparent(new_hero)
	_ensure_hero_collision_body(new_hero)

	if old_hero.is_in_group("hero"):
		old_hero.remove_from_group("hero")
	new_hero.add_to_group("hero")
	old_hero.queue_free()

	_hero = new_hero
	_original_hero = _hero
	_transformed_hero = null
	_is_transformed = false
	_transform_time_left = 0.0
	_target_position = _hero.global_position
	_plane_height = _hero.global_position.y
	_animation_player = _hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_refresh_motion_animation_aliases()
	_refresh_attack_animations()
	_play_idle_animation()


func _ensure_hero_collision_body(target_hero: Node3D) -> void:
	if target_hero == null:
		return
	var collision_body := target_hero.get_node_or_null("CollisionBody") as StaticBody3D
	if collision_body == null:
		collision_body = StaticBody3D.new()
		collision_body.name = "CollisionBody"
		target_hero.add_child(collision_body)
	var collision_shape := collision_body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		collision_shape = CollisionShape3D.new()
		collision_shape.name = "CollisionShape3D"
		collision_body.add_child(collision_shape)
	var capsule := collision_shape.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		capsule.radius = 50.0
		capsule.height = 150.0
		collision_shape.shape = capsule
	collision_shape.position = Vector3(0.0, 75.0, 0.0)


func set_destroy_cursor_mode(enabled: bool) -> void:
	_destroy_cursor_mode = enabled
	if not enabled:
		_destroy_hover_item = false
	_update_mouse_cursor_icon()


func set_destroy_cursor_item_hover(enabled: bool) -> void:
	_destroy_hover_item = enabled and _destroy_cursor_mode
	_update_mouse_cursor_icon()


func apply_temporary_slow(slow_percent: float, duration: float) -> void:
	if _is_dead:
		return
	if duration <= 0.0:
		return
	var clamped_percent: float = clampf(slow_percent, 0.0, 95.0)
	if clamped_percent <= 0.0:
		return
	_slow_percent = clamped_percent
	_slow_time_left = maxf(duration, 0.01)


func _refresh_runtime_combat_stats() -> void:
	attack_speed = _get_attack_speed_scale()
	attack_interval = _get_attack_interval()


func _get_current_move_speed() -> float:
	var current_speed: float = move_speed
	if _haste_active and skill_w_id == SKILL_ID_W_RANGED_SPEED:
		var duration: float = maxf(haste_duration, 0.01)
		var ratio: float = clampf(_haste_time_left / duration, 0.0, 1.0)
		current_speed += ranged_haste_move_speed_bonus * ratio
	if _slow_time_left > 0.0 and _slow_percent > 0.0:
		current_speed *= maxf(1.0 - _slow_percent * 0.01, 0.0)
	return maxf(current_speed, 1.0)


func _apply_regeneration(delta: float) -> void:
	if _is_dead:
		return
	if hp_regen_per_second > 0.0 and _current_hp < max_hp:
		_hp_regen_pool += hp_regen_per_second * delta
		var hp_gain: int = int(floor(_hp_regen_pool))
		if hp_gain > 0:
			_current_hp = mini(_current_hp + hp_gain, max_hp)
			_hp_regen_pool -= float(hp_gain)
			_update_hp_bar()
	elif _current_hp >= max_hp:
		_hp_regen_pool = 0.0
	if mana_regen_per_second > 0.0 and current_mana < max_mana:
		_mana_regen_pool += mana_regen_per_second * delta
		var mana_gain: int = int(floor(_mana_regen_pool))
		if mana_gain > 0:
			current_mana = mini(current_mana + mana_gain, max_mana)
			_mana_regen_pool -= float(mana_gain)
	elif current_mana >= max_mana:
		_mana_regen_pool = 0.0


func _refresh_attack_animations() -> void:
	_attack_animations.clear()
	if _animation_player == null:
		return

	var preferred: Array[String] = []
	if _is_transformed:
		if transformed_attack_animation_1 != "":
			preferred.append(transformed_attack_animation_1)
		if transformed_attack_animation_2 != "":
			preferred.append(transformed_attack_animation_2)
	else:
		if attack_animation_1 != "":
			preferred.append(attack_animation_1)
		if attack_animation_2 != "":
			preferred.append(attack_animation_2)
		if attack_animation_3 != "":
			preferred.append(attack_animation_3)

	for anim_name in preferred:
		if _animation_player.has_animation(anim_name):
			_attack_animations.append(anim_name)

	if _attack_animations.is_empty():
		var fallback_limit: int = 2 if _is_transformed else 3
		var anim_list: PackedStringArray = _animation_player.get_animation_list()
		for anim_name_sn in anim_list:
			var anim_name: String = String(anim_name_sn)
			if anim_name.to_lower().find("attack") >= 0:
				_attack_animations.append(anim_name)
				if _attack_animations.size() >= fallback_limit:
					break


func _input(event: InputEvent) -> void:
	if _hero == null or _is_dead:
		return
	
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_A and key_event.pressed and not key_event.echo:
			_attack_mode = true
			_flash_mode = false
			_update_mouse_cursor_icon()
			return
		if key_event.keycode == KEY_Q and key_event.pressed and not key_event.echo:
			if (skill_q_id == SKILL_ID_Q_FLASH or skill_q_id == SKILL_ID_Q_RANGED_SHOT) and _flash_cooldown <= 0.0:
				_flash_mode = true
				_attack_mode = false
				_update_mouse_cursor_icon()
			return
		if key_event.keycode == KEY_W and key_event.pressed and not key_event.echo:
			_activate_haste()
			return
	
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_flash_mode = false
			_update_mouse_cursor_icon()
			_handle_right_click()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and _flash_mode:
			_handle_flash_click()
			_flash_mode = false
			_update_mouse_cursor_icon()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed and _attack_mode:
			_handle_attack_click()
			_attack_mode = false
			_update_mouse_cursor_icon()
		elif mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			_handle_left_click()


func _create_interaction_ray_query(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = INTERACTION_RAY_MASK
	return query


func _find_enemy_group_node(start: Node) -> Node3D:
	var cursor: Node = start
	while cursor != null:
		if cursor.is_in_group(enemy_group_name):
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null


func _resolve_enemy_from_collider(collider: Node) -> Node3D:
	if collider == null:
		return null
	var enemy_group_node := _find_enemy_group_node(collider)
	if enemy_group_node == null:
		return null
	var enemy := enemy_group_node.get_parent() as Node3D
	if enemy == null or not is_instance_valid(enemy):
		return null
	return enemy


func _can_receive_skill_damage(enemy_controller: Node) -> bool:
	if enemy_controller == null:
		return false
	if enemy_controller.has_method("can_receive_skill_damage"):
		return bool(enemy_controller.call("can_receive_skill_damage"))
	return true


func _handle_left_click() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var space_state := get_world_3d().direct_space_state
	var query := _create_interaction_ray_query(ray_origin, ray_origin + ray_dir * 10000)
	var result := space_state.intersect_ray(query)
	if result and result.collider:
		if result.collider.is_in_group("shop"):
			shop_clicked = true


func _handle_right_click() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	
	var space_state := get_world_3d().direct_space_state
	var query := _create_interaction_ray_query(ray_origin, ray_origin + ray_dir * 10000)
	var result := space_state.intersect_ray(query)
	
	if result and result.collider:
		var collider = result.collider
		var clicked_enemy := _resolve_enemy_from_collider(collider)
		if clicked_enemy != null and not _is_enemy_dead(clicked_enemy):
			_target_enemy = clicked_enemy
			_has_move_target = false
			_focus_lock = false
		else:
			var click_pos: Vector3 = result.position
			_interrupt_attack_for_move()
			_target_enemy = null
			_focus_lock = false
			_target_position = Vector3(click_pos.x, _plane_height, click_pos.z)
			_has_move_target = true
			_spawn_move_confirmation_effect(_target_position)
	else:
		_interrupt_attack_for_move()
		_target_enemy = null
		_focus_lock = false
		_target_position = _get_ground_position(mouse_pos)
		_has_move_target = true
		_spawn_move_confirmation_effect(_target_position)


func _handle_flash_click() -> void:
	if _flash_cooldown > 0.0:
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var target := _get_ground_position(mouse_pos)
	if skill_q_id == SKILL_ID_Q_RANGED_SHOT:
		_cast_ranged_q(target)
		return
	var had_enemy_target: bool = _target_enemy != null and is_instance_valid(_target_enemy) and not _is_enemy_dead(_target_enemy)
	var current := _hero.global_position
	var direction := target - current
	direction.y = 0.0
	var dist := direction.length()
	if dist > flash_max_distance:
		target = current + direction.normalized() * flash_max_distance
		target.y = _plane_height
	_apply_flash_area_damage(current, flash_origin_damage_radius, flash_damage)
	_spawn_flash_effect(current)
	_interrupt_attack_for_move()
	_has_move_target = false
	_is_moving = false
	_hero.global_position = target
	_apply_flash_area_damage(target, flash_destination_damage_radius, flash_damage)
	_flash_cooldown = _compute_skill_cooldown(flash_cooldown_time)
	_push_network_skill_event("q", skill_q_id, {
		"from_pos": current,
		"to_pos": target,
		"yaw": _hero.rotation.y
	})
	_stop_animation()
	if had_enemy_target:
		_resume_enemy_target_after_skill()


func _cast_ranged_q(target: Vector3) -> void:
	if _hero == null:
		return
	var current := _hero.global_position
	var direction := target - current
	direction.y = 0.0
	if direction.length() <= 0.01:
		var fallback_forward := -_hero.global_basis.z
		direction = Vector3(fallback_forward.x, 0.0, fallback_forward.z)
	if direction.length() <= 0.01:
		direction = Vector3.FORWARD
	direction = direction.normalized()
	var ray_length: float = maxf(ranged_q_ray_length, 1.0)
	var ray_end: Vector3 = current + direction * ray_length
	ray_end.y = current.y

	_face_toward(current + direction * 10.0)
	_spawn_ranged_q_ray(current, ray_end)
	_apply_ranged_q_ray_damage(current, ray_end)
	_push_network_skill_event("q", skill_q_id, {
		"from_pos": current,
		"to_pos": ray_end,
		"yaw": _hero.rotation.y
	})
	_interrupt_attack_for_move()
	_has_move_target = false
	_is_moving = false
	_perform_ranged_q_backstep(-direction)
	_flash_cooldown = _compute_skill_cooldown(flash_cooldown_time)


func _perform_ranged_q_backstep(back_direction: Vector3) -> void:
	if _hero == null:
		return
	var safe_back_dir: Vector3 = back_direction
	safe_back_dir.y = 0.0
	if safe_back_dir.length() <= 0.01:
		return
	safe_back_dir = safe_back_dir.normalized()
	var safe_distance: float = maxf(ranged_q_backstep_distance, 0.0)
	if safe_distance <= 0.0:
		return

	var current := _hero.global_position
	var intended_target := current + safe_back_dir * safe_distance
	intended_target.y = _plane_height
	var final_target := _compute_next_move_with_obstacle_avoidance(current, intended_target, safe_distance)
	final_target.y = _plane_height
	_target_position = final_target

	if _ranged_q_backstep_tween != null and _ranged_q_backstep_tween.is_valid():
		_ranged_q_backstep_tween.kill()
	_ranged_q_backstep_tween = null

	var duration: float = maxf(ranged_q_backstep_duration, 0.01)
	_ranged_q_backstep_active = true
	_ranged_q_backstep_total_time = duration
	_ranged_q_backstep_time_left = duration
	_ranged_q_backstep_start_pos = current
	_ranged_q_backstep_end_pos = final_target
	_is_moving = true
	_play_walk_animation()


func _update_ranged_q_backstep(delta: float) -> void:
	if not _ranged_q_backstep_active:
		return
	if _hero == null or not is_instance_valid(_hero):
		_ranged_q_backstep_active = false
		_ranged_q_backstep_time_left = 0.0
		_ranged_q_backstep_total_time = 0.0
		return
	_ranged_q_backstep_time_left = maxf(_ranged_q_backstep_time_left - delta, 0.0)
	var total_time: float = maxf(_ranged_q_backstep_total_time, 0.001)
	var progress: float = 1.0 - (_ranged_q_backstep_time_left / total_time)
	var clamped_progress: float = clampf(progress, 0.0, 1.0)
	var eased_progress: float = clamped_progress * clamped_progress * (3.0 - 2.0 * clamped_progress)
	var next_pos: Vector3 = _ranged_q_backstep_start_pos.lerp(_ranged_q_backstep_end_pos, eased_progress)
	next_pos.y = _plane_height
	_hero.global_position = next_pos
	_target_position = next_pos
	if _ranged_q_backstep_time_left <= 0.0:
		_hero.global_position = _ranged_q_backstep_end_pos
		_ranged_q_backstep_active = false
		_ranged_q_backstep_total_time = 0.0
		_is_moving = false
		_stop_animation()


func _apply_ranged_q_ray_damage(ray_start: Vector3, ray_end: Vector3) -> void:
	var ray_vec: Vector3 = ray_end - ray_start
	ray_vec.y = 0.0
	var ray_len: float = ray_vec.length()
	if ray_len <= 0.01:
		return
	var ray_dir: Vector3 = ray_vec / ray_len
	var safe_damage: int = maxi(ranged_q_ray_damage, 0)
	if safe_damage <= 0:
		return
	var safe_hit_radius: float = maxf(ranged_q_ray_hit_radius, 1.0)
	var hit_controllers: Dictionary = {}
	var candidates := get_tree().get_nodes_in_group(enemy_group_name)
	for candidate in candidates:
		var collider := candidate as Node3D
		if collider == null:
			continue
		var enemy := collider.get_parent() as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if _is_enemy_dead(enemy):
			continue
		var rel: Vector3 = enemy.global_position - ray_start
		rel.y = 0.0
		var projection: float = rel.dot(ray_dir)
		if projection < 0.0 or projection > ray_len:
			continue
		var closest: Vector3 = ray_start + ray_dir * projection
		var lateral_distance: float = _distance_xz(enemy.global_position, closest)
		if lateral_distance > safe_hit_radius:
			continue
		var enemy_controller := enemy.get_parent()
		if enemy_controller == null or not enemy_controller.has_method("apply_damage"):
			continue
		if not _can_receive_skill_damage(enemy_controller):
			continue
		var controller_id: int = enemy_controller.get_instance_id()
		if hit_controllers.has(controller_id):
			continue
		hit_controllers[controller_id] = true
		enemy_controller.call("apply_damage", safe_damage, _hero)
		_add_attack_count(1)


func _apply_flash_area_damage(center: Vector3, radius: float, damage: int) -> void:
	if radius <= 0.0 or damage <= 0:
		return
	var hit_controllers: Dictionary = {}
	var candidates := get_tree().get_nodes_in_group(enemy_group_name)
	for candidate in candidates:
		var collider := candidate as Node3D
		if collider == null:
			continue
		var enemy := collider.get_parent() as Node3D
		if enemy == null or not is_instance_valid(enemy):
			continue
		if _is_enemy_dead(enemy):
			continue
		var distance: float = _distance_xz(center, enemy.global_position)
		if distance > radius:
			continue
		var enemy_controller := enemy.get_parent()
		if enemy_controller == null or not enemy_controller.has_method("apply_damage"):
			continue
		if not _can_receive_skill_damage(enemy_controller):
			continue
		var controller_id: int = enemy_controller.get_instance_id()
		if hit_controllers.has(controller_id):
			continue
		hit_controllers[controller_id] = true
		var final_damage: int = _compute_spell_damage(damage)
		enemy_controller.call("apply_damage", final_damage, _hero)
		_add_attack_count(1)


func _activate_haste() -> void:
	if skill_w_id != SKILL_ID_W_HASTE and skill_w_id != SKILL_ID_W_RANGED_SPEED:
		return
	if _haste_active:
		return
	if _haste_cooldown > 0.0:
		return
	_haste_active = true
	_haste_time_left = haste_duration
	_haste_cooldown = _compute_skill_cooldown(haste_cooldown_time)
	var event_pos: Vector3 = Vector3.ZERO
	if _hero != null:
		event_pos = _hero.global_position
	_push_network_skill_event("w", skill_w_id, {
		"pos": event_pos
	})
	_sync_walk_animation_speed_if_needed()


func _push_network_skill_event(event_type: String, event_skill_id: int, extra: Dictionary = {}) -> void:
	_network_skill_event_seq += 1
	var payload: Dictionary = {
		"seq": _network_skill_event_seq,
		"type": event_type,
		"skill_id": event_skill_id,
		"t_ms": Time.get_ticks_msec()
	}
	for key_variant in extra.keys():
		payload[key_variant] = extra[key_variant]
	_network_last_skill_event = payload


func _apply_poison_to_enemy(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if poison_damage_per_second <= 0:
		return
	var enemy_controller: Node = enemy.get_parent()
	if enemy_controller == null or not _can_receive_skill_damage(enemy_controller):
		return
	var safe_duration: float = maxf(poison_duration, 0.1)
	var safe_tick_interval: float = maxf(poison_tick_interval, 0.05)
	var target_id: int = enemy.get_instance_id()
	var entry: Dictionary = {
		"node": enemy,
		"time_left": safe_duration,
		"tick_left": safe_tick_interval
	}
	_poison_targets[target_id] = entry


func _apply_poison_tick_damage(enemy: Node3D) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _is_enemy_dead(enemy):
		return
	var enemy_controller: Node = enemy.get_parent()
	if enemy_controller != null and enemy_controller.has_method("apply_damage") and _can_receive_skill_damage(enemy_controller):
		var final_damage: int = _compute_spell_damage(poison_damage_per_second)
		enemy_controller.call("apply_damage", final_damage, _hero)
		_add_attack_count(1)
		if _target_enemy == enemy and _is_enemy_dead(enemy):
			_acquire_next_enemy_target_after_kill()


func _roll_critical(chance_percent: float) -> bool:
	var clamped_chance: float = clampf(chance_percent, 0.0, 100.0)
	if clamped_chance <= 0.0:
		return false
	return randf() * 100.0 < clamped_chance


func _compute_physical_damage(base_damage_amount: int) -> int:
	var dmg: int = maxi(base_damage_amount, 0)
	if dmg <= 0:
		return 0
	if _roll_critical(physical_crit_chance):
		dmg = maxi(int(round(float(dmg) * physical_crit_multiplier)), 1)
	return dmg


func _compute_spell_damage(base_damage_amount: int) -> int:
	var dmg: int = maxi(base_damage_amount, 0)
	if dmg <= 0:
		return 0
	if _roll_critical(spell_crit_chance):
		dmg = maxi(int(round(float(dmg) * spell_crit_multiplier)), 1)
	return dmg


func _update_poison_effects(delta: float) -> void:
	if _poison_targets.is_empty():
		return
	var safe_tick_interval: float = maxf(poison_tick_interval, 0.05)
	var remove_ids: Array[int] = []
	for id_variant in _poison_targets.keys():
		var target_id: int = int(id_variant)
		var entry_value: Variant = _poison_targets[target_id]
		if not (entry_value is Dictionary):
			remove_ids.append(target_id)
			continue
		var entry: Dictionary = entry_value
		var enemy: Node3D = null
		if entry.has("node"):
			enemy = entry["node"] as Node3D
		if enemy == null or not is_instance_valid(enemy) or _is_enemy_dead(enemy):
			remove_ids.append(target_id)
			continue

		var time_left: float = float(entry.get("time_left", 0.0))
		var tick_left: float = float(entry.get("tick_left", safe_tick_interval))
		time_left -= delta
		tick_left -= delta

		while tick_left <= 0.0 and time_left > 0.0:
			_apply_poison_tick_damage(enemy)
			tick_left += safe_tick_interval
			if enemy == null or not is_instance_valid(enemy) or _is_enemy_dead(enemy):
				break

		if enemy == null or not is_instance_valid(enemy) or _is_enemy_dead(enemy) or time_left <= 0.0:
			remove_ids.append(target_id)
			continue

		entry["node"] = enemy
		entry["time_left"] = time_left
		entry["tick_left"] = tick_left
		_poison_targets[target_id] = entry

	for target_id in remove_ids:
		_poison_targets.erase(target_id)


func _add_attack_count(value: int = 1) -> void:
	if value <= 0:
		return
	if _is_transformed:
		return
	_attack_count += value
	_update_attack_count_label()
	_check_passive_transform()


func _resume_enemy_target_after_skill() -> void:
	if _hero == null:
		return
	if _target_enemy == null or not is_instance_valid(_target_enemy) or _is_enemy_dead(_target_enemy):
		return

	var distance: float = _distance_xz(_hero.global_position, _target_enemy.global_position)
	_has_move_target = false
	if distance <= attack_range:
		_is_moving = false
		_face_toward(_target_enemy.global_position)
		if _attack_cooldown <= 0.0:
			_start_attack()
		else:
			_play_idle_animation()
	else:
		_is_moving = true
		_nav_agent.target_position = _target_enemy.global_position
		_play_walk_animation()


func _check_passive_transform() -> void:
	if not _uses_transform_passive():
		return
	if _is_transformed:
		return
	if _attack_count <= passive_transform_attack_count:
		return
	_transform_model()


func _transform_model() -> void:
	if transformed_model_scene == null:
		return
	if _hero == null:
		return

	var base_hero: Node3D = _hero
	var parent_node: Node = base_hero.get_parent()
	if parent_node == null:
		return

	var transformed_hero: Node3D = transformed_model_scene.instantiate() as Node3D
	if transformed_hero == null:
		return

	var base_transform: Transform3D = base_hero.global_transform
	var base_scale: Vector3 = base_hero.scale
	var base_rotation: Vector3 = base_hero.rotation

	if _animation_player != null and _animation_player.is_playing():
		_animation_player.stop()
	_is_attacking = false
	_current_attack_index = 0

	parent_node.add_child(transformed_hero)
	transformed_hero.global_transform = base_transform
	transformed_hero.scale = base_scale
	transformed_hero.rotation = base_rotation
	var fixed_rotation: Vector3 = transformed_hero.rotation
	fixed_rotation.z = 0.0
	transformed_hero.rotation = fixed_rotation

	if _nav_agent != null and _nav_agent.get_parent() != null:
		_nav_agent.reparent(transformed_hero)
	if _hp_bar != null and _hp_bar.get_parent() != null:
		_hp_bar.reparent(transformed_hero)
		_hp_bar.position = Vector3(0.0, hp_bar_height, 0.0)
	if _attack_count_label != null and _attack_count_label.get_parent() != null:
		_attack_count_label.reparent(transformed_hero)
		_attack_count_label.position = Vector3(0.0, hp_bar_height + attack_count_label_height_offset, 0.0)
	if base_hero.is_in_group("hero"):
		base_hero.remove_from_group("hero")
	transformed_hero.add_to_group("hero")

	base_hero.visible = false
	_original_hero = base_hero
	_transformed_hero = transformed_hero
	_hero = transformed_hero
	_animation_player = _hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_refresh_motion_animation_aliases()
	_is_transformed = true
	_transform_time_left = transform_duration
	_attack_count = 0
	_update_attack_count_label()
	_refresh_attack_animations()
	_play_idle_animation()


func _revert_transform_model() -> void:
	if not _is_transformed:
		return
	if _original_hero == null or not is_instance_valid(_original_hero):
		return

	var was_attacking: bool = _is_attacking
	var current_hero: Node3D = _hero
	var current_transform: Transform3D = _original_hero.global_transform
	var current_scale: Vector3 = _original_hero.scale
	var current_rotation: Vector3 = _original_hero.rotation
	if current_hero != null and is_instance_valid(current_hero):
		current_transform = current_hero.global_transform
		current_scale = current_hero.scale
		current_rotation = current_hero.rotation

	if _nav_agent != null and _nav_agent.get_parent() != null:
		_nav_agent.reparent(_original_hero)
	if _hp_bar != null and _hp_bar.get_parent() != null:
		_hp_bar.reparent(_original_hero)
		_hp_bar.position = Vector3(0.0, hp_bar_height, 0.0)
	if _attack_count_label != null and _attack_count_label.get_parent() != null:
		_attack_count_label.reparent(_original_hero)
		_attack_count_label.position = Vector3(0.0, hp_bar_height + attack_count_label_height_offset, 0.0)

	_original_hero.visible = true
	_original_hero.add_to_group("hero")
	_original_hero.global_transform = current_transform
	_original_hero.scale = current_scale
	_original_hero.rotation = current_rotation
	var fixed_rotation: Vector3 = _original_hero.rotation
	fixed_rotation.z = 0.0
	_original_hero.rotation = fixed_rotation

	if current_hero != null and is_instance_valid(current_hero):
		if current_hero.is_in_group("hero"):
			current_hero.remove_from_group("hero")
		current_hero.queue_free()

	_transformed_hero = null
	_hero = _original_hero
	_animation_player = _hero.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_refresh_motion_animation_aliases()
	_is_transformed = false
	_transform_time_left = 0.0
	_update_attack_count_label()
	_refresh_attack_animations()
	_resume_after_transform_cancel(was_attacking)


func _resume_after_transform_cancel(was_attacking: bool) -> void:
	_is_attacking = false
	_current_attack_index = 0
	_is_moving = false

	var has_enemy_target: bool = false
	if _target_enemy != null and is_instance_valid(_target_enemy) and not _is_enemy_dead(_target_enemy):
		has_enemy_target = true

	if has_enemy_target:
		var enemy_pos: Vector3 = _target_enemy.global_position
		var distance: float = _distance_xz(_hero.global_position, enemy_pos)
		if distance <= attack_range:
			if was_attacking:
				_attack_cooldown = 0.0
			if _attack_cooldown <= 0.0:
				_start_attack()
			else:
				_face_toward(enemy_pos)
				_play_idle_animation()
		else:
			_nav_agent.target_position = enemy_pos
			_is_moving = true
			_play_walk_animation()
		return

	if _has_move_target:
		_nav_agent.target_position = _target_position
		_is_moving = true
		_play_walk_animation()
		return

	_play_idle_animation()


func _spawn_flash_effect(pos: Vector3) -> void:
	if flash_effect_scene == null:
		return
	var effect := flash_effect_scene.instantiate() as Node3D
	if effect == null:
		return
	effect.global_position = pos
	effect.scale = Vector3(2, 2, 2)
	get_parent().add_child(effect)
	var anim_player := effect.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player != null:
		var anim_list := anim_player.get_animation_list()
		if anim_list.size() > 0:
			var anim_name := anim_list[0]
			var anim := anim_player.get_animation(anim_name)
			if anim != null:
				anim.loop_mode = Animation.LOOP_NONE
			anim_player.play(anim_name)
			var duration := 2.0
			if anim != null:
				duration = maxf(anim.length, 0.1)
			get_tree().create_timer(duration).timeout.connect(effect.queue_free)
		else:
			get_tree().create_timer(2.0).timeout.connect(effect.queue_free)
	else:
		get_tree().create_timer(2.0).timeout.connect(effect.queue_free)


func _spawn_ranged_q_ray(ray_start: Vector3, ray_end: Vector3) -> void:
	var delta := ray_end - ray_start
	if delta.length() <= 0.01:
		return
	var safe_dir := delta.normalized()

	var safe_length: float = maxf(delta.length(), 1.0)
	var safe_width: float = maxf(ranged_q_ray_width, 0.5)
	var safe_thickness: float = maxf(ranged_q_ray_thickness, 0.5)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(safe_length, safe_thickness, safe_width)
	var beam := MeshInstance3D.new()
	beam.mesh = mesh
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(1.0, 0.1, 0.1, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.15, 0.15, 1.0)
	mat.emission_energy_multiplier = 2.0
	beam.material_override = mat

	var center := (ray_start + ray_end) * 0.5
	var up_axis := Vector3.UP
	if absf(safe_dir.dot(up_axis)) > 0.99:
		up_axis = Vector3.FORWARD
	var z_axis := safe_dir.cross(up_axis).normalized()
	var y_axis := z_axis.cross(safe_dir).normalized()
	beam.global_transform = Transform3D(Basis(safe_dir, y_axis, z_axis), center)

	var host: Node = get_parent()
	if host == null:
		return
	host.add_child(beam)
	get_tree().create_timer(maxf(ranged_q_ray_lifetime, 0.03)).timeout.connect(beam.queue_free)


func _spawn_move_confirmation_effect(pos: Vector3) -> void:
	if move_confirmation_scene == null:
		return

	var effect := move_confirmation_scene.instantiate() as Node3D
	if effect == null:
		return

	effect.global_position = Vector3(pos.x, _plane_height, pos.z)
	effect.scale = move_confirmation_scale
	get_parent().add_child(effect)

	var duration := maxf(move_confirmation_lifetime, 0.1)
	var anim_player := effect.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player != null:
		var anim_name: StringName = &""
		if anim_player.autoplay != "":
			anim_name = StringName(anim_player.autoplay)
		elif anim_player.is_playing():
			anim_name = anim_player.current_animation
		else:
			var anim_list := anim_player.get_animation_list()
			if anim_list.size() > 0:
				anim_name = anim_list[0]

		if anim_name != &"" and anim_player.has_animation(anim_name):
			var anim := anim_player.get_animation(anim_name)
			if anim != null:
				anim.loop_mode = Animation.LOOP_NONE
				duration = maxf(anim.length * 0.5, 0.1)
			if not anim_player.is_playing():
				anim_player.play(anim_name)

	get_tree().create_timer(duration).timeout.connect(effect.queue_free)


func _handle_attack_click() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	
	var space_state := get_world_3d().direct_space_state
	var query := _create_interaction_ray_query(ray_origin, ray_origin + ray_dir * 10000)
	var result := space_state.intersect_ray(query)

	var selected_enemy: Node3D = null
	if result and result.collider:
		var collider_node := result.collider as Node
		if collider_node != null:
			selected_enemy = _resolve_enemy_from_collider(collider_node)

	if selected_enemy == null:
		var nearest_enemy: Node3D = _find_nearest_enemy()
		if nearest_enemy != null:
			var nearest_distance: float = _distance_xz(_hero.global_position, nearest_enemy.global_position)
			if nearest_distance <= attack_range:
				selected_enemy = nearest_enemy
			elif nearest_distance <= engage_range:
				selected_enemy = nearest_enemy

	if selected_enemy != null and is_instance_valid(selected_enemy) and not _is_enemy_dead(selected_enemy):
		_target_enemy = selected_enemy
		_has_move_target = false
		_focus_lock = true
	else:
		# A 键攻击点击未命中且附近没有可索敌目标时，取消当前攻击目标。
		_target_enemy = null
		_has_move_target = false
		_focus_lock = false
		_interrupt_attack_for_chase()


func _get_ground_position(mouse_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return _hero.global_position
	
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	
	if absf(ray_dir.y) < 0.0001:
		return _hero.global_position
	
	var t := (_plane_height - ray_origin.y) / ray_dir.y
	if t < 0.0:
		return _hero.global_position
	
	return ray_origin + ray_dir * t


func _process(delta: float) -> void:
	_update_mouse_cursor_icon()
	if _hero == null or _is_dead:
		return
	if _attack_count_label == null or not is_instance_valid(_attack_count_label):
		_create_attack_count_label()
	if hero_level != _last_stat_level:
		_recalculate_war3_stats(false)
	
	if _attack_cooldown > 0.0:
		_attack_cooldown -= delta
	if _flash_cooldown > 0.0:
		_flash_cooldown -= delta
	if _haste_cooldown > 0.0:
		_haste_cooldown -= delta
	if _haste_active:
		_haste_time_left -= delta
		if _haste_time_left <= 0.0:
			_haste_active = false
			_haste_time_left = 0.0
	_sync_walk_animation_speed_if_needed()
	if _slow_time_left > 0.0:
		_slow_time_left -= delta
		if _slow_time_left <= 0.0:
			_slow_time_left = 0.0
			_slow_percent = 0.0
	_apply_regeneration(delta)
	_update_poison_effects(delta)
	_refresh_runtime_combat_stats()
	if _is_transformed:
		_transform_time_left = maxf(_transform_time_left - delta, 0.0)
		_update_attack_count_label()
		if _transform_time_left <= 0.0:
			_revert_transform_model()
	if _attack_count_label != null and _attack_count_label.visible:
		_attack_count_label.position = Vector3(0.0, hp_bar_height + attack_count_label_height_offset, 0.0)
	if _ranged_q_backstep_active:
		_update_ranged_q_backstep(delta)
		return
	
	_update_auto_attack_target()
	
	if _is_attacking:
		if _target_enemy == null or not is_instance_valid(_target_enemy) or _is_enemy_dead(_target_enemy):
			_interrupt_attack_for_chase()
			_target_enemy = null
			_focus_lock = false
			return
		
		_face_toward(_target_enemy.global_position)
		
		var attack_distance := _distance_xz(_hero.global_position, _target_enemy.global_position)
		if attack_distance > attack_range:
			_interrupt_attack_for_chase()
		
		return
	
	var current := _hero.global_position
	
	if _target_enemy != null and is_instance_valid(_target_enemy):
		var enemy_pos := _target_enemy.global_position
		var distance := _distance_xz(current, enemy_pos)
		
		if distance > engage_range and not _focus_lock:
			_target_enemy = null
			_focus_lock = false
			if _is_moving:
				_is_moving = false
				_stop_animation()
			return
		
		if distance > attack_range:
			_nav_agent.target_position = enemy_pos
			var move_target := enemy_pos
			if not _nav_agent.is_navigation_finished():
				var next_nav := _nav_agent.get_next_path_position()
				if _distance_xz(next_nav, current) > 1.0:
					move_target = next_nav
			var next := _compute_next_move_with_obstacle_avoidance(current, move_target, _get_current_move_speed() * delta, delta)
			next.y = _plane_height
			_hero.global_position = next
			_look_at_target(move_target)
			
			if not _is_moving:
				_is_moving = true
				_play_walk_animation()
		else:
			if _is_moving:
				_is_moving = false
				_stop_animation()
			_face_toward(enemy_pos)
			if _attack_cooldown <= 0.0:
				_start_attack()
	elif _has_move_target:
		var dist_to_target := _distance_xz(current, _target_position)
		if dist_to_target < 20.0:
			_has_move_target = false
			_is_moving = false
			_stop_animation()
		else:
			_nav_agent.target_position = _target_position
			var move_target := _target_position
			if not _nav_agent.is_navigation_finished():
				var next_nav := _nav_agent.get_next_path_position()
				if _distance_xz(next_nav, current) > 1.0:
					move_target = next_nav
			var next := _compute_next_move_with_obstacle_avoidance(current, move_target, _get_current_move_speed() * delta, delta)
			next.y = _plane_height
			_hero.global_position = next
			_look_at_target(move_target)
			
			if not _is_moving:
				_is_moving = true
				_play_walk_animation()
	else:
		if _is_moving:
			_is_moving = false
			_stop_animation()


func _update_mouse_cursor_icon() -> void:
	var is_aim_mode: bool = _attack_mode or _flash_mode
	if is_aim_mode:
		var over_enemy := _is_mouse_over_enemy()
		_apply_mouse_cursor(over_enemy, true, false)
		return
	if _destroy_cursor_mode:
		_apply_mouse_cursor(_destroy_hover_item, false, true)
		return
	var over_enemy := _is_mouse_over_enemy()
	_apply_mouse_cursor(over_enemy, false, false)


func _is_mouse_over_enemy() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var query := _create_interaction_ray_query(ray_origin, ray_origin + ray_dir * 10000.0)
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty() or not result.has("collider"):
		return false
	var collider := result["collider"] as Node
	if collider == null:
		return false
	var enemy := _resolve_enemy_from_collider(collider)
	return enemy != null and not _is_enemy_dead(enemy)


func _apply_mouse_cursor(use_enemy_cursor: bool, attack_mode_cursor: bool, selected_cursor_mode: bool) -> void:
	if _cursor_initialized and use_enemy_cursor == _using_enemy_cursor and attack_mode_cursor == _using_attack_cursor and selected_cursor_mode == _using_selected_cursor:
		return
	_cursor_initialized = true
	_using_enemy_cursor = use_enemy_cursor
	_using_attack_cursor = attack_mode_cursor
	_using_selected_cursor = selected_cursor_mode
	var target_cursor: Texture2D
	if selected_cursor_mode:
		target_cursor = cursor_attack_enemy_texture if use_enemy_cursor else cursor_attack_default_texture
	elif attack_mode_cursor:
		target_cursor = cursor_attack_enemy_texture if use_enemy_cursor else cursor_attack_default_texture
	else:
		target_cursor = cursor_enemy_texture if use_enemy_cursor else cursor_default_texture
	if target_cursor != null:
		Input.set_custom_mouse_cursor(target_cursor, Input.CURSOR_ARROW, cursor_hotspot)
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


func _look_at_target(target_pos: Vector3) -> void:
	var direction = target_pos - _hero.global_position
	direction.y = 0
	if direction.length() > 0.01:
		var target_rotation = atan2(direction.x, direction.z)
		_hero.rotation.y = target_rotation - PI / 2.0


func _face_toward(target_pos: Vector3) -> void:
	var direction = target_pos - _hero.global_position
	direction.y = 0
	if direction.length() > 0.01:
		_hero.rotation.y = atan2(direction.x, direction.z) - PI / 2.0


func _start_attack() -> void:
	if _animation_player == null:
		return
	_refresh_attack_animations()
	if _attack_animations.is_empty():
		_is_attacking = false
		return
	
	_is_attacking = true
	_has_move_target = false
	_current_attack_index = 0
	
	if not _animation_player.animation_finished.is_connected(_on_attack_finished):
		_animation_player.animation_finished.connect(_on_attack_finished)
	
	_play_current_attack_animation()


func _get_walk_animation_speed_scale() -> float:
	if _haste_active and skill_w_id == SKILL_ID_W_RANGED_SPEED:
		return maxf(ranged_haste_walk_anim_speed_multiplier, 0.1)
	return 1.0


func _sync_walk_animation_speed_if_needed() -> void:
	if _animation_player == null:
		return
	if _resolved_walk_animation == "":
		_animation_player.speed_scale = 1.0
		return
	if not _animation_player.is_playing():
		_animation_player.speed_scale = 1.0
		return
	if String(_animation_player.current_animation) != _resolved_walk_animation:
		_animation_player.speed_scale = 1.0
		return
	_animation_player.speed_scale = _get_walk_animation_speed_scale()


func _play_walk_animation() -> void:
	if _animation_player == null:
		return
	if _resolved_walk_animation == "":
		_refresh_motion_animation_aliases()
	if _resolved_walk_animation == "":
		return
	var walk_speed_scale: float = _get_walk_animation_speed_scale()
	if _animation_player.is_playing() and String(_animation_player.current_animation) == _resolved_walk_animation:
		_animation_player.speed_scale = walk_speed_scale
		return
	_animation_player.speed_scale = walk_speed_scale
	_animation_player.play(_resolved_walk_animation, -1, 1.0, false)
	var anim = _animation_player.get_animation(_resolved_walk_animation)
	if anim != null:
		anim.loop_mode = Animation.LOOP_LINEAR


func _play_current_attack_animation() -> void:
	if _animation_player == null:
		return
	
	if _current_attack_index >= _attack_animations.size():
		_is_attacking = false
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
	_try_apply_damage_to_enemy()


func _on_attack_finished(anim_name: StringName) -> void:
	if _is_attacking:
		_current_attack_index += 1
		
		if _current_attack_index < _attack_animations.size():
			_play_current_attack_animation()
		else:
			_is_attacking = false
			_attack_cooldown = _get_attack_interval()
			if _target_enemy != null and is_instance_valid(_target_enemy):
				if _is_enemy_dead(_target_enemy):
					_acquire_next_enemy_target_after_kill()
					return
				var distance := _distance_xz(_hero.global_position, _target_enemy.global_position)
				if distance <= attack_range and _attack_cooldown <= 0.0:
					_start_attack()


func _stop_animation() -> void:
	if _animation_player == null:
		return
	_animation_player.stop()
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


func _compute_next_move_with_obstacle_avoidance(current: Vector3, move_target: Vector3, max_step: float, delta: float = 0.0) -> Vector3:
	var to_target: Vector3 = move_target - current
	to_target.y = 0.0
	if to_target.length() <= 0.01 or max_step <= 0.0:
		return current

	var step: float = minf(max_step, to_target.length())
	var forward_dir: Vector3 = to_target.normalized()
	var steer_dir: Vector3 = forward_dir
	if dynamic_detour_enabled and delta > 0.0 and _dynamic_detour_time_left > 0.0:
		var side_vec: Vector3 = forward_dir.cross(Vector3.UP)
		if side_vec.length() > 0.001:
			side_vec = side_vec.normalized()
			steer_dir = (forward_dir + side_vec * _dynamic_detour_side * maxf(dynamic_detour_side_strength, 0.0)).normalized()
		_dynamic_detour_time_left = maxf(_dynamic_detour_time_left - delta, 0.0)
	var direct_next: Vector3 = current + steer_dir * step
	var dynamic_blocked: bool = _is_dynamic_unit_blocking_segment(current, direct_next, maxf(dynamic_blocker_avoid_radius, 32.0))
	if not _is_move_segment_blocked(current, direct_next, 42.0, 38.0) and not dynamic_blocked:
		return direct_next
	if dynamic_detour_enabled and delta > 0.0 and _dynamic_detour_time_left <= 0.0:
		_dynamic_detour_time_left = maxf(dynamic_detour_duration_sec, 0.08)
		_dynamic_detour_side = -_dynamic_detour_side

	var best_next: Vector3 = current
	var best_score: float = -INF
	for angle_deg in OBSTACLE_STEER_ANGLES:
		var candidate_dir: Vector3 = forward_dir.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var candidate_next: Vector3 = current + candidate_dir * step
		var blocked_static: bool = _is_move_segment_blocked(current, candidate_next, 42.0, 38.0)
		var blocked_dynamic: bool = _is_dynamic_unit_blocking_segment(current, candidate_next, maxf(dynamic_blocker_avoid_radius, 32.0))
		if blocked_static or blocked_dynamic:
			continue
		var remain: Vector3 = move_target - candidate_next
		remain.y = 0.0
		var score: float = -remain.length()
		var angle_sign: float = sign(float(angle_deg))
		if dynamic_detour_enabled and angle_sign != 0.0 and angle_sign == _dynamic_detour_side:
			score += 3.5
		if score > best_score:
			best_score = score
			best_next = candidate_next
	return best_next


func _is_dynamic_unit_blocking_segment(from_pos: Vector3, to_pos: Vector3, probe_radius: float) -> bool:
	if _hero == null:
		return false
	var seg: Vector3 = to_pos - from_pos
	seg.y = 0.0
	var seg_len: float = seg.length()
	if seg_len <= 0.01:
		return false
	var seg_dir: Vector3 = seg / seg_len
	var safe_radius: float = maxf(probe_radius, 8.0)

	var groups: Array[StringName] = [enemy_group_name, StringName("hero")]
	for group_name in groups:
		var candidates: Array = get_tree().get_nodes_in_group(group_name)
		for candidate_variant in candidates:
			var candidate_node: Node = candidate_variant as Node
			var blocker: Node3D = candidate_node as Node3D
			if blocker == null:
				continue
			if blocker == _hero:
				continue
			if not is_instance_valid(blocker):
				continue
			if not blocker.visible:
				continue
			var blocker_pos: Vector3 = blocker.global_position
			var rel: Vector3 = blocker_pos - from_pos
			rel.y = 0.0
			var proj: float = rel.dot(seg_dir)
			if proj < 0.0 or proj > seg_len:
				continue
			var nearest: Vector3 = from_pos + seg_dir * proj
			var lateral_dist: float = _distance_xz(blocker_pos, nearest)
			if lateral_dist <= safe_radius:
				return true
	return false


func _update_auto_attack_target() -> void:
	if not auto_attack_on_enemy_engage:
		return

	if _focus_lock:
		if _target_enemy != null and is_instance_valid(_target_enemy) and not _is_enemy_dead(_target_enemy):
			return
		_focus_lock = false
	
	# 玩家下达了移动指令时，不自动切回攻击目标
	if _has_move_target:
		return
	
	var enemy := _find_nearest_enemy()
	if enemy == null:
		_was_in_enemy_engage_range = false
		_last_auto_enemy = null
		_auto_aggro_initialized = true
		return
	
	var distance := _distance_xz(_hero.global_position, enemy.global_position)
	var enemy_engage_range := _get_enemy_engage_range(enemy)
	var in_enemy_engage_range := distance <= enemy_engage_range
	
	# 首帧只记录状态，避免开局就在范围内时自动开打
	if not _auto_aggro_initialized:
		_auto_aggro_initialized = true
		_was_in_enemy_engage_range = in_enemy_engage_range
		_last_auto_enemy = enemy
		return
	
	if in_enemy_engage_range and (not _was_in_enemy_engage_range or _last_auto_enemy != enemy):
		_target_enemy = enemy
		_has_move_target = false
	
	_was_in_enemy_engage_range = in_enemy_engage_range
	_last_auto_enemy = enemy


func _interrupt_attack_for_move() -> void:
	if not _is_attacking:
		return
	
	_is_attacking = false
	_current_attack_index = 0
	if _animation_player != null and _animation_player.is_playing():
		_animation_player.stop()


func _interrupt_attack_for_chase() -> void:
	if not _is_attacking:
		return
	
	_is_attacking = false
	_current_attack_index = 0
	if _animation_player != null and _animation_player.is_playing():
		_animation_player.stop()


func _try_apply_damage_to_enemy() -> void:
	if _target_enemy == null or not is_instance_valid(_target_enemy):
		return
	
	if _is_enemy_dead(_target_enemy):
		_acquire_next_enemy_target_after_kill()
		return
	
	if not _is_ranged_hero():
		var distance := _distance_xz(_hero.global_position, _target_enemy.global_position)
		if distance > attack_range:
			return
	
	var enemy_controller := _target_enemy.get_parent()
	if enemy_controller != null and enemy_controller.has_method("apply_damage"):
		var final_damage: int = _compute_physical_damage(damage_per_hit)
		enemy_controller.call("apply_damage", final_damage, _hero)
		_add_attack_count(1)
		if _haste_active and skill_w_id == SKILL_ID_W_HASTE:
			_apply_poison_to_enemy(_target_enemy)
		if _is_enemy_dead(_target_enemy):
			_acquire_next_enemy_target_after_kill()


func _acquire_next_enemy_target_after_kill() -> void:
	var next_enemy := _find_nearest_enemy_in_engage_range()
	_target_enemy = next_enemy
	_focus_lock = false
	if next_enemy != null:
		_has_move_target = false
		_was_in_enemy_engage_range = true
		_last_auto_enemy = next_enemy


func _find_nearest_enemy_in_engage_range() -> Node3D:
	if _hero == null:
		return null
	var nearest: Node3D = null
	var nearest_distance := INF
	var candidates := get_tree().get_nodes_in_group(enemy_group_name)
	for candidate in candidates:
		var collider := candidate as Node3D
		if collider == null:
			continue
		var enemy := collider.get_parent() as Node3D
		if enemy == null:
			continue
		if not is_instance_valid(enemy):
			continue
		if _is_enemy_dead(enemy):
			continue
		var distance := _distance_xz(_hero.global_position, enemy.global_position)
		if distance > engage_range:
			continue
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	return nearest


func apply_damage(amount: int, ignore_armor: bool = false, attacker: Node3D = null) -> void:
	if _is_dead:
		return
	if _is_transformed and amount > 0:
		return

	var incoming: int = maxi(amount, 0)
	var final_damage: int = incoming
	if final_damage > 0 and not ignore_armor:
		final_damage = int(round(float(incoming) * _get_armor_damage_multiplier()))
		final_damage = maxi(final_damage, 1)
	_current_hp = maxi(_current_hp - final_damage, 0)
	_update_hp_bar()
	if final_damage > 0 and _current_hp > 0:
		_retarget_to_attacker(attacker)
	
	if _current_hp <= 0:
		_die()


func _retarget_to_attacker(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var target_enemy: Node3D = attacker
	if target_enemy.is_in_group(enemy_group_name):
		target_enemy = target_enemy.get_parent() as Node3D
	if target_enemy == null or not is_instance_valid(target_enemy):
		return
	if _is_enemy_dead(target_enemy):
		return
	_target_enemy = target_enemy
	_focus_lock = true
	_has_move_target = false
	_ranged_q_backstep_active = false
	_ranged_q_backstep_time_left = 0.0
	_ranged_q_backstep_total_time = 0.0
	if _is_attacking:
		_interrupt_attack_for_chase()
	_face_toward(target_enemy.global_position)


func is_dead() -> bool:
	return _is_dead


func _die() -> void:
	if _is_dead:
		return
	
	_is_dead = true
	_is_attacking = false
	_is_moving = false
	_has_move_target = false
	_focus_lock = false
	_target_enemy = null
	_ranged_q_backstep_active = false
	_ranged_q_backstep_time_left = 0.0
	_ranged_q_backstep_total_time = 0.0
	_poison_targets.clear()
	_hp_regen_pool = 0.0
	_mana_regen_pool = 0.0
	_slow_percent = 0.0
	_slow_time_left = 0.0
	
	if _animation_player != null:
		_animation_player.stop()
		_animation_player.speed_scale = 1.0
		if _resolved_death_animation == "":
			_refresh_motion_animation_aliases()
		if _resolved_death_animation != "" and _animation_player.has_animation(_resolved_death_animation):
			var anim = _animation_player.get_animation(_resolved_death_animation)
			if anim != null:
				anim.loop_mode = Animation.LOOP_NONE
			_animation_player.play(_resolved_death_animation, -1.0, 1.5, false)
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
	_hero.add_child(_hp_bar)
	_create_attack_count_label()


func _update_hp_bar() -> void:
	if _hp_bar_material == null:
		return
	_hp_bar_material.set_shader_parameter("hp_ratio", float(_current_hp) / float(max_hp))


func _create_attack_count_label() -> void:
	if _hero == null:
		return
	if _attack_count_label != null and is_instance_valid(_attack_count_label):
		_attack_count_label.queue_free()

	_attack_count_label = Label3D.new()
	_attack_count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_attack_count_label.no_depth_test = true
	_attack_count_label.fixed_size = true
	_attack_count_label.double_sided = true
	_attack_count_label.shaded = false
	_attack_count_label.render_priority = 20
	_attack_count_label.pixel_size = attack_count_label_pixel_size
	_attack_count_label.font_size = attack_count_label_font_size
	_attack_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_attack_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_attack_count_label.modulate = Color(1.0, 0.92, 0.2, 1.0)
	_attack_count_label.outline_size = 2
	_attack_count_label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	_attack_count_label.visible = _should_show_attack_count_label()
	_attack_count_label.position = Vector3(0.0, hp_bar_height + attack_count_label_height_offset, 0.0)
	_hero.add_child(_attack_count_label)
	_update_attack_count_label()


func _update_attack_count_label() -> void:
	if _attack_count_label == null:
		return
	if not _should_show_attack_count_label():
		_attack_count_label.visible = false
		return
	_attack_count_label.visible = true
	if _is_transformed:
		var left_sec: float = maxf(_transform_time_left, 0.0)
		_attack_count_label.text = "%.1fs" % left_sec
	else:
		_attack_count_label.text = str(_attack_count)
	_attack_count_label.position = Vector3(0.0, hp_bar_height + attack_count_label_height_offset, 0.0)


func _is_enemy_dead(enemy: Node3D) -> bool:
	if enemy == null or not is_instance_valid(enemy):
		return true
	var enemy_controller := enemy.get_parent()
	if enemy_controller != null and enemy_controller.has_method("is_dead"):
		return bool(enemy_controller.call("is_dead"))
	return false


func _get_effective_ias_percent() -> float:
	var agi_ias_percent: float = float(agility) * AGI_ATTACK_SPEED_PER_POINT * 100.0
	var total_ias: float = agi_ias_percent + _equip_attack_speed_percent_bonus
	return clampf(total_ias, WC3_IAS_MIN, WC3_IAS_MAX)


func _get_attack_speed_scale() -> float:
	attack_speed_percent_total = _get_effective_ias_percent()
	var speed_factor: float = 1.0 + attack_speed_percent_total * 0.01
	var speed := base_attack_speed * maxf(speed_factor, 0.05)
	if _is_transformed:
		speed *= transformed_attack_speed_multiplier
	if _haste_active and skill_w_id == SKILL_ID_W_HASTE:
		speed *= haste_multiplier
	return maxf(speed, 0.05)


func _get_attack_interval() -> float:
	return 1.0 / maxf(_get_attack_speed_scale(), 0.05)


func _get_effective_cooldown_reduction_percent() -> float:
	var total_cdr: float = base_cooldown_reduction_percent + _equip_cooldown_reduction_percent_bonus
	return clampf(total_cdr, 0.0, MAX_COOLDOWN_REDUCTION_PERCENT)


func _compute_skill_cooldown(base_cooldown: float) -> float:
	var safe_base: float = maxf(base_cooldown, 0.0)
	if safe_base <= 0.0:
		return 0.0
	var cdr_ratio: float = clampf(cooldown_reduction_percent_total, 0.0, MAX_COOLDOWN_REDUCTION_PERCENT) * 0.01
	return safe_base * maxf(1.0 - cdr_ratio, 0.0)


func _get_armor_damage_multiplier() -> float:
	if armor >= 0.0:
		var reduction: float = (0.06 * armor) / (1.0 + 0.06 * armor)
		return maxf(1.0 - reduction, 0.0)
	return 2.0 - pow(0.94, -armor)


func _schedule_finalize_death(delay_sec: float) -> void:
	var timer := get_tree().create_timer(maxf(delay_sec, 0.05))
	timer.timeout.connect(_finalize_death)


func _finalize_death() -> void:
	if _death_finalized:
		return
	_death_finalized = true
	
	if _hp_bar != null:
		_hp_bar.visible = false
	if _attack_count_label != null:
		_attack_count_label.visible = false
	
	if _hero != null:
		_hero.visible = false


func _find_nearest_enemy() -> Node3D:
	if _hero == null:
		return null
	var nearest: Node3D = null
	var nearest_distance := INF
	
	var candidates := get_tree().get_nodes_in_group(enemy_group_name)
	for candidate in candidates:
		var collider := candidate as Node3D
		if collider == null:
			continue
		
		var enemy := collider.get_parent() as Node3D
		if enemy == null:
			continue
		if not is_instance_valid(enemy):
			continue
		if _is_enemy_dead(enemy):
			continue
		
		var distance := _distance_xz(_hero.global_position, enemy.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = enemy
	
	return nearest


func _get_enemy_engage_range(enemy: Node3D) -> float:
	if enemy == null or not is_instance_valid(enemy):
		return engage_range
	var ai_node := enemy.get_parent()
	if ai_node != null:
		var value = ai_node.get("engage_range")
		if value is float or value is int:
			return float(value)
	
	return engage_range
