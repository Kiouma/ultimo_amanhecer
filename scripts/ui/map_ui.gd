class_name MapUI
extends Control
## Mapa do mundo (tecla M, GDD 10): biomas, lugares (vilarejo, cabanas, posto militar,
## ruínas), construções e jogadores. Só existe no mundo aberto (não na arena).
## Névoa: só aparece o que você já viu (Exploration). Botão direito marca/desmarca
## um ponto (a marcação aparece na bússola).

const MAP_PIXELS := 560.0
const RESOLUTION := 160  # amostras por lado

var player: Player

var _world: Node
var _image_rect: TextureRect
var _overlay: Control
var _region: Label
var _fog_rect: TextureRect
var _fog_image: Image
var _fog_dirty := true


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
	box.custom_minimum_size = Vector2(MAP_PIXELS, MAP_PIXELS + 50)
	box.position = -box.custom_minimum_size * 0.5
	add_child(box)
	_region = Label.new()
	_region.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region.add_theme_font_size_override("font_size", 18)
	box.add_child(_region)
	_image_rect = TextureRect.new()
	_image_rect.custom_minimum_size = Vector2(MAP_PIXELS, MAP_PIXELS)
	_image_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_image_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	box.add_child(_image_rect)
	_image_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_image_rect.gui_input.connect(_on_map_input)
	_fog_rect = TextureRect.new()
	_fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_fog_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_rect.add_child(_fog_rect)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_image_rect.add_child(_overlay)
	_overlay.draw.connect(_draw_markers)
	UITabs.attach(self, "map")
	var hint := Label.new()
	hint.text = "Botão direito: marcar / desmarcar · [M] fechar"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(hint)


func bind(p: Player) -> void:
	player = p
	var exploration := _exploration()
	if exploration:
		exploration.revealed.connect(func() -> void: _fog_dirty = true)


func _exploration() -> Exploration:
	return player.get_node_or_null(^"Exploration") as Exploration if player else null


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT and _world:
		var scale: float = _world.SIZE / MAP_PIXELS
		var at: Vector2 = event.position * scale - Vector2.ONE * float(_world.HALF)
		_exploration().toggle_marker(at)
		_overlay.queue_redraw()
		if _fog_dirty:
			_update_fog()


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
		_world = get_tree().get_first_node_in_group("world")
		if _world == null:
			player.notify("Sem mapa nesta área")
			return
		if _image_rect.texture == null:
			_image_rect.texture = _render_biomes()
	visible = not visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_update_fog()


func _process(_delta: float) -> void:
	if visible and _world:
		var pos := player.global_position
		_region.text = "Você está em: %s" % _world.BIOME_NAMES.get(_world.biome_at(pos.x, pos.z), "?")
		_overlay.queue_redraw()


## Imagem dos biomas (uma vez por partida).
func _render_biomes() -> ImageTexture:
	var img := Image.create(RESOLUTION, RESOLUTION, false, Image.FORMAT_RGB8)
	var step: float = _world.SIZE / RESOLUTION
	for j in RESOLUTION:
		for i in RESOLUTION:
			var x: float = -_world.HALF + (i + 0.5) * step
			var z: float = -_world.HALF + (j + 0.5) * step
			var biome: String = _world.biome_at(x, z)
			var color: Color = _world.BIOME_COLORS.get(biome, Color.BLACK)
			if biome == "lake":
				color = Color(0.2, 0.36, 0.48)
			elif biome == "mountain":
				color = color.lightened(clampf(_world.ground_height(x, z) / 40.0, 0.0, 0.4))
			img.set_pixel(i, j, color.lightened(0.12))
	return ImageTexture.create_from_image(img)


## Névoa: preto onde ainda não foi visto (uma imagem pequena, esticada e suavizada).
func _update_fog() -> void:
	var exploration := _exploration()
	if exploration == null or exploration.size == 0:
		return
	_fog_dirty = false
	var n := exploration.size
	if _fog_image == null or _fog_image.get_width() != n:
		_fog_image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for j in n:
		for i in n:
			var seen := exploration.explored[j * n + i] == 1
			_fog_image.set_pixel(i, j, Color(0.04, 0.05, 0.06, 0.0 if seen else 0.96))
	if _fog_rect.texture == null:
		_fog_rect.texture = ImageTexture.create_from_image(_fog_image)
	else:
		(_fog_rect.texture as ImageTexture).update(_fog_image)


func _to_map(world_pos: Vector3) -> Vector2:
	var scale: float = MAP_PIXELS / _world.SIZE
	return Vector2(world_pos.x + _world.HALF, world_pos.z + _world.HALF) * scale


func _draw_markers() -> void:
	if _world == null:
		return
	var font := get_theme_default_font()
	# Construções (peças) como pontinhos.
	var seen := _exploration()
	for piece in Structures.pieces():
		if seen and not seen.is_explored(piece.global_position.x, piece.global_position.z):
			continue
		_overlay.draw_rect(Rect2(_to_map(piece.global_position) - Vector2.ONE * 1.5, Vector2.ONE * 3), Color(0.9, 0.75, 0.5))
	# Lugares com nome.
	var named := {}
	var exploration := _exploration()
	for poi: Dictionary in _world.pois:
		if exploration and not exploration.is_explored(poi.pos.x, poi.pos.y):
			continue  # lugar ainda não descoberto
		var p := _to_map(Vector3(poi.pos.x, 0, poi.pos.y))
		var color := Color(1.0, 0.85, 0.5)
		match str(poi.type):
			"military": color = Color(0.6, 0.9, 0.5)
			"ruins": color = Color(0.85, 0.6, 1.0)
		_overlay.draw_circle(p, 4.0, color)
		var label := str(poi.name)
		if named.has(label):
			continue  # vilarejo: um nome só
		named[label] = true
		_overlay.draw_string(font, p + Vector2(6, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	# Marcações.
	if exploration:
		for m in exploration.markers:
			var at := _to_map(Vector3(m.x, 0, m.y))
			_overlay.draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(6, 0), at + Vector2(0, 8), at + Vector2(-6, 0)]), Color(1.0, 0.3, 0.25))
	# Jogadores (o seu com seta de direção).
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		var at := _to_map(p.global_position)
		if p == player:
			var forward := -p.global_basis.z
			var dir := Vector2(forward.x, forward.z).normalized()
			var side := Vector2(-dir.y, dir.x)
			_overlay.draw_colored_polygon(PackedVector2Array([at + dir * 9, at - dir * 5 + side * 5, at - dir * 5 - side * 5]), Color(1.0, 0.3, 0.25))
		else:
			_overlay.draw_circle(at, 4.0, Color(0.4, 0.7, 1.0))
			_overlay.draw_string(font, at + Vector2(6, 4), p.display_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.85, 1.0))
