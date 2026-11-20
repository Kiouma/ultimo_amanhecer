class_name AuraUI
extends Control
## Tela de auras (tecla C). Um quadrado por aura: clique liga/desliga. Passar o mouse
## mostra embaixo o nível da aura como título, a descrição (efeito) e a barra da reserva
## (1% a 35% de mana ou de vida; o efeito cresce na mesma proporção).
## Também mantém no HUD a lista das auras que o jogador está recebendo.

const SQUARE := Vector2(74, 74)

var player: Player

var _grid: GridContainer
var _reserve_label: Label
var _receiving_label: Label
var _title: Label
var _desc: Label
var _effect: Label
var _percent_label: Label
var _slider: HSlider
var _footer: Label
var _detail: VBoxContainer
var _squares := {}  # id → Button
var _focus := ""
var _strip: Label  # HUD: auras recebidas
var _strip_timer := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	UITabs.attach(self, "auras")


func bind(p: Player) -> void:
	player = p
	player.auras.changed.connect(func() -> void:
		if visible:
			_refresh())
	player.progression.changed.connect(func() -> void:
		if visible:
			_refresh())
	_strip = Label.new()
	_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	_strip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_strip.position.y -= 96
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_theme_font_size_override("font_size", 13)
	_strip.add_theme_color_override("font_outline_color", Color.BLACK)
	_strip.add_theme_constant_override("outline_size", 4)
	get_parent().add_child.call_deferred(_strip)


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("auras"):
		# Abrir pela tecla fecha as outras telas (como as abas).
		if not visible and get_parent().has_method(&"open_panel"):
			get_parent().open_panel("auras")
		else:
			toggle()
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("pause") or event.is_action_pressed("inventory")):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible and not player.health.is_dead
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_footer.text = ""
		if _focus == "" and not GameData.get_all("auras").is_empty():
			_focus = GameData.get_all("auras").keys()[0]
		_refresh()


func _process(delta: float) -> void:
	_strip_timer -= delta
	if _strip == null or player == null or _strip_timer > 0.0:
		return
	_strip_timer = 0.5
	var names: PackedStringArray = []
	for entry: Array in player.auras.received():
		var aura_name := str(GameData.get_entry("auras", entry[0]).get("name", entry[0]))
		var source: Node = entry[2]
		if source != player and is_instance_valid(source):
			aura_name += " (%s)" % _player_name(source)
		names.append(aura_name)
	_strip.text = (tr("Auras: ") + ", ".join(names)) if not names.is_empty() else ""
	if visible:
		_receiving_label.text = tr("Recebendo agora: %s") % (", ".join(names) if not names.is_empty() else tr("nenhuma"))


func _player_name(p: Node) -> String:
	var n: Variant = p.get(&"display_name")
	return str(n) if n != null and str(n) != "" else tr("aliado")


# --- Atualização ----------------------------------------------------------------------------

func _refresh() -> void:
	var auras := player.auras
	_reserve_label.text = tr("Mana reservada: %d%%  ·  Vida reservada: %d%%  (máximo %d%% de cada)") % [
		roundi(auras.reserved_fraction("mana") * 100.0), roundi(auras.reserved_fraction("life") * 100.0), roundi(Auras.MAX_RESERVED * 100.0)]
	for id: String in _squares:
		_style_square(id)
	_refresh_detail()


func _style_square(id: String) -> void:
	var auras := player.auras
	var b: Button = _squares[id]
	var data := GameData.get_entry("auras", id)
	var color := Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE)
	var active := auras.is_active(id)
	var unlocked := auras.is_unlocked(id)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(6)
		style.bg_color = color.darkened(0.35) if active else Color(0.1, 0.1, 0.12)
		style.border_color = color.lightened(0.3) if active else (color.darkened(0.2) if unlocked else Color(0.3, 0.3, 0.32))
		style.set_border_width_all(4 if active else 2)
		if state == "hover" or (state == "focus" and id == _focus):
			style.border_color = Color.WHITE
		b.add_theme_stylebox_override(state, style)
	b.modulate = Color.WHITE if unlocked else Color(0.55, 0.55, 0.55)
	b.text = _initials(str(data.get("name", id))) + ("" if unlocked else "\n" + tr("Nv %d") % int(data.get("unlock_level", 1)))


func _initials(text: String) -> String:
	var out := ""
	for word: String in text.split(" ", false):
		if word.length() > 2:
			out += word.left(1).to_upper()
	return out.left(3)


func _refresh_detail() -> void:
	_detail.visible = _focus != ""
	if _focus == "":
		return
	var auras := player.auras
	var data := GameData.get_entry("auras", _focus)
	var pct := auras.get_percent(_focus)
	var resource := tr("mana") if str(data.get("resource", "mana")) == "mana" else tr("vida")
	var lvl := auras.level(_focus)
	_title.text = tr("%s  ·  Nível %d") % [data.get("name", _focus), lvl]
	_title.add_theme_color_override("font_color", Color.from_string(str(data.get("color", "#ffffff")), Color.WHITE).lightened(0.2))
	_desc.text = str(data.get("desc", ""))
	var effect := tr("Efeito agora: %s") % ProgressionUI.bonus_text(auras.effects_at(_focus, auras.strength(_focus)))
	effect += "\n" + tr("Raio %.0f m · nível %d: +%d%% de efeito") % [auras.radius(), lvl, roundi(Auras.LEVEL_BONUS * (lvl - 1) * 100.0)]
	if lvl < Auras.MAX_LEVEL:
		effect += " · " + tr("próximo nível: %d / %d s ligada") % [int(float(auras.xp.get(_focus, 0.0))), int(Auras.xp_to_next(lvl))]
	_effect.text = effect
	var cost := auras.reserve_cost(pct) * 100.0
	_percent_label.text = tr("%d%% de %s") % [pct, resource]
	if absf(cost - pct) > 0.5:
		_percent_label.text += "  " + tr("(reserva real %.0f%%)") % cost
	_slider.set_value_no_signal(pct)
	var state := tr("LIGADA") if auras.is_active(_focus) else tr("desligada")
	if not auras.is_unlocked(_focus):
		state = tr("disponível no nível %d") % int(data.get("unlock_level", 1))
	_footer.text = tr("Aura %s · clique no quadrado para ligar/desligar") % state


# --- Montagem -------------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 540)
	panel.position = -panel.custom_minimum_size * 0.5
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Auras"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	var intro := Label.new()
	intro.text = "Bônus em área para você e os aliados por perto, pagos com uma reserva de mana (ou de vida) enquanto ficam ligadas. Sobem de nível com o tempo ligadas."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 12)
	intro.modulate = Color(0.78, 0.78, 0.74)
	root.add_child(intro)
	_reserve_label = Label.new()
	_reserve_label.add_theme_font_size_override("font_size", 13)
	_reserve_label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	root.add_child(_reserve_label)

	_grid = GridContainer.new()
	_grid.columns = 7
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	root.add_child(_grid)
	for id: String in GameData.get_all("auras"):
		var b := Button.new()
		b.custom_minimum_size = SQUARE
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 15)
		b.mouse_entered.connect(func() -> void:
			_focus = id
			_refresh())
		b.pressed.connect(func() -> void:
			_focus = id
			var reason := player.auras.toggle(id)
			_refresh()
			if reason != "":
				_footer.text = reason)
		_grid.add_child(b)
		_squares[id] = b

	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_detail)
	var sep := HSeparator.new()
	_detail.add_child(sep)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_detail.add_child(_title)
	_desc = Label.new()
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 14)
	_detail.add_child(_desc)
	_effect = Label.new()
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect.add_theme_font_size_override("font_size", 13)
	_effect.add_theme_color_override("font_color", Color(0.56, 0.78, 1.0))
	_detail.add_child(_effect)
	_percent_label = Label.new()
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent_label.add_theme_font_size_override("font_size", 16)
	_detail.add_child(_percent_label)
	_slider = HSlider.new()
	_slider.min_value = Auras.MIN_PERCENT
	_slider.max_value = Auras.MAX_PERCENT
	_slider.step = 1
	_slider.tick_count = 8
	_slider.ticks_on_borders = true
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.custom_minimum_size = Vector2(0, 24)
	_slider.value_changed.connect(func(value: float) -> void:
		if _focus == "" or player == null:
			return
		var kept := player.auras.set_percent(_focus, int(value))
		if kept != int(value):
			_slider.set_value_no_signal(kept)
		_refresh())
	_detail.add_child(_slider)
	var scale_row := HBoxContainer.new()
	var lo := Label.new()
	lo.text = "%d%%" % Auras.MIN_PERCENT
	lo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lo.modulate = Color(0.6, 0.6, 0.6)
	scale_row.add_child(lo)
	var hi := Label.new()
	hi.text = "%d%%" % Auras.MAX_PERCENT
	hi.modulate = Color(0.6, 0.6, 0.6)
	scale_row.add_child(hi)
	_detail.add_child(scale_row)
	_footer = Label.new()
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", Color(0.85, 0.82, 0.65))
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_footer)

	_receiving_label = Label.new()
	_receiving_label.add_theme_font_size_override("font_size", 12)
	_receiving_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_receiving_label.modulate = Color(0.75, 0.9, 0.75)
	root.add_child(_receiving_label)
	var hint := Label.new()
	hint.text = "[C] fechar"
	hint.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(hint)
