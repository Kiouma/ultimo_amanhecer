class_name AuraUI
extends Control
## Tela de auras (tecla C), em duas partes:
## - Em cima, só os ícones das auras, espaçados, com o nome completo em cima de cada um.
## - Clicar num ícone SELECIONA a aura (não liga/desliga): embaixo, no centro, aparece
##   uma cópia do ícone, o nível como título, a descrição completa, a barra de reserva
##   (estreita, % no topo) e, por último, o interruptor Ativado (verde) / Desativado
##   (vermelho), que é o que liga e desliga.
## As auras recebidas aparecem como ícones na barra de buffs do HUD (BuffBar).

const ICON := Vector2(56, 56)
const BIG_ICON := Vector2(68, 68)
const CELL_WIDTH := 104.0
const SLIDER_WIDTH := 260.0

var player: Player

var _reserve_label: Label
var _receiving_label: Label
var _hint: Label
var _detail: VBoxContainer
var _big_icon: Panel
var _big_label: Label
var _title: Label
var _desc: Label
var _effect: Label
var _percent_label: Label
var _slider: HSlider
var _lo_label: Label
var _hi_label: Label
var _switch: ToggleSwitch
var _footer: Label
var _icons := {}  # id → Button
var _focus := ""
## Montando o detalhe: mudar os limites da barra dispara value_changed; ignora.
var _updating := false
var _strip_timer := 0.0


func _ready() -> void:
	MouseMode.register(self)
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
	MouseMode.refresh()
	if visible:
		_footer.text = ""
		_refresh()


func _process(delta: float) -> void:
	_strip_timer -= delta
	if player == null or not visible or _strip_timer > 0.0:
		return
	_strip_timer = 0.5
	var names: PackedStringArray = []
	for entry: Array in player.auras.received():
		var aura_name := str(GameData.get_entry("auras", entry[0]).get("name", entry[0]))
		var source: Node = entry[2]
		if source != player and is_instance_valid(source):
			aura_name += " (%s)" % _player_name(source)
		names.append(aura_name)
	_receiving_label.text = tr("Recebendo agora: %s") % (", ".join(names) if not names.is_empty() else tr("nenhuma"))


func _player_name(p: Node) -> String:
	return str(p.call(&"display_name")) if p.has_method(&"display_name") else tr("aliado")


# --- Atualização ----------------------------------------------------------------------------

func _refresh() -> void:
	var auras := player.auras
	_reserve_label.text = tr("Mana reservada: %d%%  ·  Vida reservada: %d%%  (máximo %d%% de cada)") % [
		roundi(auras.reserved_fraction("mana") * 100.0), roundi(auras.reserved_fraction("life") * 100.0), roundi(Auras.MAX_RESERVED * 100.0)]
	for id: String in _icons:
		_style_icon(_icons[id], id, id == _focus)
	_refresh_detail()


func _aura_color(id: String) -> Color:
	return Color.from_string(str(GameData.get_entry("auras", id).get("color", "#ffffff")), Color.WHITE)


## Fundo e borda do ícone: aura ligada fica preenchida com a cor dela; selecionada
## ganha borda branca; bloqueada fica cinza.
func _icon_style(id: String, selected: bool, hover := false) -> StyleBoxFlat:
	var auras := player.auras
	var color := _aura_color(id)
	var active := auras.is_active(id)
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(8)
	style.bg_color = color.darkened(0.35) if active else Color(0.1, 0.1, 0.12)
	style.border_color = color.lightened(0.3) if active else (color.darkened(0.2) if auras.is_unlocked(id) else Color(0.3, 0.3, 0.32))
	style.set_border_width_all(3 if active else 2)
	if selected or hover:
		style.border_color = Color.WHITE
		style.set_border_width_all(3)
	return style


func _style_icon(b: Button, id: String, selected: bool) -> void:
	b.add_theme_stylebox_override("normal", _icon_style(id, selected))
	b.add_theme_stylebox_override("pressed", _icon_style(id, selected))
	b.add_theme_stylebox_override("focus", _icon_style(id, selected))
	b.add_theme_stylebox_override("hover", _icon_style(id, selected, true))
	b.modulate = Color.WHITE if player.auras.is_unlocked(id) else Color(0.55, 0.55, 0.55)


func _initials(text: String) -> String:
	var out := ""
	for word: String in text.split(" ", false):
		if word.length() > 2:
			out += word.left(1).to_upper()
	return out.left(3)


func _refresh_detail() -> void:
	_detail.visible = _focus != ""
	_hint.visible = _focus == ""
	if _focus == "":
		return
	var auras := player.auras
	var data := GameData.get_entry("auras", _focus)
	var color := _aura_color(_focus)
	var converter := auras.is_converter(_focus)
	# Cópia do ícone.
	_big_icon.add_theme_stylebox_override("panel", _icon_style(_focus, false))
	_big_icon.modulate = Color.WHITE if auras.is_unlocked(_focus) else Color(0.55, 0.55, 0.55)
	_big_label.text = _initials(str(data.get("name", _focus)))
	# Título: nome e nível.
	var lvl := auras.level(_focus)
	_title.text = str(data.get("name", _focus)) if converter else tr("%s  ·  Nível %d") % [data.get("name", _focus), lvl]
	_title.add_theme_color_override("font_color", color.lightened(0.2))
	_desc.text = str(data.get("desc", ""))
	# Efeito e números.
	var pct := auras.get_percent(_focus)
	var cost := auras.cost_of(_focus)
	var lines: PackedStringArray = []
	if converter:
		lines.append(tr("Converte %d%% da reserva de mana das outras auras em reserva de vida.") % pct)
		lines.append(tr("Custo próprio: %d%% de vida.") % int(data.get("cost", 0)))
	else:
		lines.append(tr("Efeito agora: %s") % ProgressionUI.bonus_text(auras.effects_at(_focus, auras.strength(_focus))))
		var level_line := tr("Raio %.0f m · nível %d: +%d%% de efeito") % [auras.radius(), lvl, roundi(Auras.LEVEL_BONUS * (lvl - 1) * 100.0)]
		if lvl < Auras.MAX_LEVEL:
			level_line += " · " + tr("próximo nível: %d / %d s") % [int(float(auras.xp.get(_focus, 0.0))), int(Auras.xp_to_next(lvl))]
		lines.append(level_line)
		if lvl < Auras.MAX_LEVEL:
			lines.append(tr("Evoluindo agora") if auras.levels_now(_focus) else tr("Nota: a aura só evolui ligada com a reserva no máximo (%d%%); com menos, o tempo não conta.") % Auras.MAX_PERCENT)
	var real: PackedStringArray = []
	if float(cost.mana) >= 0.005:
		real.append(tr("%d%% de mana") % roundi(float(cost.mana) * 100.0))
	elif float(cost.mana) <= -0.005:
		real.append(tr("libera %d%% de mana") % roundi(-float(cost.mana) * 100.0))
	if absf(float(cost.life)) >= 0.005:
		real.append(tr("%d%% de vida") % roundi(float(cost.life) * 100.0))
	if not real.is_empty():
		lines.append(tr("Reserva real (com conversão e eficiência): %s") % ", ".join(real))
	_effect.text = "\n".join(lines)
	# Barra.
	var r := auras.percent_range(_focus)
	_updating = true
	_slider.min_value = r.x
	_slider.max_value = r.y
	_slider.set_value_no_signal(pct)
	_updating = false
	_lo_label.text = "%d%%" % r.x
	_hi_label.text = "%d%%" % r.y
	if converter:
		_percent_label.text = tr("%d%% convertido em vida") % pct
	else:
		var resource := tr("mana") if str(data.get("resource", "mana")) == "mana" else tr("vida")
		_percent_label.text = tr("%d%% de %s") % [pct, resource]
	# Interruptor.
	var lock := auras.lock_reason(_focus)
	_switch.on = auras.is_active(_focus)
	_switch.disabled = lock != ""
	if lock != "":
		_footer.text = lock


func _select(id: String) -> void:
	_focus = id
	_footer.text = ""
	_refresh()


# --- Montagem -------------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(700, 640)
	panel.position = -panel.custom_minimum_size * 0.5
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 5)
	margin.add_child(root)

	var title := Label.new()
	title.text = "Auras"
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	_reserve_label = Label.new()
	_reserve_label.add_theme_font_size_override("font_size", 13)
	_reserve_label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	root.add_child(_reserve_label)

	# Ícones com o nome em cima.
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 26)
	grid.add_theme_constant_override("v_separation", 10)
	var grid_center := CenterContainer.new()
	grid_center.add_child(grid)
	root.add_child(grid_center)
	for id: String in GameData.get_all("auras"):
		var cell := VBoxContainer.new()
		cell.custom_minimum_size = Vector2(CELL_WIDTH, 0)
		cell.add_theme_constant_override("separation", 3)
		var name_label := Label.new()
		name_label.text = str(GameData.get_entry("auras", id).get("name", id))
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 12)
		cell.add_child(name_label)
		var b := Button.new()
		b.custom_minimum_size = ICON
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.focus_mode = Control.FOCUS_NONE
		b.text = _initials(name_label.text)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_select.bind(id))
		cell.add_child(b)
		grid.add_child(cell)
		_icons[id] = b

	root.add_child(HSeparator.new())
	_hint = Label.new()
	_hint.text = "Clique numa aura para ver os detalhes e ativar."
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.modulate = Color(0.7, 0.7, 0.68)
	_hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_hint)

	# Detalhe da aura selecionada, centralizado.
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 3)
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_detail)
	var icon_center := CenterContainer.new()
	_detail.add_child(icon_center)
	_big_icon = Panel.new()
	_big_icon.custom_minimum_size = BIG_ICON
	icon_center.add_child(_big_icon)
	_big_label = Label.new()
	_big_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_big_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_big_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_big_label.add_theme_font_size_override("font_size", 24)
	_big_icon.add_child(_big_label)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	_detail.add_child(_title)
	_desc = Label.new()
	_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.add_theme_font_size_override("font_size", 14)
	_detail.add_child(_desc)
	_effect = Label.new()
	_effect.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_effect.add_theme_font_size_override("font_size", 13)
	_effect.add_theme_color_override("font_color", Color(0.56, 0.78, 1.0))
	_detail.add_child(_effect)

	# Barra de reserva estreita, com a % no topo e no centro.
	var bar_center := CenterContainer.new()
	_detail.add_child(bar_center)
	var bar_box := VBoxContainer.new()
	bar_box.custom_minimum_size = Vector2(SLIDER_WIDTH, 0)
	bar_box.add_theme_constant_override("separation", 2)
	bar_center.add_child(bar_box)
	_percent_label = Label.new()
	_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_percent_label.add_theme_font_size_override("font_size", 15)
	bar_box.add_child(_percent_label)
	_slider = HSlider.new()
	_slider.step = 1
	_slider.tick_count = 8
	_slider.ticks_on_borders = true
	_slider.focus_mode = Control.FOCUS_NONE
	_slider.custom_minimum_size = Vector2(SLIDER_WIDTH, 18)
	_slider.value_changed.connect(func(value: float) -> void:
		if _focus == "" or player == null or _updating:
			return
		var kept := player.auras.set_percent(_focus, int(value))
		if kept != int(value):
			_slider.set_value_no_signal(kept)
			_footer.text = tr("Limite de reserva: %d%% de cada recurso") % roundi(Auras.MAX_RESERVED * 100.0)
		_refresh())
	bar_box.add_child(_slider)
	var scale_row := HBoxContainer.new()
	_lo_label = Label.new()
	_lo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lo_label.modulate = Color(0.6, 0.6, 0.6)
	_lo_label.add_theme_font_size_override("font_size", 11)
	scale_row.add_child(_lo_label)
	_hi_label = Label.new()
	_hi_label.modulate = Color(0.6, 0.6, 0.6)
	_hi_label.add_theme_font_size_override("font_size", 11)
	scale_row.add_child(_hi_label)
	bar_box.add_child(scale_row)

	# Interruptor na parte de baixo.
	var switch_center := CenterContainer.new()
	_detail.add_child(switch_center)
	_switch = ToggleSwitch.new()
	_switch.toggled_by_user.connect(func() -> void:
		if _focus == "" or player == null:
			return
		var reason := player.auras.toggle(_focus)
		_footer.text = reason
		_refresh())
	switch_center.add_child(_switch)
	_footer = Label.new()
	_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_footer.add_theme_font_size_override("font_size", 13)
	_footer.add_theme_color_override("font_color", Color(0.95, 0.75, 0.55))
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(_footer)

	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	_receiving_label = Label.new()
	_receiving_label.add_theme_font_size_override("font_size", 12)
	_receiving_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_receiving_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_receiving_label.modulate = Color(0.75, 0.9, 0.75)
	bottom.add_child(_receiving_label)
	var hint := Label.new()
	hint.text = "[C] fechar"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.7, 0.7, 0.7)
	bottom.add_child(hint)
