extends Node3D

signal gate_destroyed

@export var max_hp: int = 100
@export var hp_bar_height: float = 280.0
@export var hp_bar_width: float = 200.0

var current_hp: int = 100
var _is_dead: bool = false
var _hp_bar: MeshInstance3D
var _hp_bar_material: ShaderMaterial


func _ready() -> void:
	max_hp = maxi(max_hp, 1)
	current_hp = max_hp
	_create_hp_bar()
	_update_hp_bar()


func apply_damage(amount: int, _attacker: Node3D = null) -> void:
	if multiplayer.multiplayer_peer != null and not multiplayer.is_server():
		return
	if _is_dead:
		return
	var real_damage: int = maxi(amount, 0)
	if real_damage <= 0:
		return
	current_hp = maxi(current_hp - real_damage, 0)
	_update_hp_bar()
	if current_hp <= 0:
		_die()


func is_dead() -> bool:
	return _is_dead


func can_receive_skill_damage() -> bool:
	return false


func _create_hp_bar() -> void:
	var shader := Shader.new()
	shader.code = "shader_type spatial;\nrender_mode unshaded, cull_disabled, shadows_disabled;\nuniform float hp_ratio : hint_range(0.0, 1.0) = 1.0;\nvoid vertex() {\n\tMODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);\n\tMODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);\n}\nvoid fragment() {\n\tvec2 uv = UV;\n\tfloat bw = 0.04;\n\tfloat bh = 0.12;\n\tif (uv.x < bw || uv.x > 1.0 - bw || uv.y < bh || uv.y > 1.0 - bh) {\n\t\tALBEDO = vec3(0.0);\n\t\tALPHA = 0.9;\n\t} else {\n\t\tfloat ix = (uv.x - bw) / (1.0 - 2.0 * bw);\n\t\tif (ix <= hp_ratio) {\n\t\t\tALBEDO = vec3(1.0 - hp_ratio, hp_ratio, 0.0);\n\t\t\tALPHA = 0.9;\n\t\t} else {\n\t\t\tALBEDO = vec3(0.15);\n\t\t\tALPHA = 0.5;\n\t\t}\n\t}\n}\n"
	_hp_bar_material = ShaderMaterial.new()
	_hp_bar_material.shader = shader
	_hp_bar_material.set_shader_parameter("hp_ratio", 1.0)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(hp_bar_width, 24.0)
	_hp_bar = MeshInstance3D.new()
	_hp_bar.mesh = mesh
	_hp_bar.material_override = _hp_bar_material
	_hp_bar.position = Vector3(0.0, hp_bar_height, 0.0)
	add_child(_hp_bar)


func _update_hp_bar() -> void:
	if _hp_bar_material == null:
		return
	_hp_bar_material.set_shader_parameter("hp_ratio", float(current_hp) / float(maxi(max_hp, 1)))


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	current_hp = 0
	_update_hp_bar()

	var collision_body := find_child("CollisionBody", true, false) as CollisionObject3D
	if collision_body != null:
		collision_body.remove_from_group("enemy")
		collision_body.collision_layer = 0
		collision_body.collision_mask = 0

	if _hp_bar != null:
		_hp_bar.visible = false
	visible = false
	emit_signal("gate_destroyed")
