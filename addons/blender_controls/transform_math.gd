@tool
extends RefCounted
## Pure transform operations use global transforms, including their full basis.
## Angles are radians; scale values are factors (1 is unchanged).

const EPSILON_SQUARED := 1.0e-12
const PARALLEL_EPSILON := 1.0e-6


## Return a unit, orthogonal orientation without inheriting object scale/shear.
static func constraint_basis(local: bool, active_basis: Basis) -> Basis:
	if not local or not active_basis.is_finite():
		return Basis.IDENTITY
	if absf(active_basis.determinant()) > EPSILON_SQUARED:
		return active_basis.orthonormalized()
	# Collapsed objects still need a usable axis frame for recovering their scale.
	var x := active_basis.x.normalized()
	if x.length_squared() < EPSILON_SQUARED:
		x = Vector3.RIGHT
	var y := active_basis.y - x * active_basis.y.dot(x)
	if y.length_squared() < EPSILON_SQUARED:
		var fallback := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.BACK
		y = fallback - x * fallback.dot(x)
	y = y.normalized()
	return Basis(x, y, x.cross(y).normalized())


## axis -1 means unconstrained. plane=true excludes that axis (Shift+axis).
static func constrain_vector(delta: Vector3, axis: int, plane: bool, orientation: Basis) -> Vector3:
	if axis < 0 or axis > 2:
		return delta
	var direction: Vector3 = constraint_basis(true, orientation)[axis]
	var along := direction * delta.dot(direction)
	return delta - along if plane else along


static func translated(start: Transform3D, delta: Vector3) -> Transform3D:
	return Transform3D(start.basis, start.origin + delta)


## Left multiplication preserves nonuniform scale and shear already in start.
static func rotated(start: Transform3D, pivot: Vector3, axis_world: Vector3, angle: float) -> Transform3D:
	if axis_world.length_squared() < EPSILON_SQUARED or not axis_world.is_finite() or not is_finite(angle):
		return start
	var rotation := Basis(axis_world.normalized(), angle)
	return Transform3D(rotation * start.basis, pivot + rotation * (start.origin - pivot))


## Apply oriented scaling about one shared world pivot, retaining the full basis.
## Zero factors are mathematically supported; callers may reject collapsed scales.
static func scaled(start: Transform3D, pivot: Vector3, factors: Vector3, orientation: Basis) -> Transform3D:
	if not factors.is_finite():
		return start
	var frame := constraint_basis(true, orientation)
	var scaling := frame * Basis.from_scale(factors) * frame.transposed()
	return Transform3D(scaling * start.basis, pivot + scaling * (start.origin - pivot))


## Screen coordinates must be in the supplied Camera3D viewport's pixel space.
## Returns Vector3 or null for parallel rays, invalid normals, or hits behind camera.
static func ray_plane_point(camera: Camera3D, screen: Vector2, plane_point: Vector3, plane_normal: Vector3) -> Variant:
	if plane_normal.length_squared() < EPSILON_SQUARED or not plane_normal.is_finite():
		return null
	var normal := plane_normal.normalized()
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var denominator := direction.dot(normal)
	if absf(denominator) < PARALLEL_EPSILON:
		return null
	var distance := (plane_point - origin).dot(normal) / denominator
	if distance < 0.0 or not is_finite(distance):
		return null
	return origin + direction * distance


## Signed world distance along the axis closest to the camera ray, or null.
## Looking directly along an axis cannot determine its displacement from the mouse.
static func ray_axis_parameter(camera: Camera3D, screen: Vector2, axis_origin: Vector3, axis_world: Vector3) -> Variant:
	if axis_world.length_squared() < EPSILON_SQUARED or not axis_world.is_finite():
		return null
	var axis := axis_world.normalized()
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	var ray_dot_axis := ray.dot(axis)
	var denominator := 1.0 - ray_dot_axis * ray_dot_axis
	if denominator < PARALLEL_EPSILON:
		return null
	var offset := origin - axis_origin
	var ray_distance := (ray_dot_axis * axis.dot(offset) - ray.dot(offset)) / denominator
	if ray_distance < 0.0:
		return null
	var parameter := axis.dot(offset) + ray_distance * ray_dot_axis
	return parameter if is_finite(parameter) else null


## Translation from two viewport mouse positions, using a fixed initial pivot.
## Returns zero if the constraint is end-on or its intersection is undefined.
static func mouse_translation(camera: Camera3D, start_screen: Vector2, current_screen: Vector2, pivot: Vector3, axis: int, plane: bool, orientation: Basis) -> Vector3:
	var frame := constraint_basis(true, orientation)
	if axis >= 0 and axis <= 2 and not plane:
		var axis_world: Vector3 = frame[axis]
		var first: Variant = ray_axis_parameter(camera, start_screen, pivot, axis_world)
		var last: Variant = ray_axis_parameter(camera, current_screen, pivot, axis_world)
		if first == null or last == null:
			return Vector3.ZERO
		return axis_world * (float(last) - float(first))
	var normal := camera.global_basis.z.normalized()
	if axis >= 0 and axis <= 2 and plane:
		normal = frame[axis]
	var first: Variant = ray_plane_point(camera, start_screen, pivot, normal)
	var last: Variant = ray_plane_point(camera, current_screen, pivot, normal)
	if first == null or last == null:
		return Vector3.ZERO
	return constrain_vector(Vector3(last) - Vector3(first), axis, plane, frame)


## Signed angle taking source toward target around axis_world through pivot.
## Only components perpendicular to that axis affect the result.
static func snap_rotation_angle(pivot: Vector3, source: Vector3, target: Vector3, axis_world: Vector3) -> float:
	if axis_world.length_squared() < EPSILON_SQUARED or not axis_world.is_finite():
		return 0.0
	var normal := axis_world.normalized()
	var first := source - pivot
	var last := target - pivot
	first -= normal * first.dot(normal)
	last -= normal * last.dot(normal)
	if first.length_squared() < EPSILON_SQUARED or last.length_squared() < EPSILON_SQUARED or not first.is_finite() or not last.is_finite():
		return 0.0
	first = first.normalized()
	last = last.normalized()
	return atan2(normal.dot(first.cross(last)), clampf(first.dot(last), -1.0, 1.0))


## Blender's ResizeBetween projects the source vector onto the target direction,
## then takes the ratio of their lengths. This is intentionally NOT nearest-point
## scaling on the source ray. Degenerate/orthogonal references leave scale at 1.
## Reference: Blender 4.5 transform_mode_resize.cc, ResizeBetween.
static func snap_scale_factor(pivot: Vector3, source: Vector3, target: Vector3, axis: int, plane: bool, orientation: Basis) -> float:
	var first := constrain_vector(source - pivot, axis, plane, orientation)
	var last := constrain_vector(target - pivot, axis, plane, orientation)
	var denominator := absf(first.dot(last))
	if denominator < EPSILON_SQUARED or not first.is_finite() or not last.is_finite():
		return 1.0
	var factor := last.length_squared() / denominator
	return factor if is_finite(factor) else 1.0
