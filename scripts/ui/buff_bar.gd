class_name BuffBar
extends HBoxContainer
## Ícones dos efeitos ativos no jogador (HUD). Hoje: as auras recebidas (dele mesmo e
## de aliados por perto). Os buffs temporários e debuffs (etapa 5) entram aqui também.
## Passar o mouse (mouse livre) mostra o nome e de quem vem.

const ICON := Vector2(30, 30)

var player: Player
var _timer := 0.0
var _last_key := "-"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)


func _process(delta: float) -> void:
	_timer -= delta
	if player == null or _timer > 0.0:
		return
	_timer = 0.5
	var entries: Array = player.auras.received()
	var key := ""
	for e: Array in entries:
		key += "%s:%s;" % [e[0], (e[2] as Node).name if is_instance_valid(e[2]) else ""]
	if key == _last_key:
		return
	_last_key = key
	for c in get_children():
		c.queue_free()
	for e: Array in entries:
		add_child(_icon(str(e[0]), e[2] as Node))


func _icon(aura_id: String, source: Node) -> Control:
	var data := GameData.get_entry("auras", aura_id)
	var color := Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
	var panel := Panel.new()
	panel.custom_minimum_size = ICON
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.45)
	style.border_color = color.lightened(0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	var name_text := str(data.get("name", aura_id))
	var from := tr("você") if source == player else (str(source.call(&"display_name")) if is_instance_valid(source) and source.has_method(&"display_name") else tr("aliado"))
	panel.tooltip_text = tr("%s (aura de %s)") % [name_text, from]
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	var initials := ""
	for word: String in name_text.split(" ", false):
		if word.length() > 2:
			initials += word.left(1).to_upper()
	label.text = initials.left(2)
	panel.add_child(label)
	return panel
