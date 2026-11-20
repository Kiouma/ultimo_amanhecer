class_name ProgressionUI
extends Control
## Painel do personagem (tecla P): nível, XP e três abas (GDD 4.1, 4.2 e 12):
## - Árvore passiva: os pontos de nível (PassiveTreeView).
## - Ascendência: escolha no nível 30 e os nós dela.
## - Proficiências: as que sobem pelo uso e a maestria de armas.
## O equipamento e os status ficam no inventário (EquipmentPanel).

var player: Player

var _title: Label
var _points: Label
var _xp_bar: ProgressBar
var _tabs: TabContainer
var _tree: PassiveTreeView
var _status: Label
var _search: LineEdit
var _asc_box: VBoxContainer
var _profs: VBoxContainer
var _mastery: Label
var _confirm: ConfirmationDialog
var _pending_asc := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	UITabs.attach(self, "character")


func bind(p: Player) -> void:
	player = p
	_tree.progression = player.progression
	player.progression.changed.connect(func() -> void:
		if visible:
			_refresh())


func _unhandled_input(event: InputEvent) -> void:
	if player == null:
		return
	if event.is_action_pressed("progression"):
		toggle()
		get_viewport().set_input_as_handled()
	elif visible and (event.is_action_pressed("pause") or event.is_action_pressed("inventory")):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible and not player.health.is_dead
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED
	if visible:
		_status.text = ""
		_refresh()
		_tree.center_on_start.call_deferred()


func _refresh() -> void:
	var prog := player.progression
	var class_name_text := str(GameData.get_entry("backgrounds", prog.char_class).get("name", ""))
	var parts: PackedStringArray = [tr("Nível %d") % prog.char_level]
	if class_name_text != "":
		parts.append(class_name_text)
	if prog.ascendancy != "":
		parts.append(str(GameData.get_entry("ascendancies", prog.ascendancy).get("name", "")))
	_title.text = " · ".join(parts)
	_xp_bar.max_value = Progression.char_xp_to_next(prog.char_level)
	_xp_bar.value = prog.char_xp
	_xp_bar.tooltip_text = tr("%d / %d XP") % [int(prog.char_xp), int(_xp_bar.max_value)]
	var points := tr("Pontos passivos: %d") % prog.skill_points
	if prog.ascendancy != "":
		points += "  ·  " + tr("Pontos de ascendência: %d") % prog.ascendancy_points()
	elif prog.char_level >= Progression.ASCENDANCY_LEVEL:
		points += "  ·  " + tr("Ascendência disponível!")
	_points.text = points
	_tabs.set_tab_title(1, tr("Ascendência") + (" (!)" if (prog.ascendancy == "" and prog.char_level >= Progression.ASCENDANCY_LEVEL) or prog.ascendancy_points() > 0 else ""))
	_tree.queue_redraw()
	_tree._update_tip()
	_refresh_ascendancy()
	_refresh_profs()


# --- Proficiências ------------------------------------------------------------------------

func _refresh_profs() -> void:
	var prog := player.progression
	for c in _profs.get_children():
		c.queue_free()
	for id: String in GameData.get_all("proficiencies"):
		var data := GameData.get_entry("proficiencies", id)
		var level := prog.get_level(id)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 1)
		var head := Label.new()
		head.text = tr("%s · nível %d") % [data.get("name", id), level]
		head.add_theme_font_size_override("font_size", 14)
		row.add_child(head)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(0, 8)
		bar.show_percentage = false
		bar.max_value = Progression.xp_to_next(level)
		bar.value = float(prog.xp.get(id, 0.0))
		row.add_child(bar)
		var info := Label.new()
		info.text = tr("%s · sobe: %s") % [data.get("summary", ""), str(data.get("raised_by", "")).to_lower()]
		info.add_theme_font_size_override("font_size", 11)
		info.modulate = Color(0.75, 0.75, 0.72)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(info)
		_profs.add_child(row)
	var parts: PackedStringArray = []
	for t in ["bow", "melee", "unarmed", "spell", "thrown"]:
		parts.append("%s %d" % [Progression.mastery_name(t).capitalize(), prog.mastery_level(t)])
	_mastery.text = tr("Maestria (até +10% de dano): ") + " · ".join(parts)


# --- Ascendência --------------------------------------------------------------------------

func _refresh_ascendancy() -> void:
	var prog := player.progression
	for c in _asc_box.get_children():
		c.queue_free()
	if prog.ascendancy == "":
		var intro := _text("", 14)
		if prog.char_level < Progression.ASCENDANCY_LEVEL:
			intro.text = tr("A ascendência é escolhida no nível %d (você está no %d). Ela define a especialização do personagem: dá um bônus fixo e pontos de ascendência (níveis 30, 45, 60 e 75) para desbloquear os nós dela. Opções da sua classe:") % [Progression.ASCENDANCY_LEVEL, prog.char_level]
		else:
			intro.text = tr("Escolha a sua ascendência. A escolha é definitiva.")
		_asc_box.add_child(intro)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		_asc_box.add_child(row)
		for asc_id: String in prog.ascendancy_options():
			row.add_child(_asc_card(asc_id, true))
		return
	_asc_box.add_child(_asc_card(prog.ascendancy, false))


func _asc_card(asc_id: String, choosing: bool) -> Control:
	var prog := player.progression
	var data := GameData.get_entry("ascendancies", asc_id)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	var title := _text(str(data.get("name", asc_id)), 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	box.add_child(title)
	box.add_child(_text(str(data.get("desc", "")), 13, Color(0.8, 0.8, 0.76)))
	box.add_child(_text(tr("Bônus da ascendência: %s") % bonus_text(data.get("effects", {})), 13, Color(0.56, 0.78, 1.0)))
	if not choosing:
		box.add_child(_text(tr("Pontos de ascendência: %d de %d (ganha nos níveis 30, 45, 60 e 75)") % [prog.ascendancy_points(), prog.ascendancy_points_total()], 13))
	for n: Dictionary in data.get("nodes", []):
		var node_id := str(n.get("id", ""))
		var line := HBoxContainer.new()
		var unlocked := not choosing and prog.asc_nodes.has(node_id)
		var label := _text("%s%s: %s" % ["✓ " if unlocked else "• ", n.get("name", node_id), bonus_text(n.get("effects", {}))], 13,
			Color(0.6, 1.0, 0.6) if unlocked else Color(0.85, 0.85, 0.82))
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(label)
		if not choosing and not unlocked:
			var b := Button.new()
			b.text = tr("Desbloquear")
			b.disabled = prog.ascendancy_points() <= 0
			b.tooltip_text = tr("Sem pontos de ascendência") if b.disabled else ""
			b.pressed.connect(func() -> void: prog.unlock_asc_node(node_id))
			line.add_child(b)
		box.add_child(line)
	if choosing:
		var choose := Button.new()
		choose.text = tr("Escolher %s") % data.get("name", asc_id)
		var reason := prog.choose_block_reason(asc_id)
		choose.disabled = reason != ""
		choose.tooltip_text = reason
		choose.pressed.connect(func() -> void:
			_pending_asc = asc_id
			_confirm.dialog_text = tr("Escolher a ascendência %s? Não dá para trocar depois.") % data.get("name", asc_id)
			_confirm.popup_centered())
		box.add_child(choose)
	return panel


func _text(text: String, font_size: int, color := Color(0.92, 0.92, 0.88)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# --- Texto dos bônus (árvore, ascendência, auras e dicas de itens) -------------------------

const BONUS_NAMES := {
	"melee.damage": "Dano corpo a corpo", "ranged.damage": "Dano à distância", "magic.damage": "Dano mágico",
	"thrown.damage": "Dano de arremesso", "ranged.draw_time": "Tempo de puxada do arco", "move_speed": "Velocidade de movimento",
	"noise": "Barulho", "damage_taken": "Dano recebido", "max_stamina_add": "Stamina máxima", "max_mana_add": "Mana máxima",
	"magic.mana": "Custo de mana", "magic.cooldown": "Recarga de feitiços", "melee.stamina_cost": "Stamina por golpe",
	"sneak_damage": "Dano de ataque surpresa", "heal": "Cura de poções e comida",
	"ranged.recover_chance": "Recuperar flechas", "attack_speed": "Velocidade de ataque", "cooldown_reduction": "Redução de recarga",
	"spell_resist": "Resistência a magia", "carry_weight_add": "Capacidade de carga", "loot_bonus": "Aumento de loot",
	"headshot_damage": "Dano na cabeça", "magic.channel": "Força da canalização", "melee.channel": "Carga do golpe",
	"ranged.arrow_speed": "Velocidade da flecha", "unarmed.damage": "Dano desarmado", "unarmed.stamina_cost": "Stamina por soco", "gather_yield": "Coleta de recursos", "craft_time": "Tempo de fabricação",
	"max_health_add": "Vida máxima", "life_regen_add": "Regeneração de vida", "mana_regen": "Regeneração de mana",
	"stamina_regen": "Regeneração de stamina", "aura_effect": "Efeito das auras", "aura_radius": "Raio das auras",
	"reservation_efficiency": "Eficiência de reserva das auras", "melee.attack_time": "Tempo do golpe", "unarmed.attack_time": "Tempo do soco",
	"thrown.attack_time": "Tempo do arremesso", "magic.cast_time": "Tempo de conjuração", "sprint_stamina": "Stamina ao correr",
}


## ["Dano corpo a corpo +4%", "Vida máxima +10", ...] (nomes no idioma atual).
static func bonus_lines(bonus: Dictionary) -> PackedStringArray:
	var parts: PackedStringArray = []
	for key: String in bonus:
		var v := float(bonus[key])
		var label := TranslationServer.translate(str(BONUS_NAMES.get(key, key)))
		var value := ""
		if key == "life_regen_add":
			value = "%+.1f/s" % v
		elif key.ends_with("_add"):
			value = "%+d" % roundi(v)
		else:
			value = "%+d%%" % roundi(v * 100.0) if absf(v * 100.0 - roundf(v * 100.0)) < 0.05 else "%+.1f%%" % (v * 100.0)
		if key == "carry_weight_add":
			value += TranslationServer.translate(" kg")
		parts.append("%s %s" % [label, value])
	return parts


## "Dano corpo a corpo +4%, Capacidade de carga +10 kg" (nomes no idioma atual).
static func bonus_text(bonus: Dictionary) -> String:
	return ", ".join(bonus_lines(bonus))


# --- Montagem -----------------------------------------------------------------------------

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 36
	panel.offset_right = -36
	panel.offset_top = 58
	panel.offset_bottom = -22
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	margin.add_child(root)

	var head := HBoxContainer.new()
	root.add_child(head)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_points = Label.new()
	_points.add_theme_font_size_override("font_size", 15)
	_points.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	head.add_child(_points)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 10)
	_xp_bar.show_percentage = false
	root.add_child(_xp_bar)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	# Aba 1: árvore passiva.
	var tree_tab := VBoxContainer.new()
	tree_tab.name = "Árvore passiva"
	_tabs.add_child(tree_tab)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	tree_tab.add_child(tools)
	_search = LineEdit.new()
	_search.placeholder_text = "Buscar (nome ou efeito)"
	_search.custom_minimum_size = Vector2(220, 0)
	_search.clear_button_enabled = true
	tools.add_child(_search)
	var center := Button.new()
	center.text = "Centralizar"
	center.focus_mode = Control.FOCUS_NONE
	tools.add_child(center)
	for z: Array in [["+", 1.25], ["−", 0.8]]:
		var zb := Button.new()
		zb.text = z[0]
		zb.focus_mode = Control.FOCUS_NONE
		zb.custom_minimum_size = Vector2(30, 0)
		var factor: float = z[1]
		zb.pressed.connect(func() -> void: _tree.zoom_by(factor))
		tools.add_child(zb)
	var reset := Button.new()
	reset.text = "Devolver tudo"
	reset.focus_mode = Control.FOCUS_NONE
	tools.add_child(reset)
	var hint := Label.new()
	hint.text = "Clique: alocar · Botão direito: devolver · Arrastar: mover · Roda: zoom"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.7, 0.7, 0.68)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tools.add_child(hint)
	_tree = PassiveTreeView.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree_tab.add_child(_tree)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color(0.85, 0.82, 0.65))
	tree_tab.add_child(_status)
	_search.text_changed.connect(func(text: String) -> void: _tree.search = text)
	center.pressed.connect(func() -> void: _tree.center_on_start())
	_tree.message.connect(func(text: String) -> void: _status.text = text)

	# Aba 2: ascendência.
	var asc_scroll := ScrollContainer.new()
	asc_scroll.name = "Ascendência"
	asc_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(asc_scroll)
	_asc_box = VBoxContainer.new()
	_asc_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_asc_box.add_theme_constant_override("separation", 10)
	asc_scroll.add_child(_asc_box)

	# Aba 3: proficiências.
	var prof_tab := VBoxContainer.new()
	prof_tab.name = "Proficiências"
	_tabs.add_child(prof_tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	prof_tab.add_child(scroll)
	_profs = VBoxContainer.new()
	_profs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profs.add_theme_constant_override("separation", 6)
	scroll.add_child(_profs)
	_mastery = Label.new()
	_mastery.add_theme_font_size_override("font_size", 12)
	_mastery.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prof_tab.add_child(_mastery)

	var close_hint := Label.new()
	close_hint.text = "[P] fechar"
	close_hint.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(close_hint)

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Ascendência"
	_confirm.ok_button_text = "Escolher"
	_confirm.cancel_button_text = "Cancelar"
	_confirm.confirmed.connect(func() -> void:
		if _pending_asc != "":
			player.progression.choose_ascendancy(_pending_asc)
			_pending_asc = "")
	add_child(_confirm)

	var reset_confirm := ConfirmationDialog.new()
	reset_confirm.title = "Árvore passiva"
	reset_confirm.dialog_text = "Devolver todos os pontos passivos?"
	reset_confirm.ok_button_text = "Devolver"
	reset_confirm.cancel_button_text = "Cancelar"
	reset_confirm.confirmed.connect(func() -> void:
		player.progression.reset_passives()
		_status.text = tr("Todos os pontos passivos foram devolvidos"))
	add_child(reset_confirm)
	reset.pressed.connect(func() -> void: reset_confirm.popup_centered())
