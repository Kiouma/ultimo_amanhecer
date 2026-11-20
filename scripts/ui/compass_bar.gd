class_name CompassBar
extends Control
## Bússola no topo da tela: gira com o personagem (N, NE, L, SE, S, SO, O, NO),
## mostra as marcações do mapa e os outros jogadores, com a distância.
## O norte do mundo é -Z (o topo do mapa).

const WIDTH := 640.0
const HEIGHT := 40.0
## Quantos graus cabem na barra.
const SPAN := 180.0
const LABELS := {0: "N", 45: "NE", 90: "L", 135: "SE", 180: "S", 225: "SO", 270: "O", 315: "NO"}

var player: Player


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 6)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	# Some com telas abertas (inventário, mapa...): as abas ficam no mesmo lugar.
	visible = MouseMode.playing()
	queue_redraw()


## Direção (graus, 0 = norte, 90 = leste) de um ponto visto do jogador.
static func bearing(from: Vector3, to: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(to.x - from.x, -(to.z - from.z))), 360.0)


func _heading() -> float:
	var forward := -player.global_basis.z
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


## Posição x na barra de uma direção (ou -1 se fora da vista).
func _x_of(deg: float, heading: float) -> float:
	var diff := wrapf(deg - heading, -180.0, 180.0)
	if absf(diff) > SPAN * 0.5:
		return -1.0
	return WIDTH * 0.5 + diff / SPAN * WIDTH


func _draw() -> void:
	if player == null or not is_instance_valid(player):
		return
	var font := get_theme_default_font()
	draw_rect(Rect2(0, 0, WIDTH, 22), Color(0, 0, 0, 0.45))
	var heading := _heading()
	for deg in range(0, 360, 15):
		var x := _x_of(deg, heading)
		if x < 0.0:
			continue
		if LABELS.has(deg):
			var text: String = LABELS[deg]
			var color := Color(1.0, 0.45, 0.35) if text == "N" else Color.WHITE
			var size := 16 if text.length() == 1 else 12
			draw_string(font, Vector2(x - 6.0 * text.length(), 17), tr(text), HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		else:
			draw_line(Vector2(x, 4), Vector2(x, 12), Color(1, 1, 1, 0.5), 1.0)
	draw_line(Vector2(WIDTH * 0.5, 0), Vector2(WIDTH * 0.5, 22), Color(1.0, 0.85, 0.3), 2.0)
	var me := player.global_position
	# Marcações do mapa.
	var exploration := player.get_node_or_null(^"Exploration") as Exploration
	if exploration:
		for m in exploration.markers:
			var target := Vector3(m.x, me.y, m.y)
			var x := _x_of(bearing(me, target), heading)
			if x < 0.0:
				continue
			draw_colored_polygon(PackedVector2Array([Vector2(x, 24), Vector2(x - 5, 30), Vector2(x, 36), Vector2(x + 5, 30)]), Color(1.0, 0.3, 0.25))
			draw_string(font, Vector2(x + 7, 35), "%d m" % roundi(me.distance_to(target)), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1.0, 0.75, 0.7))
	# Outros jogadores.
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if p == player:
			continue
		var x := _x_of(bearing(me, p.global_position), heading)
		if x < 0.0:
			continue
		draw_circle(Vector2(x, 30), 4.0, Color(0.4, 0.75, 1.0))
		draw_string(font, Vector2(x + 7, 35), "%s %d m" % [p.display_name(), roundi(me.distance_to(p.global_position))],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.75, 0.88, 1.0))
