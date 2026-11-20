class_name BuffBar
extends HBoxContainer
## Ícones dos efeitos ativos no jogador (HUD): buffs e debuffs temporários (StatusEffects,
## com os segundos restantes e os acúmulos) e as auras recebidas. Debuffs têm borda
## vermelha. Passar o mouse (mouse livre) mostra o nome, o efeito e de quem vem.

const ICON := Vector2(30, 30)

var player: Player
var _timer := 0.0
var _last_key := "-"
var _time_labels := {}  # id do efeito → Label do tempo


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)


func _process(delta: float) -> void:
	_timer -= delta
	if player == null or _timer > 0.0:
		return
	_timer = 0.25
	var effects: Array = player.effects.list() if player.effects else []
	var auras: Array = player.auras.received()
	var key := ""
	for e: Array in effects:
		key += "%s:%d;" % [e[0], e[3]]
	for e: Array in auras:
		key += "%s:%s;" % [e[0], (e[2] as Node).name if is_instance_valid(e[2]) else ""]
	if key != _last_key:
		_last_key = key
		for c in get_children():
			c.queue_free()
		_time_labels.clear()
		for e: Array in effects:
			add_child(_effect_icon(str(e[0]), int(e[3])))
		for e: Array in auras:
			add_child(_aura_icon(str(e[0]), e[2] as Node))
	for e: Array in effects:
		var label: Label = _time_labels.get(e[0])
		if label:
			var left := float(e[1])
			label.text = ("%dm" % ceili(left / 60.0)) if left >= 60.0 else ("%d" % ceili(left))


func _base_icon(color: Color, text: String, border: Color) -> Panel:
	var panel := Panel.new()
	panel.custom_minimum_size = ICON
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = color.darkened(0.45)
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.text = text
	panel.add_child(label)
	return panel


func _initials(name_text: String) -> String:
	var initials := ""
	for word: String in name_text.split(" ", false):
		if word.length() > 2:
			initials += word.left(1).to_upper()
	return initials.left(2) if initials != "" else name_text.left(2)


func _effect_icon(effect_id: String, stacks: int) -> Control:
	var data := StatusEffects.data(effect_id)
	var color := Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
	var debuff := str(data.get("kind", "")) == "debuff"
	var name_text := str(data.get("name", effect_id))
	var panel := _base_icon(color, _initials(name_text), Color(0.95, 0.25, 0.25) if debuff else color.lightened(0.3))
	panel.tooltip_text = "%s\n%s" % [name_text, data.get("desc", "")]
	var time := Label.new()
	time.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	time.offset_top = 6
	time.offset_bottom = 20
	time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time.add_theme_font_size_override("font_size", 10)
	time.add_theme_color_override("font_outline_color", Color.BLACK)
	time.add_theme_constant_override("outline_size", 3)
	panel.add_child(time)
	_time_labels[effect_id] = time
	if stacks > 1:
		var count := Label.new()
		count.text = "x%d" % stacks
		count.position = Vector2(ICON.x - 14, -6)
		count.add_theme_font_size_override("font_size", 10)
		count.add_theme_color_override("font_outline_color", Color.BLACK)
		count.add_theme_constant_override("outline_size", 3)
		panel.add_child(count)
	return panel


func _aura_icon(aura_id: String, source: Node) -> Control:
	var data := GameData.get_entry("auras", aura_id)
	var color := Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
	var name_text := str(data.get("name", aura_id))
	var panel := _base_icon(color, _initials(name_text), color.lightened(0.2))
	var from := tr("você") if source == player else (str(source.call(&"display_name")) if is_instance_valid(source) and source.has_method(&"display_name") else tr("aliado"))
	panel.tooltip_text = tr("%s (aura de %s)") % [name_text, from]
	return panel
