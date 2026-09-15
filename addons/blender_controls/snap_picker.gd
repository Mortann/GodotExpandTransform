@tool
extends RefCounted
## Physics-independent snapping against static meshes and rendered CSG results.
## Call rebuild after scene geometry/transforms change. Imported child meshes are
## included. Hidden branches and excluded roots are omitted. Locked objects can
## serve as read-only snap references. No triangle
## budget silently drops geometry; rebuilding a large scene can take time.
## Adjacent coplanar triangles form one face; internal diagonals are not edges.
## Skeleton, blend shape, shader deformation and MultiMesh are outside its scope.

const CELL_SIZE := 32.0
const EPSILON := 0.00001

var _records: Array[Dictionary] = []
var _projection_key: Array = []
var _triangle_count := 0


func rebuild(root: Node, excluded_roots: Array[Node3D] = []) -> void:
	_records.clear()
	_projection_key.clear()
	_triangle_count = 0
	if is_instance_valid(root):
		_collect(root, excluded_roots)


func get_statistics() -> Dictionary:
	return {"meshes": _records.size(), "triangles": _triangle_count}


func pick(camera: Camera3D, screen: Vector2, pixel_radius: float = 14.0) -> Dictionary:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return {}
	if pixel_radius < 0.0:
		return {}
	_ensure_projection(camera)
	var vertices: Array[Dictionary] = []
	var radius_squared := pixel_radius * pixel_radius
	for record in _records:
		if not _record_visible(record, camera):
			continue
		for index in _query_grid(record.vertex_grid, screen, pixel_radius, false):
			var projected: Vector2 = record.projected_vertices[index]
			var distance := projected.distance_squared_to(screen)
			if distance <= radius_squared:
				vertices.append(_candidate(record, record.vertices[index],
					record.normals[index], "Vertex", projected, distance,
					PackedVector3Array([record.vertices[index]])))
	var vertex_hit := _first_visible(camera, vertices)
	if not vertex_hit.is_empty():
		return vertex_hit
	# Most pointer updates find a vertex. Build edge candidates only when needed.
	var edges: Array[Dictionary] = []
	for record in _records:
		if not _record_visible(record, camera):
			continue
		for index in _query_grid(record.edge_grid, screen, pixel_radius):
			var a: Vector2 = record.projected_edges[index * 2]
			var b: Vector2 = record.projected_edges[index * 2 + 1]
			var delta := b - a
			var t := clampf((screen - a).dot(delta) / maxf(delta.length_squared(), EPSILON), 0.0, 1.0)
			var projected := a.lerp(b, t)
			var distance := projected.distance_squared_to(screen)
			if distance > radius_squared:
				continue
			var world_a: Vector3 = record.clipped_edges[index * 2]
			var world_b: Vector3 = record.clipped_edges[index * 2 + 1]
			if camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
				var view_inverse := camera.get_camera_transform().affine_inverse()
				var depth_a: float = -(view_inverse * world_a).z
				var depth_b: float = -(view_inverse * world_b).z
				t = t * depth_a / maxf((1.0 - t) * depth_b + t * depth_a, EPSILON)
			var position := world_a.lerp(world_b, t)
			var vertex_index: int = record.edges[index * 2]
			edges.append(_candidate(record, position, record.normals[vertex_index],
				"Edge", projected, distance, PackedVector3Array([
					record.vertices[vertex_index], record.vertices[record.edges[index * 2 + 1]]])))
	# Prefer a visible vertex, then an edge, then the surface directly under the
	# pointer. Each feature gets its own occlusion ray, not the pointer's ray.
	var edge_hit := _first_visible(camera, edges)
	if not edge_hit.is_empty():
		return edge_hit
	return _raycast(camera, screen)


func _first_visible(camera: Camera3D, candidates: Array[Dictionary]) -> Dictionary:
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.distance < b.distance)
	for candidate in candidates:
		if _feature_visible(camera, candidate):
			return _public_hit(candidate, camera.project_ray_normal(candidate.screen))
	return {}


func _collect(node: Node, excluded_roots: Array[Node3D]) -> void:
	if node is Node3D:
		if excluded_roots.has(node) or not node.is_visible_in_tree():
			return
	if node is MeshInstance3D and node.mesh != null:
		_cache_mesh(node, node.mesh)
	elif node is CSGShape3D and node.is_root_shape():
		var affected := false
		for excluded in excluded_roots:
			if node.is_ancestor_of(excluded):
				affected = true
				break
		if not affected:
			# The renderer exposes the evaluated boolean result on the CSG root.
			# Do not cache each operand separately: subtraction interiors are not
			# visible geometry, and moving a child changes the whole result.
			var meshes: Array = node.get_meshes()
			if meshes.size() >= 2 and meshes[1] is Mesh:
				_cache_mesh(node, meshes[1])
	for child in node.get_children():
		_collect(child, excluded_roots)


func _cache_mesh(node: GeometryInstance3D, mesh: Mesh) -> void:
	var faces: PackedVector3Array = mesh.get_faces()
	if faces.size() < 3:
		return
	var world := node.global_transform
	for i in faces.size():
		faces[i] = world * faces[i]
	var triangles := TriangleMesh.new()
	if not triangles.create_from_faces(faces):
		push_warning("Blender Controls: unable to build snapping geometry for %s." % node.name)
		return
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var edges := PackedInt32Array()
	var vertex_map: Dictionary = {}
	var edge_map: Dictionary = {}
	var face_normals := PackedVector3Array()
	var parents: Array[int] = []
	for index in range(faces.size() / 3):
		parents.append(index)
		face_normals.append(Vector3.ZERO)
	var bounds := AABB(faces[0], Vector3.ZERO)
	for triangle in range(0, faces.size() - 2, 3):
		var a := faces[triangle]
		var b := faces[triangle + 1]
		var c := faces[triangle + 2]
		var normal := (b - a).cross(c - a).normalized()
		var face_index := triangle / 3
		face_normals[face_index] = normal
		if normal.length_squared() < EPSILON:
			continue
		var indices: Array[int] = []
		for position in [a, b, c]:
			if not vertex_map.has(position):
				vertex_map[position] = vertices.size()
				vertices.append(position)
				normals.append(normal)
				bounds = bounds.expand(position)
			indices.append(vertex_map[position])
		for corner in 3:
			var first := indices[corner]
			var second := indices[(corner + 1) % 3]
			var edge_key := Vector2i(mini(first, second), maxi(first, second))
			if not edge_map.has(edge_key):
				edge_map[edge_key] = []
			edge_map[edge_key].append(face_index)
	# Merge adjacent coplanar triangles into one visible face. In particular,
	# a cube face must light up as a square, without snapping its hidden diagonal.
	var boundary_edges: Dictionary = {}
	for edge: Vector2i in edge_map:
		var adjacent: Array = edge_map[edge]
		if adjacent.size() == 2 and face_normals[adjacent[0]].dot(face_normals[adjacent[1]]) > 0.99999:
			parents[_face_root(parents, adjacent[1])] = _face_root(parents, adjacent[0])
		else:
			boundary_edges[edge] = adjacent
			edges.append(edge.x)
			edges.append(edge.y)
	var patches: Dictionary = {}
	for index in parents.size():
		var group := _face_root(parents, index)
		parents[index] = group
		if not patches.has(group):
			patches[group] = {"points": [], "boundary": []}
		for corner in 3:
			patches[group].points.append(faces[index * 3 + corner])
	for edge: Vector2i in boundary_edges:
		var visited: Dictionary = {}
		for index in boundary_edges[edge]:
			var group: int = parents[index]
			if visited.has(group):
				continue
			visited[group] = true
			patches[group].boundary.append(vertices[edge.x])
			patches[group].boundary.append(vertices[edge.y])
	for group in patches:
		patches[group].points = PackedVector3Array(patches[group].points)
		patches[group].boundary = PackedVector3Array(patches[group].boundary)
	_records.append({"node": node, "triangles": triangles, "bounds": bounds.grow(EPSILON),
		"face_groups": parents, "patches": patches,
		"vertices": vertices, "normals": normals, "edges": edges,
		"vertex_grid": {}, "edge_grid": {}, "projected_vertices": PackedVector2Array(),
		"projected_edges": PackedVector2Array(), "clipped_edges": PackedVector3Array()})
	_triangle_count += faces.size() / 3


static func _face_root(parents: Array[int], index: int) -> int:
	while parents[index] != index:
		parents[index] = parents[parents[index]]
		index = parents[index]
	return index


func _record_visible(record: Dictionary, camera: Camera3D) -> bool:
	if not is_instance_valid(record.node):
		return false
	var node: GeometryInstance3D = record.node
	return node.is_inside_tree() and node.is_visible_in_tree() \
		and (node.layers & camera.cull_mask) != 0


func _ensure_projection(camera: Camera3D) -> void:
	var viewport_rect := camera.get_viewport().get_visible_rect()
	var key: Array = [camera.get_instance_id(), camera.get_camera_transform(),
		camera.get_camera_projection(), viewport_rect]
	if key == _projection_key:
		return
	_projection_key = key
	var view_inverse := camera.get_camera_transform().affine_inverse()
	for record in _records:
		var vertex_grid: Dictionary = {}
		var edge_grid: Dictionary = {}
		var projected_vertices := PackedVector2Array()
		projected_vertices.resize(record.vertices.size())
		for index in record.vertices.size():
			var position: Vector3 = record.vertices[index]
			if not camera.is_position_in_frustum(position):
				continue
			var projected := camera.unproject_position(position)
			projected_vertices[index] = projected
			_grid_add(vertex_grid, _cell(projected), index)
		var projected_edges := PackedVector2Array()
		var clipped_edges := PackedVector3Array()
		projected_edges.resize(record.edges.size())
		clipped_edges.resize(record.edges.size())
		for index in range(record.edges.size() / 2):
			var a: Vector3 = record.vertices[record.edges[index * 2]]
			var b: Vector3 = record.vertices[record.edges[index * 2 + 1]]
			var depth_a: float = -(view_inverse * a).z
			var depth_b: float = -(view_inverse * b).z
			var clipped := _clip_depth(a, b, depth_a, depth_b, camera.near, camera.far)
			if clipped.is_empty():
				continue
			a = clipped[0]
			b = clipped[1]
			var screen_a := camera.unproject_position(a)
			var screen_b := camera.unproject_position(b)
			projected_edges[index * 2] = screen_a
			projected_edges[index * 2 + 1] = screen_b
			clipped_edges[index * 2] = a
			clipped_edges[index * 2 + 1] = b
			var visible_segment := _clip_screen(screen_a, screen_b, viewport_rect)
			if visible_segment.is_empty():
				continue
			_index_edge(edge_grid, visible_segment[0], visible_segment[1], index)
		record.vertex_grid = vertex_grid
		record.edge_grid = edge_grid
		record.projected_vertices = projected_vertices
		record.projected_edges = projected_edges
		record.clipped_edges = clipped_edges


static func _clip_depth(a: Vector3, b: Vector3, depth_a: float, depth_b: float,
		near: float, far: float) -> PackedVector3Array:
	var delta := depth_b - depth_a
	if absf(delta) < EPSILON:
		return PackedVector3Array([a, b]) if depth_a >= near and depth_a <= far else PackedVector3Array()
	var t_near := (near - depth_a) / delta
	var t_far := (far - depth_a) / delta
	var start := maxf(0.0, minf(t_near, t_far))
	var end := minf(1.0, maxf(t_near, t_far))
	if start > end:
		return PackedVector3Array()
	return PackedVector3Array([a.lerp(b, start), a.lerp(b, end)])


static func _clip_screen(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	var delta := b - a
	var start := 0.0
	var end := 1.0
	for axis in 2:
		if absf(delta[axis]) < EPSILON:
			if a[axis] < rect.position[axis] or a[axis] > rect.end[axis]:
				return PackedVector2Array()
			continue
		var enter := (rect.position[axis] - a[axis]) / delta[axis]
		var leave := (rect.end[axis] - a[axis]) / delta[axis]
		start = maxf(start, minf(enter, leave))
		end = minf(end, maxf(enter, leave))
		if start > end:
			return PackedVector2Array()
	return PackedVector2Array([a.lerp(b, start), a.lerp(b, end)])


static func _cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.y / CELL_SIZE))


static func _grid_add(grid: Dictionary, cell: Vector2i, index: int) -> void:
	if not grid.has(cell):
		grid[cell] = []
	grid[cell].append(index)


static func _index_edge(grid: Dictionary, a: Vector2, b: Vector2, index: int) -> void:
	# Sample at most one cell width apart. Queries include one neighboring cell,
	# covering corner crossings without storing an entire segment bounding box.
	var span := b - a
	var steps := maxi(1, ceili(maxf(absf(span.x), absf(span.y)) / CELL_SIZE))
	var previous := Vector2i(2147483647, 2147483647)
	for step in range(steps + 1):
		var cell := _cell(a.lerp(b, float(step) / steps))
		if cell != previous:
			_grid_add(grid, cell, index)
			previous = cell


static func _query_grid(grid: Dictionary, point: Vector2, radius: float,
		edge_neighbors: bool = true) -> Array:
	var padding := Vector2i.ONE if edge_neighbors else Vector2i.ZERO
	var begin := _cell(point - Vector2.ONE * radius) - padding
	var end := _cell(point + Vector2.ONE * radius) + padding
	var unique: Dictionary = {}
	for x in range(begin.x, end.x + 1):
		for y in range(begin.y, end.y + 1):
			for index in grid.get(Vector2i(x, y), []):
				unique[index] = true
	return unique.keys()


static func _candidate(record: Dictionary, position: Vector3, normal: Vector3,
		kind: String, screen: Vector2, distance: float, points: PackedVector3Array) -> Dictionary:
	return {"position": position, "normal": normal, "kind": kind,
		"node": record.node, "screen": screen, "distance": distance, "feature_points": points}


func _feature_visible(camera: Camera3D, candidate: Dictionary) -> bool:
	var hit := _raycast(camera, candidate.screen)
	if hit.is_empty():
		return true
	var origin := camera.project_ray_origin(candidate.screen)
	var candidate_distance := origin.distance_to(candidate.position)
	var tolerance := maxf(0.0001, candidate_distance * EPSILON)
	return origin.distance_to(hit.position) >= candidate_distance - tolerance


func _raycast(camera: Camera3D, screen: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen).normalized()
	var best: Dictionary = {}
	var best_distance := INF
	for record in _records:
		if not _record_visible(record, camera):
			continue
		var bounds: AABB = record.bounds
		if bounds.intersects_ray(origin, direction) == null:
			continue
		var triangles: TriangleMesh = record.triangles
		var hit := triangles.intersect_ray(origin, direction)
		if hit.is_empty() or not camera.is_position_in_frustum(hit.position):
			continue
		var distance: float = origin.distance_squared_to(hit.position)
		if distance < best_distance:
			best_distance = distance
			var patch: Dictionary = record.patches[record.face_groups[hit.face_index]]
			best = {"position": hit.position, "normal": hit.normal,
				"kind": "Face", "node": record.node,
				"feature_points": patch.points, "boundary_points": patch.boundary}
	return _public_hit(best, direction)


static func _public_hit(hit: Dictionary, ray_direction: Vector3) -> Dictionary:
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit.normal
	if normal.dot(ray_direction) > 0.0:
		normal = -normal
	return {"position": hit.position, "normal": normal.normalized(),
		"kind": hit.kind, "node": hit.node,
		"feature_points": hit.get("feature_points", PackedVector3Array([hit.position])),
		"boundary_points": hit.get("boundary_points", PackedVector3Array())}
