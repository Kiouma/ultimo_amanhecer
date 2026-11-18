class_name MapView
extends Control
## Desenho do mapa do mundo infinito (usado pelo mapa do M e pelo minimapa): terreno por
## bloco (MapTiles), névoa do que não foi visto, lugares descobertos, construções,
## marcações e jogadores. center: ponto do mundo no meio; zoom: pixels por metro.

const MIN_ZOOM := 0.15
const MAX_ZOOM := 6.0

var player: Player
var world: Node
var center := Vector2.ZERO
var zoom := 1.0
## Segue o jogador (minimapa e mapa ao abrir); arrastar o mapa desliga.
var follow := true
var show_labels := true
var round_dots := 1.0

var _need_more := false


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func exploration() -> Exploration:
	return player.get_node_or_null(^"Exploration") as Exploration if player else null


func world_to_screen(p: Vector2) -> Vector2:
	return size * 0.5 + (p - center) * zoom


func screen_to_world(s: Vector2) -> Vector2:
	return center + (s - size * 0.5) / zoom


## Zoom mantendo o ponto do mundo sob o mouse no mesmo lugar.
func zoom_at(screen_pos: Vector2, factor: float) -> void:
	var before := screen_to_world(screen_pos)
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if not follow:
		center = before - (screen_pos - size * 0.5) / zoom
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or player == null:
		return
	if follow:
		center = Vector2(player.global_position.x, player.global_position.z)
	if _need_more:
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.05, 0.06))
	if world == null or not is_instance_valid(world) or player == null:
		return
	var chunk_size: float = world.CHUNK
	var top_left := screen_to_world(Vector2.ZERO)
	var bottom_right := screen_to_world(size)
	var c0 := Vector2i(floori(top_left.x / chunk_size), floori(top_left.y / chunk_size))
	var c1 := Vector2i(floori(bottom_right.x / chunk_size), floori(bottom_right.y / chunk_size))
	var seen := exploration()
	_need_more = false
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var c := Vector2i(cx, cz)
			var fog := MapTiles.fog(world, c, seen)
			if fog == null:
				continue  # nada visto neste bloco: fica escuro
			var rect := Rect2(world_to_screen(Vector2(c) * chunk_size), Vector2.ONE * chunk_size * zoom)
			var tex := MapTiles.terrain(world, c)  # feita numa thread; null = ainda não
			if tex == null:
				draw_rect(rect, Color(0.3, 0.32, 0.3))
				_need_more = true
			else:
				draw_texture_rect(tex, rect, false)
			draw_texture_rect(fog, rect, false)
	_draw_markers(seen)


func _draw_markers(seen: Exploration) -> void:
	var font := get_theme_default_font()
	var view := Rect2(Vector2.ZERO, size).grow(20.0)
	# Construções (peças) como pontinhos.
	if zoom > 0.4:
		for piece in Structures.pieces():
			var at := world_to_screen(Vector2(piece.global_position.x, piece.global_position.z))
			if view.has_point(at) and seen and seen.is_explored(piece.global_position.x, piece.global_position.z):
				draw_rect(Rect2(at - Vector2.ONE * 1.5, Vector2.ONE * 3), Color(0.9, 0.75, 0.5))
	# Lugares com nome (descobertos).
	var named := {}
	for poi: Dictionary in world.pois:
		if str(poi.type) == "square":
			continue
		var at := world_to_screen(poi.pos)
		if not view.has_point(at) or (seen and not seen.is_explored(poi.pos.x, poi.pos.y)):
			continue
		var color := Color(1.0, 0.85, 0.5)
		match str(poi.type):
			"military": color = Color(0.6, 0.9, 0.5)
			"ruins": color = Color(0.85, 0.6, 1.0)
		draw_circle(at, 4.0 * round_dots, color)
		var label := tr(str(poi.name))
		var key := label + str(poi.get("group", ""))
		if show_labels and not named.has(key):
			named[key] = true
			draw_string(font, at + Vector2(6, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
	# Marcações.
	if seen:
		for m in seen.markers:
			var at := world_to_screen(m)
			at = at.clamp(Vector2(6, 6), size - Vector2(6, 6))  # fora da vista: presa na borda
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -8), at + Vector2(6, 0), at + Vector2(0, 8), at + Vector2(-6, 0)]), Color(1.0, 0.3, 0.25))
	# Jogadores (o seu com seta de direção).
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		var at := world_to_screen(Vector2(p.global_position.x, p.global_position.z))
		if p == player:
			var forward := -p.global_basis.z
			var dir := Vector2(forward.x, forward.z).normalized()
			var side := Vector2(-dir.y, dir.x)
			draw_colored_polygon(PackedVector2Array([at + dir * 9, at - dir * 5 + side * 5, at - dir * 5 - side * 5]), Color(1.0, 0.3, 0.25))
		elif view.has_point(at):
			draw_circle(at, 4.0, Color(0.4, 0.7, 1.0))
			if show_labels:
				draw_string(font, at + Vector2(6, 4), p.display_name(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.85, 1.0))
