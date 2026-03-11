@tool
extends Node3D

@export_dir var source_dir: String = "res://outputs/terrain_godot/terrain"
@export var cell_size: float = 128.0
@export var height_multiplier: float = 1.0
@export var create_collision: bool = true
@export var import_props: bool = true
@export var import_regions: bool = true
@export var region_height: float = 400.0
@export var rawcode_scene_map: Dictionary = {}
@export var import_now: bool = false:
	set(value):
		import_now = false
		if value:
			_import_all()


func _import_all() -> void:
	var metadata_path := source_dir.path_join("metadata.json")
	var props_path := source_dir.path_join("props.json")
	var regions_path := source_dir.path_join("regions.json")
	var height_path := source_dir.path_join("heightmap_16.png")

	var metadata := _read_json(metadata_path)
	if metadata.is_empty():
		push_error("metadata.json 读取失败: %s" % metadata_path)
		return

	var terrain_meta: Dictionary = metadata.get("terrain", {})
	var size_arr: Array = terrain_meta.get("size", [])
	if size_arr.size() < 2:
		push_error("metadata 缺少 terrain.size")
		return

	var w := int(size_arr[0])
	var h := int(size_arr[1])
	if w < 2 or h < 2:
		push_error("地形尺寸不合法: %s x %s" % [w, h])
		return

	var min_h := float(terrain_meta.get("groundHeightMin", 0.0))
	var max_h := float(terrain_meta.get("groundHeightMax", 0.0))

	var image := Image.new()
	var img_err := image.load(height_path)
	if img_err != OK:
		push_error("heightmap 读取失败: %s" % height_path)
		return

	if image.get_width() != w or image.get_height() != h:
		push_warning("heightmap 尺寸(%s,%s)与 metadata(%s,%s)不一致，按图片尺寸导入" % [
			image.get_width(), image.get_height(), w, h
		])
		w = image.get_width()
		h = image.get_height()

	_clear_old_nodes()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "TerrainMesh"
	mesh_instance.mesh = _build_terrain_mesh(image, w, h, min_h, max_h)
	add_child(mesh_instance)
	mesh_instance.owner = get_tree().edited_scene_root

	if create_collision:
		var body := StaticBody3D.new()
		body.name = "TerrainCollision"
		var shape_node := CollisionShape3D.new()
		var concave := ConcavePolygonShape3D.new()
		var faces := mesh_instance.mesh.get_faces()
		concave.set_faces(faces)
		shape_node.shape = concave
		body.add_child(shape_node)
		add_child(body)
		body.owner = get_tree().edited_scene_root
		shape_node.owner = get_tree().edited_scene_root

	if import_props:
		var props_data = _read_json(props_path)
		if props_data is Array:
			_import_props(props_data)
		else:
			push_warning("props.json 不可用，跳过物件导入")

	if import_regions:
		var regions_data = _read_json(regions_path)
		if regions_data is Array:
			_import_regions(regions_data)
		else:
			push_warning("regions.json 不可用，跳过区域导入")


func _build_terrain_mesh(image: Image, w: int, h: int, min_h: float, max_h: float) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	vertices.resize(w * h)
	normals.resize(w * h)
	uvs.resize(w * h)

	var range_h := max(0.000001, max_h - min_h)
	var half_w := float(w - 1) * 0.5
	var half_h := float(h - 1) * 0.5

	var idx := 0
	for y in range(h):
		for x in range(w):
			var c := image.get_pixel(x, y)
			var normalized_h := clamp(c.r, 0.0, 1.0)
			var world_h := lerp(min_h, max_h, normalized_h) * height_multiplier
			var world_x := (float(x) - half_w) * cell_size
			var world_z := (float(y) - half_h) * cell_size
			vertices[idx] = Vector3(world_x, world_h, world_z)
			uvs[idx] = Vector2(float(x) / float(max(1, w - 1)), float(y) / float(max(1, h - 1)))
			normals[idx] = Vector3.UP
			idx += 1

	for y in range(h - 1):
		for x in range(w - 1):
			var i0 := y * w + x
			var i1 := i0 + 1
			var i2 := i0 + w
			var i3 := i2 + 1
			indices.push_back(i0)
			indices.push_back(i2)
			indices.push_back(i1)
			indices.push_back(i1)
			indices.push_back(i2)
			indices.push_back(i3)

	_recompute_normals(vertices, indices, normals)

	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vertices
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return mesh


func _recompute_normals(vertices: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array) -> void:
	for i in range(normals.size()):
		normals[i] = Vector3.ZERO

	for i in range(0, indices.size(), 3):
		var ia := indices[i]
		var ib := indices[i + 1]
		var ic := indices[i + 2]
		var a := vertices[ia]
		var b := vertices[ib]
		var c := vertices[ic]
		var n := (b - a).cross(c - a).normalized()
		normals[ia] += n
		normals[ib] += n
		normals[ic] += n

	for i in range(normals.size()):
		normals[i] = normals[i].normalized()


func _import_props(props_data: Array) -> void:
	var props_root := Node3D.new()
	props_root.name = "TerrainProps"
	add_child(props_root)
	props_root.owner = get_tree().edited_scene_root

	for item in props_data:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var rawcode := String(d.get("rawcode", ""))
		var godot := d.get("godot", {})
		if not (godot is Dictionary):
			continue

		var pos_arr := godot.get("position", [])
		var scale_arr := godot.get("scale", [])
		var rot_y := float(godot.get("rotation_y_rad", 0.0))
		if pos_arr.size() < 3:
			continue

		var scene_path := String(rawcode_scene_map.get(rawcode, ""))
		var node: Node3D
		if scene_path != "" and ResourceLoader.exists(scene_path):
			var packed := load(scene_path)
			if packed is PackedScene:
				node = (packed as PackedScene).instantiate() as Node3D
			else:
				node = Node3D.new()
		else:
			node = Node3D.new()

		node.name = "%s_%s" % [rawcode, int(d.get("index", 0))]
		node.position = Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2]))
		node.rotation.y = rot_y
		if scale_arr.size() >= 3:
			node.scale = Vector3(float(scale_arr[0]), float(scale_arr[1]), float(scale_arr[2]))
		props_root.add_child(node)
		node.owner = get_tree().edited_scene_root


func _import_regions(regions_data: Array) -> void:
	var root := Node3D.new()
	root.name = "TerrainRegions"
	add_child(root)
	root.owner = get_tree().edited_scene_root

	for item in regions_data:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		var region_name := String(d.get("name", "Region"))
		var godot := d.get("godot", {})
		if not (godot is Dictionary):
			continue
		var center := godot.get("center", [])
		var size := godot.get("size", [])
		if center.size() < 2 or size.size() < 2:
			continue

		var area := Area3D.new()
		area.name = region_name
		var shape_node := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(size[0]), region_height, float(size[1]))
		shape_node.shape = box
		area.position = Vector3(float(center[0]), region_height * 0.5, float(center[1]))
		area.add_child(shape_node)
		root.add_child(area)
		area.owner = get_tree().edited_scene_root
		shape_node.owner = get_tree().edited_scene_root


func _read_json(file_path: String) -> Variant:
	if not FileAccess.file_exists(file_path):
		return {}
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	var parsed := JSON.parse_string(txt)
	if parsed == null:
		return {}
	return parsed


func _clear_old_nodes() -> void:
	var names := ["TerrainMesh", "TerrainCollision", "TerrainProps", "TerrainRegions"]
	for n in names:
		var node := get_node_or_null(n)
		if node:
			node.queue_free()
