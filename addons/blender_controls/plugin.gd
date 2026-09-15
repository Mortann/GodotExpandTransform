@tool
extends EditorPlugin
## An editor-only modal transform session. Uses public editor APIs and never
## modifies the user's global shortcut configuration.

const Math3D = preload("transform_math.gd")
const SnapPicker = preload("snap_picker.gd")
enum Mode { NONE, MOVE, ROTATE, SCALE }
const MODE_NAMES := ["", "Déplacer", "Tourner", "Échelle"]
const AXIS_NAMES := ["X", "Y", "Z"]
const AXIS_COLORS := [Color("f37878"), Color("86cf90"), Color("80afff")]

var _mode: int = Mode.NONE
var _enabled := true
var _show_panel := true
var _default_local := false
var _local := false
var _axis := -1
var _plane := false
var _axis_cycle := 0
var _nodes: Array[Node3D] = []
var _selection_snapshot := PackedInt64Array()
var _original_local: Array[Transform3D] = []
var _original_world: Array[Transform3D] = []
var _parents: Array[Node] = []
var _parent_world: Array[Transform3D] = []
var _scene: Node
var _camera: Camera3D
var _surface: Control
var _pivot := Vector3.ZERO
var _active_basis := Basis.IDENTITY
var _mouse := Vector2.ZERO
var _anchor := Vector2.ZERO
var _effective_mouse := Vector2.ZERO
var _last_raw_mouse := Vector2.ZERO
var _shift := false
var _ctrl := false
var _number := ""
var _number_valid := true
var _value_text := ""
var _error := ""
var _pick_base := false
var _building_snap := false
var _snap_build_revision := 0
var _has_base := false
var _base := Vector3.ZERO
var _display_base := Vector3.ZERO
var _hover: Dictionary = {}
var _target: Dictionary = {}
var _picker = SnapPicker.new()
var _source_picker = SnapPicker.new()
var _last_operation := Transform3D.IDENTITY
var _toolbar: HBoxContainer
var _toggle: CheckButton
var _orientation: OptionButton
var _panel_toggle: Button
var _help: AcceptDialog
var _ignore_selection := false
var _release_to_swallow := 0


func _enter_tree() -> void:
	add_to_group("blender_controls_plugin")
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	set_process_input(true)
	_show_panel = bool(EditorInterface.get_editor_settings().get_project_metadata("blender_controls", "show_panel", true))
	_build_toolbar()
	EditorInterface.get_selection().selection_changed.connect(_selection_changed)
	scene_changed.connect(_scene_changed)
	main_screen_changed.connect(_screen_changed)
	set_process(true)


func _exit_tree() -> void:
	_cancel()
	if EditorInterface.get_selection().selection_changed.is_connected(_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_selection_changed)
	if is_instance_valid(_toolbar):
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
		_toolbar.queue_free()
	if is_instance_valid(_help):
		_help.queue_free()


func _handles(object: Object) -> bool:
	return object is Node3D


func _get_plugin_name() -> String:
	return "Blender Controls 3D"


func _build_toolbar() -> void:
	_toolbar = HBoxContainer.new()
	_toggle = CheckButton.new()
	_toggle.text = "Blender G/R/S"
	_toggle.button_pressed = _enabled
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.tooltip_text = "Transformations au clavier. B pendant G/R/S : choisir la base d’accrochage."
	_toggle.toggled.connect(func(value: bool):
		_cancel()
		_enabled = value
	)
	_toolbar.add_child(_toggle)
	_orientation = OptionButton.new()
	_orientation.add_item("Global")
	_orientation.add_item("Local")
	_orientation.focus_mode = Control.FOCUS_NONE
	_orientation.tooltip_text = "Orientation initiale. Répéter un axe change de repère puis retire la contrainte."
	_orientation.item_selected.connect(func(index: int):
		_cancel()
		_default_local = index == 1
	)
	_toolbar.add_child(_orientation)
	_panel_toggle = Button.new()
	_panel_toggle.text = "Panneau"
	_panel_toggle.toggle_mode = true
	_panel_toggle.button_pressed = _show_panel
	_panel_toggle.focus_mode = Control.FOCUS_NONE
	_panel_toggle.tooltip_text = "Afficher ou masquer le panneau d’aide. Les surbrillances restent visibles."
	_panel_toggle.toggled.connect(_set_panel_visible)
	_toolbar.add_child(_panel_toggle)
	var help_button := Button.new()
	help_button.text = "?"
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.tooltip_text = "Raccourcis et accrochage"
	help_button.pressed.connect(func():
		_cancel()
		_help.popup_centered(Vector2i(650, 420))
	)
	_toolbar.add_child(help_button)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _toolbar)
	_help = AcceptDialog.new()
	_help.title = "Blender Controls 3D"
	_help.dialog_text = ("Dans la vue 3D, sélectionne un ou plusieurs objets.\n\n"
		+ "G : déplacer • R : tourner • S : échelle\n"
		+ "X/Y/Z : axe • Maj+axe : plan (G/S)\n"
		+ "Même axe : repère initial → autre repère → libre\n"
		+ "Nombre : distance / degrés / facteur ; virgule, point, signe et fractions\n"
		+ "Entrée / Espace / clic gauche : valider • Échap / clic droit : annuler\n"
		+ "Maj : précision • Ctrl : pas de 1 m / 5° / 0,1\n\n"
		+ "B pendant G/R/S : retour à l’état initial pour choisir une base.\n"
		+ "Survole un sommet, une arête ou une face, puis clique.\n"
		+ "Vise ensuite la cible sur un autre objet et clique pour valider.\n"
		+ "Ctrl suspend cet accrochage. B permet de choisir une nouvelle base.\n\n"
		+ "Pivot : moyenne des origines. Axes Godot : Y est vertical.\n"
		+ "Accrochage sur maillages statiques et formes CSG, sans collision.\n"
		+ "Sommet : point lumineux • Arête : ligne • Face : surface teintée.\n"
		+ "Le bouton Panneau masque l’aide sans masquer la surbrillance.\n"
		+ "Le B natif de Godot reste disponible hors transformation.")
	EditorInterface.get_base_control().add_child(_help)


func _set_panel_visible(value: bool) -> void:
	_show_panel = value
	EditorInterface.get_editor_settings().set_project_metadata("blender_controls", "show_panel", value)
	update_overlays()


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not _enabled:
		return AFTER_GUI_INPUT_PASS
	if _mode != Mode.NONE:
		# Normally handled earlier by _input. This path also supports events
		# supplied directly by a viewport and editor integration tests.
		if camera != _camera:
			return AFTER_GUI_INPUT_STOP
		if event is InputEventKey:
			_handle_key(event)
		elif event is InputEventMouseMotion:
			_motion(_to_camera(event.position), event.shift_pressed, event.ctrl_pressed)
		elif event is InputEventMouseButton:
			_motion(_to_camera(event.position), event.shift_pressed, event.ctrl_pressed)
			_button(event)
		return AFTER_GUI_INPUT_STOP
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
			return AFTER_GUI_INPUT_PASS
		# Never take S/G/R from fly navigation or a native mouse drag.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			return AFTER_GUI_INPUT_PASS
		var mode := _mode_for_key(event.keycode)
		if mode != Mode.NONE:
			var focus := get_viewport().gui_get_focus_owner()
			if focus is LineEdit or focus is TextEdit:
				return AFTER_GUI_INPUT_PASS
			_surface = focus
			_camera = camera
			var mouse := camera.get_viewport().get_mouse_position()
			if is_instance_valid(_surface):
				mouse = _to_camera(_surface.get_local_mouse_position())
			if _begin(mode, camera, mouse):
				return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _input(event: InputEvent) -> void:
	if _release_to_swallow != 0 and event is InputEventMouseButton and not event.pressed and event.button_index == _release_to_swallow:
		_release_to_swallow = 0
		get_viewport().set_input_as_handled()
		return
	if _mode == Mode.NONE:
		return
	# Godot 4.7 processes native B before forwarding viewport input to plugins.
	# Input-stage interception is necessary and avoids changing editor shortcuts.
	if event is InputEventKey:
		if event.pressed and (event.ctrl_pressed or event.meta_pressed) and event.keycode == KEY_S:
			_cancel()
			return
		_handle_key(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouse and is_instance_valid(_surface):
		# The visibility option can be toggled during a transform without
		# committing/cancelling it or forwarding the click as a scene click.
		if is_instance_valid(_panel_toggle) and _panel_toggle.get_global_rect().has_point(event.position):
			return
		var local_pos: Vector2 = _surface.get_global_transform_with_canvas().affine_inverse() * event.position
		if event is InputEventMouseMotion:
			_motion(_to_camera(local_pos), event.shift_pressed, event.ctrl_pressed)
		elif event is InputEventMouseButton:
			# A click outside the viewport cancels before the editor handles it.
			if event.pressed and not Rect2(Vector2.ZERO, _surface.size).has_point(local_pos):
				_cancel()
				return
			_motion(_to_camera(local_pos), event.shift_pressed, event.ctrl_pressed)
			_button(event)
		get_viewport().set_input_as_handled()


func _mode_for_key(key: int) -> int:
	match key:
		KEY_G: return Mode.MOVE
		KEY_R: return Mode.ROTATE
		KEY_S: return Mode.SCALE
	return Mode.NONE


func _begin(mode: int, camera: Camera3D, mouse: Vector2) -> bool:
	if _mode != Mode.NONE:
		return false
	_scene = EditorInterface.get_edited_scene_root()
	if not is_instance_valid(_scene):
		return false
	_nodes.clear()
	_original_local.clear()
	_original_world.clear()
	_parents.clear()
	_parent_world.clear()
	var selection := EditorInterface.get_selection()
	_selection_snapshot = _selection_ids()
	for selected in selection.get_top_selected_nodes():
		if not selected is Node3D or not _editable(selected):
			continue
		var node := selected as Node3D
		var parent := node.get_parent_node_3d()
		if parent != null and not node.is_set_as_top_level() and absf(parent.global_basis.determinant()) < 0.0000001:
			continue
		_nodes.append(node)
		_original_local.append(node.transform)
		_original_world.append(node.global_transform)
		_parents.append(node.get_parent())
		_parent_world.append(parent.global_transform if parent != null else Transform3D.IDENTITY)
	if _nodes.is_empty():
		return false
	_camera = camera
	_mode = mode
	_pivot = Vector3.ZERO
	for transform in _original_world:
		_pivot += transform.origin
	_pivot /= _nodes.size()
	_active_basis = _nodes.back().global_basis
	# The most recently added selected node gives the local orientation,
	# even when its parent is also selected and is the transformed root.
	for selected in selection.get_selected_nodes():
		if selected is Node3D and _editable(selected):
			_active_basis = selected.global_basis
	_local = _default_local
	_axis = -1
	_axis_cycle = 0
	_plane = false
	_mouse = mouse
	_anchor = mouse
	_effective_mouse = mouse
	_last_raw_mouse = mouse
	_number = ""
	_number_valid = true
	_error = ""
	_pick_base = false
	_has_base = false
	_base = _pivot
	_display_base = _base
	_hover = {}
	_target = {}
	_last_operation = Transform3D.IDENTITY
	_shift = false
	_ctrl = false
	_update_preview()
	update_overlays()
	return true


func _editable(node: Node3D) -> bool:
	if node != _scene and not _scene.is_ancestor_of(node):
		return false
	if bool(node.get_meta("_edit_lock_", false)) or not node.is_visible_in_tree():
		return false
	return node == _scene or node.owner == _scene or (node.owner != null and _scene.is_editable_instance(node.owner))


func _handle_key(event: InputEventKey) -> void:
	_shift = event.shift_pressed
	_ctrl = event.ctrl_pressed
	if not event.pressed:
		if event.keycode == KEY_CTRL or event.keycode == KEY_SHIFT:
			_update_preview()
		return
	if event.keycode == KEY_ESCAPE:
		_cancel()
		return
	if event.echo and event.keycode != KEY_BACKSPACE:
		return
	if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
		if _pick_base:
			_accept_base()
		else:
			_commit()
		return
	if event.keycode == KEY_B and not event.alt_pressed and not event.meta_pressed:
		_start_base_pick()
		return
	if _pick_base:
		return
	if event.keycode in [KEY_X, KEY_Y, KEY_Z] and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		var axis := [KEY_X, KEY_Y, KEY_Z].find(event.keycode)
		_set_constraint(axis, event.shift_pressed and _mode != Mode.ROTATE)
		return
	if event.keycode == KEY_CTRL or event.keycode == KEY_SHIFT:
		_update_preview()
		return
	if not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		if _edit_number(event):
			_update_preview()
			return
		var next_mode := _mode_for_key(event.keycode)
		if next_mode != Mode.NONE and next_mode != _mode:
			_restore()
			_mode = next_mode
			_number = ""
			_number_valid = true
			_anchor = _mouse
			_effective_mouse = _mouse
			_last_raw_mouse = _mouse
			if _mode == Mode.ROTATE:
				_plane = false
			_update_preview()


func _edit_number(event: InputEventKey) -> bool:
	if event.keycode == KEY_BACKSPACE:
		_number = _number.left(-1)
		return true
	var character := String.chr(event.unicode) if event.unicode > 0 else ""
	if character not in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", ",", "-", "/"]:
		if event.keycode >= KEY_KP_0 and event.keycode <= KEY_KP_9:
			character = str(event.keycode - KEY_KP_0)
		elif event.keycode >= KEY_0 and event.keycode <= KEY_9:
			character = str(event.keycode - KEY_0)
		elif event.keycode in [KEY_PERIOD, KEY_COMMA, KEY_KP_PERIOD]:
			character = "."
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			character = "-"
		elif event.keycode in [KEY_SLASH, KEY_KP_DIVIDE]:
			character = "/"
		else:
			return false
	if _number.length() >= 32 and character != "-":
		return true
	if character == "-":
		_number = _number.substr(1) if _number.begins_with("-") else "-" + _number
	elif character == "/":
		if not _number.contains("/"):
			_number = (_number if not _number.is_empty() else "1") + "/"
	elif character in [".", ","]:
		if not _number.get_slice("/", _number.get_slice_count("/") - 1).contains("."):
			_number += "."
	else:
		_number += character
	return true


func _numeric_value() -> Variant:
	if _number.is_empty():
		return null
	var parts := _number.split("/")
	if not parts[0].is_valid_float():
		return null
	var value := float(parts[0])
	if parts.size() == 2:
		if not parts[1].is_valid_float() or is_zero_approx(float(parts[1])):
			return null
		value /= float(parts[1])
	if not is_finite(value) or absf(value) > 1000000000.0:
		return null
	return value


func _set_constraint(axis: int, plane: bool) -> void:
	if axis == _axis and plane == _plane:
		_axis_cycle += 1
	else:
		_axis_cycle = 1
	_axis = axis
	_plane = plane
	if _axis_cycle >= 3:
		_axis = -1
		_axis_cycle = 0
		_local = _default_local
	else:
		_local = _default_local if _axis_cycle == 1 else not _default_local
	_update_preview()


func _motion(position: Vector2, shift: bool, ctrl: bool) -> void:
	_mouse = position
	_shift = shift
	_ctrl = ctrl
	# Integrate only the new motion in precision mode to prevent a jump when
	# Shift is pressed or released partway through a transformation.
	_effective_mouse += (position - _last_raw_mouse) * (0.1 if shift else 1.0)
	_last_raw_mouse = position
	if _pick_base:
		if not _building_snap:
			_hover = _source_picker.pick(_camera, _mouse, _snap_radius())
		update_overlays()
	else:
		_update_preview()


func _button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_release_to_swallow = MOUSE_BUTTON_RIGHT
		_cancel()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		_release_to_swallow = MOUSE_BUTTON_LEFT
		if _pick_base:
			_accept_base()
		else:
			_commit()


func _start_base_pick() -> void:
	_restore()
	_number = ""
	_number_valid = true
	_error = ""
	_pick_base = true
	_building_snap = true
	_snap_build_revision += 1
	var revision := _snap_build_revision
	_hover = {}
	_target = {}
	_last_operation = Transform3D.IDENTITY
	_display_base = _base
	update_overlays()
	# CSG boolean meshes are deferred. After restoring a transformed operand,
	# wait for evaluation instead of picking stale geometry from the preview.
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != _snap_build_revision or _mode == Mode.NONE or not _context_valid():
		return
	_source_picker.rebuild(_scene)
	_building_snap = false
	_hover = _source_picker.pick(_camera, _mouse, _snap_radius())
	if _source_picker.get_statistics().meshes == 0:
		_error = "Aucune géométrie détectée : utilise un maillage ou une forme CSG visible."
	update_overlays()


func _accept_base() -> void:
	if _building_snap:
		return
	if _hover.is_empty():
		_error = "Survole un sommet, une arête ou une face de maillage."
		update_overlays()
		return
	_base = _hover.position
	_display_base = _base
	_has_base = true
	_pick_base = false
	_error = ""
	_anchor = _camera.unproject_position(_base)
	_effective_mouse = _anchor
	_last_raw_mouse = _mouse
	_picker.rebuild(_scene, _nodes)
	_hover = {}
	# Do not snap to an unrelated object on the base-confirming click.
	update_overlays()


func _update_preview() -> void:
	if _mode == Mode.NONE or _pick_base or not is_instance_valid(_camera):
		return
	_error = ""
	var orientation: Basis = Math3D.constraint_basis(_local, _active_basis)
	var number: Variant = _numeric_value()
	_number_valid = _number.is_empty() or number != null
	if not _number_valid:
		_error = "Saisie incomplète ou invalide. Retour arrière pour corriger."
		update_overlays()
		return
	_target = {}
	if _has_base and not _ctrl and _number.is_empty():
		_target = _picker.pick(_camera, _mouse, _snap_radius())
	var operation := Transform3D.IDENTITY
	match _mode:
		Mode.MOVE:
			var delta: Vector3 = Math3D.mouse_translation(_camera, _anchor, _effective_mouse, _base if _has_base else _pivot, _axis, _plane, orientation)
			if not _target.is_empty():
				delta = Math3D.constrain_vector(_target.position - _base, _axis, _plane, orientation)
			elif number != null:
				# Blender's simple numeric input uses X when G is unconstrained.
				var components := Vector3.ZERO
				if _plane and _axis >= 0:
					components = Vector3.ONE * float(number)
					components[_axis] = 0.0
				else:
					components[_axis if _axis >= 0 else 0] = float(number)
				delta = orientation * components
			elif _ctrl and not _has_base:
				var step := 0.1 if _shift else 1.0
				var components := orientation.inverse() * delta
				components = components.snapped(Vector3.ONE * step)
				delta = Math3D.constrain_vector(orientation * components, _axis, _plane, orientation)
			operation.origin = delta
			_value_text = "Δ (%s, %s, %s) m" % [_format(delta.x), _format(delta.y), _format(delta.z)]
		Mode.ROTATE:
			var world_axis := orientation[_axis] if _axis >= 0 else _camera.global_basis.z.normalized()
			var angle := _mouse_angle(world_axis)
			if not _target.is_empty():
				angle = Math3D.snap_rotation_angle(_pivot, _base, _target.position, world_axis)
			elif number != null:
				angle = deg_to_rad(float(number))
			elif _ctrl and not _has_base:
				angle = snappedf(angle, deg_to_rad(1.0 if _shift else 5.0))
			operation = Math3D.rotated(Transform3D.IDENTITY, _pivot, world_axis, angle)
			_value_text = "%s°" % _format(rad_to_deg(angle))
		Mode.SCALE:
			var factor := _mouse_scale()
			if not _target.is_empty():
				factor = Math3D.snap_scale_factor(_pivot, _base, _target.position, _axis, _plane, orientation)
			elif number != null:
				factor = float(number)
			elif _ctrl and not _has_base:
				factor = snappedf(factor, 0.01 if _shift else 0.1)
			# An exactly singular Node3D breaks descendant inverse transforms.
			# Keep the previous preview and require correction; never clamp a
			# user-entered zero into an undocumented different value.
			if absf(factor) < 0.000001:
				_number_valid = false
				_error = "Une échelle nulle n’est pas prise en charge. Choisis un facteur non nul."
				update_overlays()
				return
			var factors := Vector3.ONE
			for i in range(3):
				if _axis < 0 or (_plane and i != _axis) or (not _plane and i == _axis):
					factors[i] = factor
			operation = Math3D.scaled(Transform3D.IDENTITY, _pivot, factors, orientation)
			_value_text = "× %s" % _format(factor)
	_last_operation = operation
	_display_base = operation * _base
	for i in range(_nodes.size()):
		if is_instance_valid(_nodes[i]):
			_nodes[i].global_transform = operation * _original_world[i]
	update_overlays()


func _mouse_angle(axis: Vector3) -> float:
	var first: Variant = Math3D.ray_plane_point(_camera, _anchor, _pivot, axis)
	var current: Variant = Math3D.ray_plane_point(_camera, _effective_mouse, _pivot, axis)
	if first != null and current != null:
		var a: Vector3 = first - _pivot
		var b: Vector3 = current - _pivot
		if a.length_squared() > 0.000001 and b.length_squared() > 0.000001:
			return a.signed_angle_to(b, axis)
	# Edge-on planes and a cursor on the pivot need a stable screen fallback.
	return (_effective_mouse.x - _anchor.x) * 0.01


func _mouse_scale() -> float:
	var center := _camera.unproject_position(_pivot)
	var start := _anchor - center
	var current := _effective_mouse - center
	if start.length() < 12.0:
		return 1.0 + (_effective_mouse.x - _anchor.x) * 0.01
	var side := -1.0 if start.dot(current) < 0.0 else 1.0
	return side * current.length() / start.length()


func _restore() -> void:
	for i in range(_nodes.size()):
		if is_instance_valid(_nodes[i]) and _nodes[i].get_parent() == _parents[i]:
			_nodes[i].transform = _original_local[i]


func _commit() -> void:
	if _mode == Mode.NONE or not _number_valid or _pick_base:
		return
	if not _context_valid():
		_cancel()
		return
	var changed := false
	for i in range(_nodes.size()):
		if not _nodes[i].transform.is_equal_approx(_original_local[i]):
			changed = true
			break
	if changed:
		var history := get_undo_redo()
		history.create_action("Blender : " + MODE_NAMES[_mode], UndoRedo.MERGE_DISABLE, _scene)
		for i in range(_nodes.size()):
			history.add_do_property(_nodes[i], &"transform", _nodes[i].transform)
			history.add_undo_property(_nodes[i], &"transform", _original_local[i])
		# Preview is already applied. A single history entry covers the group.
		history.commit_action(false)
	_finish()


func _cancel() -> void:
	if _mode == Mode.NONE:
		return
	_restore()
	_finish()


func _finish() -> void:
	_mode = Mode.NONE
	_pick_base = false
	_building_snap = false
	_snap_build_revision += 1
	_has_base = false
	_nodes.clear()
	_original_local.clear()
	_original_world.clear()
	_parents.clear()
	_parent_world.clear()
	_hover = {}
	_target = {}
	_picker = SnapPicker.new()
	_source_picker = SnapPicker.new()
	update_overlays()


func _context_valid() -> bool:
	if not is_instance_valid(_scene) or EditorInterface.get_edited_scene_root() != _scene or not is_instance_valid(_camera):
		return false
	for i in range(_nodes.size()):
		var node := _nodes[i]
		if not is_instance_valid(node) or not node.is_inside_tree() or node.get_parent() != _parents[i]:
			return false
		var parent := node.get_parent_node_3d()
		if parent != null and not node.is_set_as_top_level() and not parent.global_transform.is_equal_approx(_parent_world[i]):
			return false
	return true


func _process(_delta: float) -> void:
	if _mode != Mode.NONE and not _context_valid():
		_cancel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_cancel()


func _selection_changed() -> void:
	# EditorSelection may emit its deferred notification after G has started.
	# Ignore that notification if the selection itself is still unchanged.
	if not _ignore_selection and _selection_ids() != _selection_snapshot:
		_cancel()


func _selection_ids() -> PackedInt64Array:
	var ids := PackedInt64Array()
	for node in EditorInterface.get_selection().get_selected_nodes():
		ids.append(node.get_instance_id())
	ids.sort()
	return ids


func _scene_changed(_root: Node) -> void:
	_cancel()


func _screen_changed(screen: String) -> void:
	if screen != "3D":
		_cancel()


func _apply_changes() -> void:
	# Saving or running must not serialize an unconfirmed mouse preview.
	_cancel()


func _to_camera(point: Vector2) -> Vector2:
	if not is_instance_valid(_surface) or not is_instance_valid(_camera):
		return point
	var size := _camera.get_viewport().get_visible_rect().size
	return point * size / _surface.size.max(Vector2.ONE)


func _to_overlay(point: Vector2) -> Vector2:
	if not is_instance_valid(_surface):
		return point
	var size := _camera.get_viewport().get_visible_rect().size
	return point * _surface.size / size.max(Vector2.ONE)


func _project(point: Vector3) -> Vector2:
	return _to_overlay(_camera.unproject_position(point))


func _snap_radius() -> float:
	# Detection uses camera pixels; keep its apparent radius constant when the
	# editor UI is scaled or the viewport is rendered at reduced resolution.
	var radius := 14.0 * EditorInterface.get_editor_scale()
	return _to_camera(Vector2(radius, radius)).x


func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if _mode == Mode.NONE or not is_instance_valid(_camera) or overlay != _surface:
		return
	var ui_scale := EditorInterface.get_editor_scale()
	if not _camera.is_position_behind(_pivot):
		var center := _project(_pivot)
		overlay.draw_arc(center, 5.0 * ui_scale, 0, TAU, 32, Color("f8f9fc"), 1.5, true)
		if _axis >= 0:
			var basis: Basis = Math3D.constraint_basis(_local, _active_basis)
			for i in range(3):
				if (_plane and i == _axis) or (not _plane and i != _axis):
					continue
				var direction := _project(_pivot + basis[i]) - center
				if direction.length_squared() > 0.01:
					direction = direction.normalized() * overlay.size.length()
					overlay.draw_line(center - direction, center + direction, AXIS_COLORS[i] * Color(1, 1, 1, 0.6), 1.0, true)
	if _has_base and not _camera.is_position_behind(_display_base):
		_draw_marker(overlay, _display_base, Color("82e5dd"), false)
	var pick: Dictionary = _hover if _pick_base else _target
	if not pick.is_empty() and not _camera.is_position_behind(pick.position):
		_draw_feature(overlay, pick)
		_draw_marker(overlay, pick.position, Color("ffd37a"), true)
		if _has_base and not _camera.is_position_behind(_display_base):
			overlay.draw_dashed_line(_project(_display_base), _project(pick.position), Color("ffd37a"), 1.0, 5.0)

	if _show_panel:
		_draw_status_panel(overlay)
	if _pick_base or _has_base:
		_draw_snap_hint(overlay, pick)


func _draw_status_panel(overlay: Control) -> void:
	var ui_scale := EditorInterface.get_editor_scale()
	var margin := 16.0 * ui_scale
	var width := minf(overlay.size.x - margin * 2.0, 730.0 * ui_scale)
	var font := overlay.get_theme_default_font()
	var font_size := int(14.0 * ui_scale)
	var line_height := 24.0 * ui_scale
	# Leave room for Godot's Perspective/Orthogonal viewport menu.
	var rect := Rect2(margin, 52.0 * ui_scale, width, line_height * 4.0 + margin)
	overlay.draw_style_box(_panel_style(), rect)
	var constraint := "Libre"
	if _axis >= 0:
		constraint = ("Plan sans " if _plane else "Axe ") + AXIS_NAMES[_axis]
	constraint += " · " + ("Local" if _local else "Global")
	var title: String = MODE_NAMES[_mode] + "  |  " + constraint
	if _pick_base:
		title = "B · Choisir la base d’accrochage"
	var value := "Saisie : " + _number if not _number.is_empty() else _value_text
	if _pick_base:
		value = "Préparation de la géométrie…" if _building_snap else "Survole un sommet, une arête ou une face, puis clique."
	elif _has_base:
		value += "  |  Accrochage " + ("suspendu (Ctrl)" if _ctrl else "actif")
	var detail := _error
	if detail.is_empty():
		if _pick_base and not _hover.is_empty():
			detail = "Base : " + _kind_name(_hover.kind)
		elif not _target.is_empty():
			detail = "Cible : " + _kind_name(_target.kind) + " · " + String(_target.node.name)
		else:
			detail = "X/Y/Z : axe · Maj+axe : plan · B : base · Maj : précision"
	var lines := [title, value, detail, "Clic gauche / Entrée : valider · Clic droit / Échap : annuler"]
	for i in range(lines.size()):
		var color := Color("ffba8a") if i == 2 and not _error.is_empty() else Color("eef1f6")
		overlay.draw_string(font, rect.position + Vector2(12.0 * ui_scale, line_height * (i + 1)), lines[i], HORIZONTAL_ALIGNMENT_LEFT, width - 24.0 * ui_scale, font_size, color)


func _draw_marker(overlay: Control, position: Vector3, color: Color, square: bool) -> void:
	var center := _project(position)
	var radius := 7.0 * EditorInterface.get_editor_scale()
	if square:
		overlay.draw_rect(Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2), color, false, 2.0)
	else:
		overlay.draw_arc(center, radius, 0, TAU, 32, color, 2.0, true)
	overlay.draw_line(center - Vector2(radius + 3, 0), center + Vector2(radius + 3, 0), color, 1.0, true)
	overlay.draw_line(center - Vector2(0, radius + 3), center + Vector2(0, radius + 3), color, 1.0, true)


func _draw_feature(overlay: Control, hit: Dictionary) -> void:
	var points: PackedVector3Array = hit.get("feature_points", PackedVector3Array())
	var color := Color("ffd37a")
	var ui_scale := EditorInterface.get_editor_scale()
	match String(hit.kind).to_lower():
		"vertex":
			var point := _project(hit.position)
			overlay.draw_circle(point, 10.0 * ui_scale, Color(1, 0.67, 0.15, 0.22), true, -1, true)
			overlay.draw_circle(point, 6.5 * ui_scale, Color("11151d"), true, -1, true)
			overlay.draw_circle(point, 4.5 * ui_scale, color, true, -1, true)
		"edge":
			if points.size() == 2:
				_draw_feature_edge(overlay, points[0], points[1], color, 3.5 * ui_scale)
		"face":
			for index in range(0, points.size() - 2, 3):
				var polygon := _project_polygon(points.slice(index, index + 3))
				if polygon.size() >= 3:
					overlay.draw_colored_polygon(polygon, Color(1.0, 0.68, 0.18, 0.27))
			var boundary: PackedVector3Array = hit.get("boundary_points", PackedVector3Array())
			for index in range(0, boundary.size() - 1, 2):
				_draw_feature_edge(overlay, boundary[index], boundary[index + 1], color, 2.0 * ui_scale)


func _draw_feature_edge(overlay: Control, a: Vector3, b: Vector3, color: Color, width: float) -> void:
	var inverse := _camera.get_camera_transform().affine_inverse()
	var segment: PackedVector3Array = SnapPicker._clip_depth(a, b, -(inverse * a).z, -(inverse * b).z, _camera.near, _camera.far)
	if segment.size() != 2:
		return
	var first := _project(segment[0])
	var second := _project(segment[1])
	overlay.draw_line(first, second, Color(0.04, 0.05, 0.08, 0.9), width + 3.0, true)
	overlay.draw_line(first, second, color, width, true)


func _project_polygon(world_points: PackedVector3Array) -> PackedVector2Array:
	# Clip each triangle before projecting. Features straddling the camera's
	# near plane must never produce inverted screen-filling highlight polygons.
	var inverse := _camera.get_camera_transform().affine_inverse()
	var points := world_points
	for far_side in [false, true]:
		if points.is_empty():
			break
		var clipped := PackedVector3Array()
		var previous := points[-1]
		var previous_depth := -(inverse * previous).z
		var limit := _camera.far if far_side else _camera.near
		var previous_inside := previous_depth <= limit if far_side else previous_depth >= limit
		for point in points:
			var depth := -(inverse * point).z
			var inside := depth <= limit if far_side else depth >= limit
			if inside != previous_inside:
				clipped.append(previous.lerp(point, (limit - previous_depth) / (depth - previous_depth)))
			if inside:
				clipped.append(point)
			previous = point
			previous_depth = depth
			previous_inside = inside
		points = clipped
	var result := PackedVector2Array()
	for point in points:
		result.append(_project(point))
	return result


func _draw_snap_hint(overlay: Control, hit: Dictionary) -> void:
	var text := ""
	if _building_snap:
		text = "B · Préparation de la géométrie…"
	elif _pick_base:
		text = "1/2 · Choisir la base" if hit.is_empty() else "1/2 · " + _kind_name(hit.kind).capitalize() + " · Clic : choisir la base"
	elif _ctrl:
		text = "Accrochage suspendu · Relâche Ctrl"
	else:
		text = "2/2 · Viser la cible" if hit.is_empty() else "2/2 · " + _kind_name(hit.kind).capitalize() + " · Clic : valider"
	if not _error.is_empty() and not _show_panel:
		text = _error
	var scale := EditorInterface.get_editor_scale()
	var font := overlay.get_theme_default_font()
	var font_size := int(14.0 * scale)
	var width := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 20.0 * scale, overlay.size.x - 16.0)
	var size := Vector2(width, 32.0 * scale)
	var position := _to_overlay(_mouse) + Vector2(22.0, 25.0) * scale
	position.x = clampf(position.x, 8.0, maxf(8.0, overlay.size.x - size.x - 8.0))
	position.y = clampf(position.y, 8.0, maxf(8.0, overlay.size.y - size.y - 8.0))
	overlay.draw_style_box(_panel_style(), Rect2(position, size))
	overlay.draw_string(font, position + Vector2(10.0, 21.0) * scale, text, HORIZONTAL_ALIGNMENT_LEFT, width - 20.0 * scale, font_size, Color("ffd37a"))


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.068, 0.09, 0.94)
	style.set_corner_radius_all(7)
	style.border_color = Color("536179")
	style.set_border_width_all(1)
	return style


func _kind_name(kind: String) -> String:
	match kind.to_lower():
		"vertex": return "sommet"
		"edge": return "arête"
		"face": return "face"
	return kind


func _format(value: float) -> String:
	return String.num(value, 4)
