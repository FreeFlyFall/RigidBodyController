extends Node

func line(pos1: Vector3, pos2: Vector3, color = Color.WHITE_SMOKE, persist_seconds = 0):
	var mesh_instance := MeshInstance3D.new()
	var immediate_mesh := ImmediateMesh.new()
	var material := ORMMaterial3D.new()

	mesh_instance.mesh = immediate_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate_mesh.surface_add_vertex(pos1)
	immediate_mesh.surface_add_vertex(pos2)
	immediate_mesh.surface_end()

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color

	return await final_cleanup(mesh_instance, persist_seconds)

func point(pos: Vector3, radius = 0.05, color = Color.WHITE_SMOKE, persist_seconds = 0):
	var mesh_instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	var material := ORMMaterial3D.new()

	mesh_instance.mesh = sphere_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.position = pos

	sphere_mesh.radius = radius
	sphere_mesh.height = radius*2
	sphere_mesh.material = material

	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color

	return await final_cleanup(mesh_instance, persist_seconds)

func final_cleanup(mesh_instance: MeshInstance3D, persist_seconds: float):
	get_tree().get_root().add_child(mesh_instance)
	if persist_seconds == 0:
		await get_tree().physics_frame
		mesh_instance.queue_free()
	elif persist_seconds > 0:
		await get_tree().create_timer(persist_seconds).timeout
		mesh_instance.queue_free()
	else:
		return mesh_instance
