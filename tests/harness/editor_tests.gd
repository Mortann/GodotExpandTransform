@tool
extends EditorPlugin

var checks := 0
var failures := 0
var plugin
var scene: Node3D
var camera: Camera3D
var cube: Node3D
var other: Node3D
var selection: EditorSelection


func _enter_tree() -> void:
	_run.call_deferred()


func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("EDITOR TEST: " + label)


func _key(code: int, shift := false, unicode := 0, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.unicode = unicode
	event.pressed = true
	event.shift_pressed = shift
	event.ctrl_pressed = ctrl
	return event


func _type(text: String) -> void:
	for character in text:
		plugin._handle_key(_key(character.to_upper().unicode_at(0), false, character.unicode_at(0)))


func _select(nodes: Array) -> void:
	selection.clear()
	for node in nodes:
		selection.add_node(node)
	selection.emit_signal("selection_changed")


func _start(mode: int, nodes: Array) -> void:
	_select(nodes)
	plugin._surface = null
	_check(plugin._begin(mode, camera, camera.unproject_position(cube.global_position) + Vector2(90, 0)), "begin mode %s" % mode)


func _run() -> void:
	await get_tree().process_frame
	EditorInterface.open_scene_from_path("res://demo.tscn")
	for i in range(20):
		await get_tree().process_frame
	plugin = get_tree().get_first_node_in_group("blender_controls_plugin")
	if plugin == null:
		push_error("Editor plugin failed to load")
		get_tree().quit(1)
		return
	scene = EditorInterface.get_edited_scene_root()
	cube = scene.get_node("Cube_Corail")
	other = scene.get_node("Bloc_Turquoise")
	selection = EditorInterface.get_selection()
	# Use the actual editor camera and render viewport for projection tests.
	camera = EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	_check(camera != null, "editor camera accessible")
	if camera == null:
		get_tree().quit(1)
		return
	camera.global_transform = scene.get_node("Camera3D").global_transform
	var original := cube.transform
	var other_original := other.transform
	_start(1, [cube])
	plugin._handle_key(_key(KEY_X))
	_type("2")
	_check(cube.position.is_equal_approx(original.origin + Vector3(2, 0, 0)), "G X 2 preview")
	plugin._handle_key(_key(KEY_ENTER))
	var history: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(cube))
	_check(history.has_undo(), "confirmed preview in editor history")
	history.undo()
	_check(cube.transform.is_equal_approx(original), "undo exact")
	history.redo()
	_check(cube.position.is_equal_approx(original.origin + Vector3(2, 0, 0)), "redo exact")
	history.undo()
	_start(1, [cube])
	plugin._handle_key(_key(KEY_Z, true))
	_type("1.5")
	_check(cube.position.is_equal_approx(original.origin + Vector3(1.5, 1.5, 0)), "numeric plane excludes Z")
	plugin._handle_key(_key(KEY_ESCAPE))
	_check(cube.transform.is_equal_approx(original), "escape exact")
	_start(1, [other])
	plugin._handle_key(_key(KEY_X))
	_check(plugin._axis == 0 and not plugin._local, "global X")
	plugin._handle_key(_key(KEY_X))
	_check(plugin._axis == 0 and plugin._local, "repeat X local")
	_type("2")
	_check(other.position.is_equal_approx(other_original.origin + other_original.basis.orthonormalized().x * 2), "local numeric displacement")
	plugin._handle_key(_key(KEY_X))
	_check(plugin._axis == -1, "third X unconstrained")
	plugin._cancel()
	_start(2, [cube])
	plugin._handle_key(_key(KEY_Y, true))
	_type("90")
	_check(cube.basis.is_equal_approx(Basis(Vector3.UP, PI / 2) * original.basis), "R shift Y 90")
	plugin._cancel()
	_start(3, [cube])
	_type("1/2")
	_check(cube.basis.is_equal_approx(original.basis.scaled(Vector3.ONE * 0.5)), "scale fraction")
	plugin._handle_key(_key(KEY_BACKSPACE))
	plugin._commit()
	_check(plugin._mode == 3 and not plugin._number_valid, "invalid fraction cannot commit")
	_type("0")
	_check(not plugin._number_valid, "division zero rejected")
	plugin._cancel()
	_start(3, [cube])
	_type("0")
	_check(not plugin._number_valid and cube.transform.is_equal_approx(original), "scale zero refused with original intact")
	plugin._cancel()
	_start(3, [cube])
	_type("-0,5")
	_check(cube.basis.is_equal_approx(Basis.from_scale(Vector3.ONE * -0.5)), "negative comma scale")
	plugin._cancel()
	_start(1, [cube, other])
	plugin._handle_key(_key(KEY_Y))
	_type("3")
	plugin._commit()
	_check(other.position.is_equal_approx(other_original.origin + Vector3.UP * 3), "group moved")
	history.undo()
	_check(cube.transform.is_equal_approx(original) and other.transform.is_equal_approx(other_original), "one group undo")
	var parent: Node3D = scene.get_node("Parent_Tourne_Echelle_Non_Uniforme")
	var child: Node3D = parent.get_child(0)
	var child_start := child.transform
	var child_world := child.global_transform
	_start(1, [parent, child])
	_check(plugin._nodes.size() == 1, "parent child filter")
	plugin._handle_key(_key(KEY_Z))
	_type("2")
	_check(child.global_position.is_equal_approx(child_world.origin + Vector3(0, 0, 2)), "descendant moved only once")
	plugin._cancel()
	_start(2, [child])
	plugin._handle_key(_key(KEY_X))
	_type("35")
	_check(child.global_basis.is_equal_approx(Basis(Vector3.RIGHT, deg_to_rad(35)) * child_world.basis), "rotation below nonuniform parent")
	plugin._cancel()
	_check(child.transform.is_equal_approx(child_start), "parented cancel exact local")
	_start(1, [cube])
	_type("2")
	_select([other])
	_check(plugin._mode == 0 and cube.transform.is_equal_approx(original), "selection change cancels")
	_start(1, [cube])
	_type("2")
	plugin._apply_changes()
	_check(plugin._mode == 0 and cube.transform.is_equal_approx(original), "save/run cancels preview")
	_start(1, [cube])
	_type("2")
	plugin._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(plugin._mode == 0 and cube.transform.is_equal_approx(original), "focus loss cancels")
	_start(1, [cube])
	_type("2")
	plugin._toggle.button_pressed = false
	_check(plugin._mode == 0 and cube.transform.is_equal_approx(original), "toolbar disable cancels")
	plugin._toggle.button_pressed = true
	_select([scene.get_node("Sol_Verrouille")])
	_check(not plugin._begin(1, camera, Vector2(200, 200)), "locked selection cannot start")
	_select([])
	_check(not plugin._begin(1, camera, Vector2(200, 200)), "empty selection cannot start")
	# Base selection against real mesh geometry; then all transform resolutions.
	_start(1, [cube])
	plugin._start_base_pick()
	_check(plugin._pick_base and cube.transform.is_equal_approx(original), "B restores reference pose")
	var source := cube.global_transform * Vector3(0.9, 0.9, 0.9)
	var target := other.global_transform * Vector3(1.2, 1.4, 0.9)
	plugin._mouse = camera.unproject_position(source)
	plugin._hover = plugin._source_picker.pick(camera, plugin._mouse)
	_check(not plugin._hover.is_empty(), "base picker finds mesh")
	plugin._accept_base()
	_check(plugin._has_base and not plugin._pick_base, "base click advances phase")
	var chosen: Vector3 = plugin._base
	plugin._motion(camera.unproject_position(target), false, false)
	_check(not plugin._target.is_empty(), "target picker finds other mesh")
	if not plugin._target.is_empty():
		_check(plugin._display_base.is_equal_approx(plugin._target.position), "free translation source exactly reaches target")
		_check(plugin._target.node != cube, "target excludes moving geometry")
	plugin._handle_key(_key(KEY_X))
	_check(is_equal_approx(cube.position.y, original.origin.y) and is_equal_approx(cube.position.z, original.origin.z), "snap obeys axis")
	plugin._cancel()
	_check(cube.transform.is_equal_approx(original), "B cancel restores initial pose")
	for mode in [2, 3]:
		_start(mode, [cube])
		plugin._start_base_pick()
		plugin._hover = {"position": source, "normal": Vector3.UP, "kind": "Vertex", "node": cube}
		plugin._accept_base()
		plugin._motion(camera.unproject_position(target), false, false)
		_check(cube.transform.is_finite(), "B rotate/scale remains finite mode %s" % mode)
		plugin._cancel()
	await _test_real_input()
	print("EDITOR_TESTS: %d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _find_surface(node: Node) -> Control:
	# Test harness only: find the actual editor surface by its signal connection,
	# never used by the addon itself.
	if node is Control:
		for connection in node.get_signal_connection_list("gui_input"):
			var callback: Callable = connection.callable
			if callback.get_method() == "_sinput":
				return node
	for child in node.get_children(true):
		var result := _find_surface(child)
		if result != null:
			return result
	return null


func _test_real_input() -> void:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var surface := _find_surface(viewport.get_parent().get_parent())
	if surface == null:
		for sibling in viewport.get_parent().get_parent().get_children(true):
			if sibling is Control and sibling.focus_mode == Control.FOCUS_ALL:
				surface = sibling
				break
	_check(surface != null, "native editor input surface found")
	if surface == null:
		return
	_select([cube])
	EditorInterface.set_main_screen_editor("3D")
	surface.grab_focus()
	await get_tree().process_frame
	var begin := _key(KEY_G)
	Input.parse_input_event(begin)
	await get_tree().process_frame
	_check(plugin._mode == 1, "real input G starts modal")
	Input.parse_input_event(_key(KEY_B))
	await get_tree().process_frame
	_check(plugin._pick_base, "real input B reaches addon before native snapping")
	var release_b := _key(KEY_B)
	release_b.pressed = false
	Input.parse_input_event(release_b)
	var before := cube.transform
	await _mouse_to(surface, camera.unproject_position(cube.global_position))
	_check(not plugin._hover.is_empty(), "real mouse finds source with correct viewport mapping")
	await _click(surface)
	_check(plugin._has_base and not plugin._pick_base, "real click chooses base")
	await _mouse_to(surface, camera.unproject_position(other.global_position))
	_check(not plugin._target.is_empty(), "real mouse finds target")
	if not plugin._target.is_empty():
		_check(plugin._display_base.is_equal_approx(plugin._target.position), "real input snaps source exactly")
	if DisplayServer.get_name() != "headless" and OS.has_environment("BC_CAPTURE_PATH"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("BC_CAPTURE_PATH"))
	await _click(surface)
	_check(plugin._mode == 0, "real click confirms snap")
	var undo: UndoRedo = plugin.get_undo_redo().get_history_undo_redo(plugin.get_undo_redo().get_object_history_id(cube))
	undo.undo()
	_check(cube.transform.is_equal_approx(before), "real snap undo restores exact transform")
	Input.parse_input_event(_key(KEY_G))
	await get_tree().process_frame
	Input.parse_input_event(_key(KEY_ESCAPE))
	await get_tree().process_frame
	_check(plugin._mode == 0, "real input Escape cancels")
	# R is Godot's default Scale Mode shortcut. The addon must receive it first.
	Input.parse_input_event(_key(KEY_R))
	await get_tree().process_frame
	_check(plugin._mode == 2, "real input R overrides native scale mode only in viewport")
	Input.parse_input_event(_key(KEY_ESCAPE))
	await get_tree().process_frame
	Input.parse_input_event(_key(KEY_S))
	await get_tree().process_frame
	_check(plugin._mode == 3, "real input S starts scale")
	plugin._cancel()
	var field := LineEdit.new()
	EditorInterface.get_base_control().add_child(field)
	field.grab_focus()
	await get_tree().process_frame
	Input.parse_input_event(_key(KEY_G, false, 103))
	await get_tree().process_frame
	_check(plugin._mode == 0 and field.text == "g", "text field keeps G input")
	field.queue_free()


func _mouse_to(surface: Control, position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = surface.get_global_transform_with_canvas() * plugin._to_overlay(position)
	event.global_position = event.position
	Input.parse_input_event(event)
	await get_tree().process_frame


func _click(surface: Control) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = surface.get_global_transform_with_canvas() * plugin._to_overlay(plugin._mouse)
		event.global_position = event.position
		Input.parse_input_event(event)
		await get_tree().process_frame
