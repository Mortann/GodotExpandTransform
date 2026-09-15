extends SceneTree

const Picker = preload("res://addons/blender_controls/snap_picker.gd")

var _failures := 0
var _checks := 0
var _viewport: SubViewport
var _scene: Node3D
var _camera: Camera3D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(800, 600)
	root.add_child(_viewport)
	_scene = Node3D.new()
	_viewport.add_child(_scene)
	_camera = Camera3D.new()
	_scene.add_child(_camera)
	_camera.position = Vector3(0, 0, 6)
	_camera.current = true
	await process_frame
	_test_features()
	_test_occlusion()
	_test_exclusions()
	_test_perspective_edge()
	_test_clipping()
	_test_highlight_geometry()
	await _test_csg()
	_test_large_mesh()
	print("Snap picker: %d checks, %d failures" % [_checks, _failures])
	_viewport.free()
	quit(1 if _failures else 0)


func _test_features() -> void:
	var node := _mesh(PackedVector3Array([
		Vector3(-2, -1, 0), Vector3(2, -1, 0), Vector3(0, 2, 0)]))
	var picker = Picker.new()
	picker.rebuild(_scene)
	var hit: Dictionary = picker.pick(_camera, _screen(Vector3.ZERO), 3.0)
	_check(hit.get("kind") == "Face", "triangle interior falls back to face")
	_check(_position_near(hit, Vector3.ZERO), "surface ray hits world-space triangle")
	hit = picker.pick(_camera, _screen(Vector3(-2, -1, 0)) + Vector2(2, 1))
	_check(hit.get("kind") == "Vertex", "vertex inside pixel radius has priority")
	_check(_position_near(hit, Vector3(-2, -1, 0)), "vertex position is exact")
	hit = picker.pick(_camera, _screen(Vector3(0, -1, 0)))
	_check(hit.get("kind") == "Edge", "edge midpoint snaps without nearby vertex")
	_check(_position_near(hit, Vector3(0, -1, 0)), "edge position is exact")
	_check(picker.pick(_camera, Vector2(10, 10)).is_empty(), "empty space returns empty dictionary")
	_check(hit.has("normal") and hit.has("node"), "public result contains normal and node")
	_check(hit.normal.dot(_camera.project_ray_normal(_screen(hit.position))) <= 0.0,
		"returned normal faces the viewer")
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = 8.0
	hit = picker.pick(_camera, _screen(Vector3(0, -1, 0)))
	_check(hit.get("kind") == "Edge" and _position_near(hit, Vector3(0, -1, 0)),
		"orthographic projection invalidates cache and preserves edge snapping")
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	node.free()


func _test_occlusion() -> void:
	var back := _mesh(PackedVector3Array([
		Vector3.ZERO, Vector3(2, -1, 0), Vector3(-2, -1, 0)]))
	var front := _quad(1.0, 3.0)
	var picker = Picker.new()
	picker.rebuild(_scene)
	var hit: Dictionary = picker.pick(_camera, _screen(Vector3.ZERO))
	_check(hit.get("node") == front, "occluded back vertex never wins over front geometry")
	_check(absf(hit.get("position", Vector3.ZERO).z - 1.0) < 0.001, "occluder hit is on front plane")
	front.layers = 2
	_camera.cull_mask = 1
	hit = picker.pick(_camera, _screen(Vector3.ZERO))
	_check(hit.get("node") == back, "camera layer mask removes invisible occluders")
	_camera.cull_mask = 1048575
	front.hide()
	hit = picker.pick(_camera, _screen(Vector3.ZERO))
	_check(hit.get("node") == back, "visibility changes take effect without rebuild")
	front.free()
	back.free()


func _test_exclusions() -> void:
	var group := Node3D.new()
	_scene.add_child(group)
	var child := _quad(0.0, 2.0)
	child.reparent(group)
	var picker = Picker.new()
	picker.rebuild(_scene)
	_check(picker.get_statistics().meshes == 1, "ownerless and imported child meshes can snap")
	var excluded: Array[Node3D] = [group]
	picker.rebuild(_scene, excluded)
	_check(picker.get_statistics().meshes == 0, "excluding a root excludes descendants")
	group.set_meta("_edit_lock_", true)
	picker.rebuild(_scene)
	_check(picker.get_statistics().meshes == 1, "locked geometry remains a read-only snapping reference")
	group.remove_meta("_edit_lock_")
	group.hide()
	picker.rebuild(_scene)
	_check(picker.get_statistics().meshes == 0, "hidden parent excludes descendant geometry")
	group.show()
	group.position = Vector3(2, 0, 0)
	picker.rebuild(_scene)
	var hit: Dictionary = picker.pick(_camera, _screen(Vector3(2, 0, 0)), 0.0)
	_check(not hit.is_empty() and absf(hit.position.x - 2.0) < 0.001,
		"hierarchical global transforms are included")
	group.free()
	_check(picker.pick(_camera, _screen(Vector3.ZERO)).is_empty(), "freed nodes are ignored safely")


func _test_perspective_edge() -> void:
	var a := Vector3(-2, -1, 2)
	var b := Vector3(2, -1, -2)
	var node := _mesh(PackedVector3Array([a, b, Vector3(0, 3, 0)]))
	var picker = Picker.new()
	picker.rebuild(_scene)
	var target := _screen(a).lerp(_screen(b), 0.5)
	var hit: Dictionary = picker.pick(_camera, target, 3.0)
	_check(hit.get("kind") == "Edge", "slanted perspective edge is selected")
	_check(not hit.is_empty() and _screen(hit.position).distance_to(target) < 0.001,
		"edge interpolation is perspective-correct")
	_check(not hit.is_empty() and hit.position.distance_to(a.lerp(b, 1.0 / 3.0)) < 0.001,
		"screen midpoint maps to the correct non-midpoint in world space")
	node.free()


func _test_clipping() -> void:
	var clipped: PackedVector3Array = Picker._clip_depth(
		Vector3(0, 0, -1), Vector3(0, 0, 5), -1.0, 5.0, 0.1, 4.0)
	_check(clipped.size() == 2 and absf(clipped[0].z - 0.1) < 0.001 and
		absf(clipped[1].z - 4.0) < 0.001, "near and far clipping preserves crossing segments")
	var screen_clip: PackedVector2Array = Picker._clip_screen(
		Vector2(-1000, 300), Vector2(2000, 300), Rect2(0, 0, 800, 600))
	_check(screen_clip.size() == 2 and screen_clip[0].is_equal_approx(Vector2(0, 300)) and
		screen_clip[1].is_equal_approx(Vector2(800, 300)), "off-screen edges are clipped before indexing")
	var grid: Dictionary = {}
	Picker._index_edge(grid, Vector2(1, 1), Vector2(799, 599), 7)
	_check(Picker._query_grid(grid, Vector2(399, 299), 1.0).has(7),
		"screen grid finds a long diagonal near cell boundaries")


func _test_large_mesh() -> void:
	var sphere := SphereMesh.new()
	sphere.radial_segments = 128
	sphere.rings = 64
	var node := MeshInstance3D.new()
	node.mesh = sphere
	_scene.add_child(node)
	var picker = Picker.new()
	var started := Time.get_ticks_msec()
	picker.rebuild(_scene)
	var expected: int = sphere.get_faces().size() / 3
	_check(picker.get_statistics().triangles == expected, "all triangles are cached without a hidden budget")
	var hit: Dictionary = picker.pick(_camera, _screen(Vector3.ZERO))
	_check(not hit.is_empty(), "dense mesh remains snappable")
	var first_duration := Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	for i in 10:
		picker.pick(_camera, Vector2(400 + i, 300))
	print("Dense mesh: %d triangles, rebuild + first pick %d ms, cached pick average %.1f ms" % [
		expected, first_duration, float(Time.get_ticks_msec() - started) / 10.0])
	node.free()


func _test_highlight_geometry() -> void:
	var node := _quad(0.0, 2.0)
	var picker = Picker.new()
	picker.rebuild(_scene)
	var hit: Dictionary = picker.pick(_camera, _screen(Vector3.ZERO), 3.0)
	_check(hit.kind == "Face", "coplanar triangulation diagonal is not a snap edge")
	_check(hit.feature_points.size() == 6, "face highlight includes both triangles of quad")
	_check(hit.boundary_points.size() == 8, "face highlight boundary contains four edges")
	hit = picker.pick(_camera, _screen(Vector3(0, -2, 0)), 3.0)
	_check(hit.kind == "Edge" and hit.feature_points.size() == 2, "edge highlight returns complete endpoints")
	_check(hit.feature_points.has(Vector3(-2, -2, 0)) and hit.feature_points.has(Vector3(2, -2, 0)), "edge endpoints span the whole edge")
	hit = picker.pick(_camera, _screen(Vector3(-2, -2, 0)), 3.0)
	_check(hit.kind == "Vertex" and hit.feature_points.size() == 1, "vertex highlight returns one point")
	node.free()


func _test_csg() -> void:
	var box := CSGBox3D.new()
	box.size = Vector3(2, 2, 2)
	_scene.add_child(box)
	box.position = Vector3(1, 0, 0)
	for i in 3:
		await process_frame
	var picker = Picker.new()
	picker.rebuild(_scene)
	_check(picker.get_statistics().meshes == 1, "standalone CSG box is cached")
	var hit: Dictionary = picker.pick(_camera, _screen(Vector3(1, 0, 1)), 3.0)
	_check(hit.get("kind") == "Face" and _position_near(hit, Vector3(1, 0, 1)), "CSG face snap has correct world transform")
	_check(hit.get("feature_points", []).size() == 6, "CSG box face highlighted as whole square")
	hit = picker.pick(_camera, _screen(Vector3(1, -1, 1)), 3.0)
	_check(hit.get("kind") == "Edge", "CSG edge snaps")
	hit = picker.pick(_camera, _screen(Vector3(2, -1, 1)), 3.0)
	_check(hit.get("kind") == "Vertex", "CSG vertex snaps")
	var exclusions: Array[Node3D] = [box]
	picker.rebuild(_scene, exclusions)
	_check(picker.get_statistics().meshes == 0, "moving CSG root is excluded from targets")
	box.free()
	# A through-hole proves the picker uses the rendered boolean result rather
	# than overlapping source primitives (which would fill the hole back in).
	var combiner := CSGCombiner3D.new()
	_scene.add_child(combiner)
	var solid := CSGBox3D.new()
	solid.size = Vector3(4, 4, 2)
	combiner.add_child(solid)
	var cutter := CSGBox3D.new()
	cutter.size = Vector3(1, 1, 4)
	cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
	combiner.add_child(cutter)
	for i in 3:
		await process_frame
	picker.rebuild(_scene)
	_check(picker.get_statistics().meshes == 1, "CSG combiner cached once, without duplicate operands")
	hit = picker.pick(_camera, _screen(Vector3.ZERO), 0.0)
	_check(hit.is_empty(), "subtracted CSG hole stays empty")
	hit = picker.pick(_camera, _screen(Vector3(1.5, 0, 1)), 0.0)
	_check(not hit.is_empty() and hit.node == combiner, "remaining CSG surface remains snappable")
	exclusions = [cutter]
	picker.rebuild(_scene, exclusions)
	_check(picker.get_statistics().meshes == 0, "moving CSG operand excludes dependent boolean result")
	combiner.position = Vector3(-1, 0, -1)
	combiner.rotation.y = 0.3
	for i in 3:
		await process_frame
	picker.rebuild(_scene)
	var target := combiner.global_transform * Vector3(1.5, 0, 1)
	hit = picker.pick(_camera, _screen(target), 0.0)
	_check(_position_near(hit, target), "CSG result follows translated and rotated root")
	combiner.free()


func _mesh(faces: PackedVector3Array) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = faces
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	_scene.add_child(node)
	return node


func _quad(z: float, size: float) -> MeshInstance3D:
	return _mesh(PackedVector3Array([
		Vector3(-size, -size, z), Vector3(size, -size, z), Vector3(size, size, z),
		Vector3(-size, -size, z), Vector3(size, size, z), Vector3(-size, size, z)]))


func _screen(position: Vector3) -> Vector2:
	return _camera.unproject_position(position)


func _position_near(hit: Dictionary, expected: Vector3) -> bool:
	return hit.has("position") and hit.position.distance_to(expected) < 0.001


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
