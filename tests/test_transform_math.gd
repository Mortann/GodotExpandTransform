extends SceneTree

const TransformMath = preload("res://addons/blender_controls/transform_math.gd")
var failures := 0
var checks := 0


func _initialize() -> void:
	_test_constraints()
	_test_composition()
	_test_snap()
	call_deferred("_test_projection")


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)


func _vector(actual: Vector3, expected: Vector3, label: String) -> void:
	_check(actual.is_equal_approx(expected), "%s: got %s, expected %s" % [label, actual, expected])


func _transform(actual: Transform3D, expected: Transform3D, label: String) -> void:
	_check(actual.is_equal_approx(expected), "%s: got %s, expected %s" % [label, actual, expected])


func _test_constraints() -> void:
	var delta := Vector3(2, 3, 4)
	_vector(TransformMath.constrain_vector(delta, -1, false, Basis.IDENTITY), delta, "free")
	for axis in range(3):
		var expected := Vector3.ZERO
		expected[axis] = delta[axis]
		_vector(TransformMath.constrain_vector(delta, axis, false, Basis.IDENTITY), expected, "axis %d" % axis)
		_vector(TransformMath.constrain_vector(delta, axis, true, Basis.IDENTITY), delta - expected, "plane %d" % axis)
	var orientation := Basis(Vector3.BACK, PI / 2.0)
	_vector(TransformMath.constrain_vector(delta, 0, false, orientation), Vector3(0, 3, 0), "local X")
	_vector(TransformMath.constrain_vector(delta, 0, true, orientation), Vector3(2, 0, 4), "local YZ")
	var frame: Basis = TransformMath.constraint_basis(true, orientation * Basis.from_scale(Vector3(2, 3, 4)))
	_check(frame.is_equal_approx(orientation), "constraint frame removes scale")
	_check(TransformMath.constraint_basis(false, orientation).is_equal_approx(Basis.IDENTITY), "global basis")
	_check(TransformMath.constraint_basis(true, Basis.from_scale(Vector3.ZERO)).is_finite(), "collapsed frame finite")
	_check(absf(TransformMath.constraint_basis(true, Basis.from_scale(Vector3.ZERO)).determinant() - 1.0) < 0.00001, "collapsed frame orthogonal")


func _test_composition() -> void:
	var pivot := Vector3(1, 2, 3)
	var parent := Transform3D(Basis(Vector3(1, 2, 3).normalized(), 0.7) * Basis.from_scale(Vector3(2, 0.5, 3)), Vector3(-4, 2, 1))
	var local := Transform3D(Basis(Vector3(2, 1, 3).normalized(), 0.4) * Basis.from_scale(Vector3(0.5, 4, -2)), Vector3(3, -1, 2))
	var start := parent * local
	var delta := Vector3(2, -3, 4)
	var moved: Transform3D = TransformMath.translated(start, delta)
	_transform(moved, Transform3D(Basis.IDENTITY, delta) * start, "translation retains full basis")
	_transform(parent * (parent.affine_inverse() * moved), moved, "parent conversion after translation")
	var axis := Vector3(2, 5, -3).normalized()
	var angle := 0.9
	var rotation := Basis(axis, angle)
	var rotated: Transform3D = TransformMath.rotated(start, pivot, axis, angle)
	var expected := Transform3D(Basis.IDENTITY, pivot) * Transform3D(rotation, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot) * start
	_transform(rotated, expected, "rotation composition with sheared global basis")
	_transform(parent * (parent.affine_inverse() * rotated), expected, "parent conversion after rotation")
	_transform(TransformMath.rotated(rotated, pivot, axis, -angle), start, "rotation reversible")
	var frame := Basis(Vector3(1, 3, 2).normalized(), 0.6)
	var factors := Vector3(1.7, 0.3, -2)
	var scaling := frame * Basis.from_scale(factors) * frame.inverse()
	var scaled: Transform3D = TransformMath.scaled(start, pivot, factors, frame)
	expected = Transform3D(Basis.IDENTITY, pivot) * Transform3D(scaling, Vector3.ZERO) * Transform3D(Basis.IDENTITY, -pivot) * start
	_transform(scaled, expected, "scale composition retains shear and mirrors")
	_transform(parent * (parent.affine_inverse() * scaled), expected, "parent conversion after scale")
	_transform(TransformMath.scaled(scaled, pivot, Vector3.ONE / factors, frame), start, "scale reversible")
	var second := Transform3D(Basis.IDENTITY, pivot + Vector3.RIGHT * 2)
	_vector(TransformMath.rotated(second, pivot, Vector3.BACK, PI / 2).origin, pivot + Vector3.UP * 2, "shared rotation pivot")
	_vector(TransformMath.scaled(second, pivot, Vector3(3, 1, 1), Basis.IDENTITY).origin, pivot + Vector3.RIGHT * 6, "shared scale pivot")
	_transform(TransformMath.rotated(start, pivot, Vector3.ZERO, angle), start, "invalid rotation axis safe")


func _test_snap() -> void:
	var pivot := Vector3(3, 4, 5)
	_check(is_equal_approx(TransformMath.snap_rotation_angle(pivot, pivot + Vector3.RIGHT, pivot + Vector3.UP, Vector3.BACK), PI / 2), "rotation snap signed angle")
	_check(is_equal_approx(TransformMath.snap_rotation_angle(pivot, pivot + Vector3.RIGHT, pivot + Vector3.DOWN, Vector3.BACK), -PI / 2), "rotation snap negative angle")
	_check(is_equal_approx(TransformMath.snap_rotation_angle(pivot, pivot + Vector3(1, 0, 7), pivot + Vector3(0, 2, -3), Vector3.BACK), PI / 2), "rotation projects reference vectors")
	_check(TransformMath.snap_rotation_angle(pivot, pivot, pivot + Vector3.UP, Vector3.BACK) == 0.0, "degenerate rotation source")
	_check(TransformMath.snap_rotation_angle(pivot, pivot + Vector3.RIGHT, pivot, Vector3.BACK) == 0.0, "degenerate rotation target")
	# Target length is 5; source projection onto its unit direction is 2.
	_check(is_equal_approx(TransformMath.snap_scale_factor(pivot, pivot + Vector3(1, 2, 0), pivot + Vector3(4, 3, 0), -1, false, Basis.IDENTITY), 2.5), "Blender scale projected-reference ratio")
	_check(is_equal_approx(TransformMath.snap_scale_factor(pivot, pivot + Vector3(2, 3, 4), pivot + Vector3(6, -2, 10), 0, false, Basis.IDENTITY), 3), "axis scale snap")
	_check(is_equal_approx(TransformMath.snap_scale_factor(pivot, pivot + Vector3(1, 2, 8), pivot + Vector3(2, 4, -7), 2, true, Basis.IDENTITY), 2), "plane scale ignores excluded axis")
	var frame := Basis(Vector3.BACK, PI / 2)
	_check(is_equal_approx(TransformMath.snap_scale_factor(pivot, pivot + Vector3(7, 2, 0), pivot + Vector3(-8, 6, 0), 0, false, frame), 3), "local scale snap")
	_check(TransformMath.snap_scale_factor(pivot, pivot, pivot + Vector3.UP, -1, false, frame) == 1.0, "degenerate scale source")
	_check(TransformMath.snap_scale_factor(pivot, pivot + Vector3.RIGHT, pivot, -1, false, frame) == 1.0, "target at pivot does not define a scale snap")
	_check(TransformMath.snap_scale_factor(pivot, pivot + Vector3.RIGHT, pivot + Vector3.LEFT * 2, -1, false, frame) == 2.0, "Blender snap ratio stays positive")
	_check(TransformMath.snap_scale_factor(pivot, pivot + Vector3.RIGHT, pivot + Vector3.UP, -1, false, frame) == 1.0, "perpendicular reference remains finite")


func _test_projection() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 0, 10)
	camera.current = true
	for projection in [Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_ORTHOGONAL]:
		camera.projection = projection
		camera.size = 12.0
		var pivot := Vector3.ZERO
		var from := camera.unproject_position(pivot)
		var to := camera.unproject_position(Vector3(2, 3, 0))
		_vector(TransformMath.mouse_translation(camera, from, to, pivot, -1, false, Basis.IDENTITY), Vector3(2, 3, 0), "free mouse translation projection %d" % projection)
		_vector(TransformMath.mouse_translation(camera, from, camera.unproject_position(Vector3(2, 0, 0)), pivot, 0, false, Basis.IDENTITY), Vector3(2, 0, 0), "axis mouse projection %d" % projection)
		_vector(TransformMath.mouse_translation(camera, from, to, pivot, 2, true, Basis.IDENTITY), Vector3(2, 3, 0), "plane mouse projection %d" % projection)
		_check(TransformMath.ray_axis_parameter(camera, from, pivot, Vector3.BACK) == null, "end-on axis safe %d" % projection)
		_check(TransformMath.ray_plane_point(camera, from, pivot, Vector3.RIGHT) == null, "parallel plane safe %d" % projection)
	viewport.free()
	print("Transform math: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
