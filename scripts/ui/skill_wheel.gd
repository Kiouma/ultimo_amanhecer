class_name SkillWheel
extends Control
## Roda de habilidades (Q segurado): as habilidades aprendidas em volta do centro.
## Mexer o mouse aponta a escolha; soltar Q conjura a apontada. Sem mexer = cancela.
## Também desenha o ícone da última habilidade, ao lado esquerdo da hotbar (SpellIcon).

const RADIUS := 150.0
const DEAD_ZONE := 25.0

var player: Player
var choice := ""

var _spells: Array = []
var _aim := Vector2.ZERO


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func open(spell_ids: Array) -> void:
	_spells = spell_ids
	_aim = Vector2.ZERO
	choice = ""
	visible = true
	queue_redraw()


## Fecha e devolve a escolha ("" = nenhuma).
func close() -> String:
	visible = false
	return choice


func _input(event: InputEvent) -> void:
	# Aberta: o mouse escolhe na roda (e não gira a câmera).
	if visible and event is InputEventMouseMotion:
		_aim += event.relative
		if _aim.length() > RADIUS:
			_aim = _aim.normalized() * RADIUS
		choice = _pick()
		queue_redraw()
		get_viewport().set_input_as_handled()


func _pick() -> String:
	if _aim.length() < DEAD_ZONE or _spells.is_empty():
		return ""
	var step := TAU / _spells.size()
	var angle := fposmod(_aim.angle() + PI * 0.5 + step * 0.5, TAU)
	return str(_spells[int(angle / step) % _spells.size()])


func _slot_position(index: int, center: Vector2) -> Vector2:
	var step := TAU / _spells.size()
	var angle := -PI * 0.5 + index * step
	return center + Vector2(cos(angle), sin(angle)) * RADIUS


func _draw() -> void:
	if player == null:
		return
	var center := size * 0.5
	var font := get_theme_default_font()
	draw_circle(center, RADIUS + 60.0, Color(0, 0, 0, 0.45))
	for i in _spells.size():
		var id := str(_spells[i])
		var p := _slot_position(i, center)
		var selected := id == choice
		var color := SpellIcon.school_color(id)
		draw_circle(p, 38.0 if selected else 32.0, Color(color, 0.9 if selected else 0.55))
		draw_arc(p, 38.0 if selected else 32.0, 0, TAU, 32, Color.WHITE if selected else Color(1, 1, 1, 0.4), 2.0)
		var data := GameData.get_item(id)
		var level := int(player.progression.spells.get(id, 1))
		var text := str(data.get("name", id))
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(font, p + Vector2(-w * 0.5, 52), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
		draw_string(font, p + Vector2(-14, 6), "Nv %d" % level, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	if _aim.length() >= DEAD_ZONE:
		draw_line(center, center + _aim, Color(1, 1, 1, 0.7), 2.0)
	draw_string(font, center + Vector2(-60, 6), "solte Q" if choice != "" else "mova o mouse", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))
