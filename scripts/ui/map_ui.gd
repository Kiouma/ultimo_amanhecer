class_name MapUI
extends Control
## Mapa do mundo (tecla M, GDD 10): biomas, lugares, construções e jogadores, só do que
## você já viu (Exploration). Roda do mouse: zoom; arrastar com o botão esquerdo: mover;
## botão direito: marca/desmarca um ponto (aparece na bússola e no minimapa).

const MAP_SIZE := Vector2(860, 560)
const ZOOM_STEP := 1.2

var player: Player

var _view: MapView
var _region: Label
var _dragging := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = MAP_SIZE + Vector2(0, 60)
	box.position = -box.custom_minimum_size * 0.5
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_region = Label.new()
	_region.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_region.add_theme_font_size_override("font_size", 18)
	top.add_child(_region)
	var center_button := Button.new()
	center_button.text = "Centralizar"
	center_button.focus_mode = Control.FOCUS_NONE
	center_button.pressed.connect(func() -> void:
		_view.follow = true
		_view.queue_redraw())
	top.add_child(center_button)
	_view = MapView.new()
	_view.custom_minimum_size = MAP_SIZE
	_view.zoom = 1.2
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_map_input)
	box.add_child(_view)
	UITabs.attach(self, "map", box)
	var hint := Label.new()
	hint.text = "Roda: zoom · arrastar: mover · botão direito: marcar / desmarcar · [M] fechar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(hint)


func bind(p: Player) -> void:
	player = p
	_view.player = p
	var exploration := p.get_node_or_null(^"Exploration") as Exploration
	if exploration:
		exploration.revealed.connect(func(chunks: Array) -> void:
			MapTiles.invalidate_fog(chunks)
			if visible:
				_view.queue_redraw())
		exploration.markers_changed.connect(_view.queue_redraw)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_view.zoom_at(event.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_view.zoom_at(event.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_RIGHT:
				var exploration := _view.exploration()
				if exploration:
					exploration.toggle_marker(_view.screen_to_world(event.position), 10.0 / _view.zoom)
			MOUSE_BUTTON_LEFT:
				_dragging = true
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_view.follow = false
		_view.center -= event.relative / _view.zoom
		_view.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("map"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if not visible:
		var world := get_tree().get_first_node_in_group("world")
		if world == null or not "CHUNK" in world:
			player.notify(tr("Sem mapa nesta área"))
			return
		_view.world = world
		_view.follow = true
	visible = not visible
	_dragging = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_view.queue_redraw()


func _process(_delta: float) -> void:
	if visible and _view.world:
		var pos := player.global_position
		_region.text = tr("Você está em: %s") % tr(_view.world.BIOME_NAMES.get(_view.world.biome_at(pos.x, pos.z), "?"))
		_view.queue_redraw()
