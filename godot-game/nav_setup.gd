extends NavigationRegion3D

func _ready() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 15.0
	nav_mesh.cell_height = 5.0
	nav_mesh.agent_height = 150.0
	nav_mesh.agent_radius = 70.0
	nav_mesh.agent_max_climb = 10.0
	nav_mesh.agent_max_slope = 45.0
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navigation_mesh = nav_mesh
	call_deferred("_bake")


func _bake() -> void:
	bake_navigation_mesh()
