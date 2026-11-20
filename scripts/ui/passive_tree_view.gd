class_name PassiveTreeView
extends Control
## Árvore passiva desenhada (aba da tela Personagem, P). Clique aloca, botão direito
## devolve, arrastar move, roda dá zoom. A busca destaca nós pelo nome ou efeito.
## Os nós e ligações vêm de PassiveTree; o estado (alocado ou não) do Progression.

## Mensagem para a barra de status ("Sem pontos passivos"...).
signal message(text: String)

const KIND_RADIUS := {"small": 9.0, "notable": 17.0, "keystone": 24.0, "start": 22.0}
const GROUP_COLORS := {
	"warrior": Color(0.86, 0.36, 0.3), "archer": Color(0.45, 0.8, 0.42), "mage": Color(0.42, 0.58, 1.0),
	"brawler": Color(0.95, 0.68, 0.28), "monk": Color(0.72, 0.6, 0.95), "spellbow": Color(0.4, 0.82, 0.85),
	"hunter": Color(0.7, 0.75, 0.35), "barbarian": Color(0.9, 0.5, 0.45), "center": Color(0.82, 0.8, 0.72),
}
const GOLD := Color(1.0, 0.82, 0.4)
const MIN_ZOOM := 0.25
const MAX_ZOOM := 2.0
## Zoom a partir do qual aparecem os nomes dos notáveis.
const LABEL_ZOOM := 0.5

var progression: Progression
var zoom := 0.7
## Onde fica a origem da árvore, relativa ao centro do controle (em pixels).
var pan := Vector2.ZERO
var search := "":
	set(value):
		search = value.strip_edges().to_lower()
		queue_redraw()

var _hover := ""
var _dragging := false
var _drag_moved := 0.0
var _tip: PanelContainer
var _tip_label: RichTextLabel


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	_tip = PanelContainer.new()
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip.custom_minimum_size = Vector2(300, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.96)
	style.border_color = Color(0.55, 0.5, 0.38)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	_tip.add_theme_stylebox_override("panel", style)
	add_child(_tip)
	_tip_label = RichTextLabel.new()
	_tip_label.bbcode_enabled = true
	_tip_label.fit_content = true
	_tip_label.scroll_active = false
	_tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_label.custom_minimum_size = Vector2(300, 0)
	_tip.add_child(_tip_label)
	mouse_exited.connect(func() -> void:
		_dragging = false
		_set_hover(""))


func center_on_start() -> void:
	if progression:
		pan = -_pos(progression.start_node()) * zoom
	queue_redraw()


func _pos(id: String) -> Vector2:
	var p: Array = PassiveTree.node(id).get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))


func _to_screen(world: Vector2) -> Vector2:
	return size * 0.5 + pan + world * zoom


func _radius(kind: String) -> float:
	return maxf(float(KIND_RADIUS.get(kind, 9.0)) * zoom, 2.5)


func _matches(node: Dictionary) -> bool:
	if search.length() < 2:
		return false
	if str(node.get("name", "")).to_lower().contains(search):
		return true
	return ProgressionUI.bonus_text(node.get("effects", {})).to_lower().contains(search)


## Ligado a um alocado, mas ainda não alocado (dá para pegar com pontos).
func _reachable(id: String) -> bool:
	if progression.is_allocated(id) or str(PassiveTree.node(id).get("kind", "")) == "start":
		return false
	for other: String in PassiveTree.neighbors(id):
		if progression.is_allocated(other):
			return true
	return false


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.055, 0.07))
	if progression == null:
		return
	var nodes := PassiveTree.all()
	var view := Rect2(Vector2.ZERO, size).grow(40.0)
	var line_w := clampf(3.0 * zoom, 1.0, 4.0)
	# Ligações.
	for id: String in nodes:
		var a := _to_screen(_pos(id))
		var a_on := progression.is_allocated(id)
		for other: String in nodes[id].get("links", []):
			if not nodes.has(other):
				continue
			var b := _to_screen(_pos(other))
			if not view.has_point(a) and not view.has_point(b):
				continue
			var b_on := progression.is_allocated(other)
			var color := Color(0.22, 0.24, 0.28)
			var width := line_w * 0.6
			if a_on and b_on:
				color = GOLD
				width = line_w
			elif a_on or b_on:
				color = Color(0.5, 0.56, 0.66)
				width = line_w * 0.8
			draw_line(a, b, color, width, true)
	# Nós.
	var font := get_theme_default_font()
	for id: String in nodes:
		var node: Dictionary = nodes[id]
		var p := _to_screen(_pos(id))
		var kind := str(node.get("kind", "small"))
		var r := _radius(kind)
		if not view.has_point(p):
			continue
		var group_color: Color = GROUP_COLORS.get(str(node.get("group", "")), Color(0.7, 0.7, 0.7))
		var allocated := progression.is_allocated(id)
		var reachable := _reachable(id)
		var fill := Color(0.11, 0.115, 0.13)
		var outline := group_color.darkened(0.45)
		var outline_w := maxf(1.5 * zoom, 1.0)
		if allocated:
			fill = group_color.lerp(GOLD, 0.35)
			outline = GOLD
			outline_w = maxf(2.5 * zoom, 1.5)
		elif reachable:
			fill = group_color.darkened(0.6)
			outline = Color(0.85, 0.9, 1.0) if progression.skill_points > 0 else group_color
			outline_w = maxf(2.0 * zoom, 1.2)
		match kind:
			"keystone":
				_draw_polygon_node(p, r, 8, fill, outline, outline_w)
				draw_arc(p, r * 0.6, 0, TAU, 24, outline.darkened(0.2), outline_w * 0.7, true)
			"notable":
				draw_circle(p, r, fill)
				draw_arc(p, r, 0, TAU, 32, outline, outline_w * 1.4, true)
				draw_arc(p, r * 0.7, 0, TAU, 24, outline.darkened(0.25), outline_w * 0.6, true)
			"start":
				var own := id == progression.start_node()
				draw_circle(p, r, group_color.darkened(0.2) if own else Color(0.1, 0.1, 0.12))
				draw_arc(p, r, 0, TAU, 32, group_color, outline_w * 1.6, true)
				draw_arc(p, r * 1.3, 0, TAU, 32, group_color.darkened(0.3), outline_w, true)
			_:
				draw_circle(p, r, fill)
				draw_arc(p, r, 0, TAU, 20, outline, outline_w, true)
		if _matches(node):
			draw_arc(p, r + 6.0, 0, TAU, 28, Color(1.0, 0.95, 0.3), 2.5, true)
		if id == _hover:
			draw_arc(p, r + 2.5, 0, TAU, 28, Color.WHITE, 2.0, true)
		if kind != "small" and zoom >= LABEL_ZOOM:
			var text := str(node.get("name", ""))
			var font_size := 12 if kind == "notable" else 14
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
			var color := Color(0.95, 0.9, 0.75) if allocated else Color(0.7, 0.7, 0.66)
			draw_string_outline(font, p + Vector2(-w * 0.5, r + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, 0.85))
			draw_string(font, p + Vector2(-w * 0.5, r + 14.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_polygon_node(p: Vector2, r: float, sides: int, fill: Color, outline: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in sides:
		var a := TAU * (float(i) + 0.5) / sides
		points.append(p + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(points, fill)
	points.append(points[0])
	draw_polyline(points, outline, width * 1.4, true)


# --- Entrada -----------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if progression == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15)
				accept_event()
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if mb.pressed:
					_dragging = true
					_drag_moved = 0.0
				else:
					if _dragging and _drag_moved < 6.0 and _hover != "" and mb.button_index == MOUSE_BUTTON_LEFT:
						_click(_hover)
					_dragging = false
				accept_event()
			MOUSE_BUTTON_RIGHT:
				if mb.pressed and _hover != "":
					var reason := progression.refund_block_reason(_hover)
					if reason == "":
						progression.refund(_hover)
						message.emit(tr("Ponto devolvido: %s") % PassiveTree.node(_hover).get("name", ""))
					else:
						message.emit(reason)
					_update_tip()
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			pan += mm.relative
			_drag_moved += mm.relative.length()
			queue_redraw()
		_set_hover(_node_at(mm.position))
		if _tip.visible:
			_place_tip(mm.position)


func _click(id: String) -> void:
	var reason := progression.allocate_block_reason(id)
	if reason == "":
		progression.allocate(id)
		message.emit(tr("Alocado: %s") % PassiveTree.node(id).get("name", ""))
	else:
		message.emit(reason)
	_update_tip()


func _zoom_at(screen: Vector2, factor: float) -> void:
	var world := (screen - size * 0.5 - pan) / zoom
	zoom = clampf(zoom * factor, MIN_ZOOM, MAX_ZOOM)
	pan = screen - size * 0.5 - world * zoom
	queue_redraw()


func zoom_by(factor: float) -> void:
	_zoom_at(size * 0.5, factor)


func _node_at(screen: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id: String in PassiveTree.all():
		var node := PassiveTree.node(id)
		var d := _to_screen(_pos(id)).distance_to(screen)
		if d <= _radius(str(node.get("kind", "small"))) + 4.0 and d < best_d:
			best = id
			best_d = d
	return best


func _set_hover(id: String) -> void:
	if id == _hover:
		return
	_hover = id
	_update_tip()
	if id != "":
		_place_tip(get_local_mouse_position())
	queue_redraw()


# --- Dica ---------------------------------------------------------------------------------

const KIND_NAMES := {"small": "Nó pequeno", "notable": "Notável", "keystone": "Pedra angular", "start": "Início"}


func _update_tip() -> void:
	_tip.visible = _hover != "" and progression != null
	if not _tip.visible:
		return
	var node := PassiveTree.node(_hover)
	var kind := str(node.get("kind", "small"))
	var head_color := "#ffd27a" if kind != "small" else "#e8e4d8"
	var lines: PackedStringArray = []
	lines.append("[font_size=17][color=%s]%s[/color][/font_size]" % [head_color, node.get("name", "")])
	var kind_text := tr(str(KIND_NAMES.get(kind, kind)))
	if kind == "start":
		kind_text = tr("Início da classe %s") % GameData.get_entry("backgrounds", str(node.get("class", ""))).get("name", "")
	lines.append("[color=#9a968a]%s[/color]" % kind_text)
	for line: String in ProgressionUI.bonus_lines(node.get("effects", {})):
		lines.append("[color=#8fc8ff]%s[/color]" % line)
	if node.has("desc"):
		lines.append("[i]%s[/i]" % node.desc)
	var status := ""
	if kind == "start":
		status = tr("Seu ponto de partida") if _hover == progression.start_node() else tr("Início de outra classe: não dá para alocar")
	elif progression.is_allocated(_hover):
		var reason := progression.refund_block_reason(_hover)
		status = tr("Alocado · botão direito devolve o ponto") if reason == "" else tr("Alocado · %s") % reason
	else:
		var reason := progression.allocate_block_reason(_hover)
		status = tr("Clique para alocar (1 ponto)") if reason == "" else reason
	lines.append("[color=#c8c09a]%s[/color]" % status)
	_tip_label.text = "\n".join(lines)
	_tip.reset_size()


func _place_tip(mouse: Vector2) -> void:
	var tip_size := _tip.get_combined_minimum_size()
	var p := mouse + Vector2(18, 18)
	if p.x + tip_size.x > size.x:
		p.x = mouse.x - tip_size.x - 12.0
	if p.y + tip_size.y > size.y:
		p.y = maxf(size.y - tip_size.y - 4.0, 0.0)
	_tip.position = p.max(Vector2.ZERO)
