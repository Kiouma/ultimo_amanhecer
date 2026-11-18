class_name ProgressionUI
extends Control
## Painel do personagem (tecla P): nível, XP, proficiências, maestria de armas e,
## na coluna da direita, as trilhas de habilidades (GDD 4.1, 4.2 e 12).
## O equipamento e os status ficam no inventário (EquipmentPanel).

var player: Player

var _title: Label
var _xp_bar: ProgressBar
var _profs: VBoxContainer
var _mastery: Label
var _skills: VBoxContainer
var _points: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	UITabs.attach(self, "character")


func bind(p: Player) -> void:
	player = p
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
		_refresh()


func _refresh() -> void:
	var prog := player.progression
	_title.text = tr("Nível %d") % prog.char_level
	_xp_bar.max_value = Progression.char_xp_to_next(prog.char_level)
	_xp_bar.value = prog.char_xp
	_xp_bar.tooltip_text = tr("%d / %d XP") % [int(prog.char_xp), int(_xp_bar.max_value)]
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
	for t in ["bow", "melee", "spell", "thrown"]:
		parts.append("%s %d" % [Progression.mastery_name(t).capitalize(), prog.mastery_level(t)])
	_mastery.text = tr("Maestria (até +10% de dano): ") + " · ".join(parts)
	_refresh_skills()


## Coluna de habilidades, agrupadas por trilha.
func _refresh_skills() -> void:
	var prog := player.progression
	_points.text = tr("Pontos de habilidade: %d (1 por nível do personagem)") % prog.skill_points
	for c in _skills.get_children():
		c.queue_free()
	var by_trail := {}
	for id: String in GameData.get_all("skills"):
		var trail := str(GameData.get_entry("skills", id).get("trail", ""))
		if not by_trail.has(trail):
			by_trail[trail] = []
		by_trail[trail].append(id)
	for trail: String in by_trail:
		var title := Label.new()
		title.text = tr("Trilha do %s") % tr(str(Progression.TRAIL_NAMES.get(trail, trail)))
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
		_skills.add_child(title)
		for id: String in by_trail[trail]:
			_skills.add_child(_skill_row(id))


func _skill_row(id: String) -> Control:
	var prog := player.progression
	var data := GameData.get_entry("skills", id)
	var row := HBoxContainer.new()
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_label := Label.new()
	var learned := prog.skills.has(id)
	name_label.text = tr("%s%s (%d pt)") % ["✓ " if learned else "", data.get("name", id), int(data.get("cost", 1))]
	name_label.add_theme_font_size_override("font_size", 13)
	if learned:
		name_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	text.add_child(name_label)
	var desc := Label.new()
	var req: Dictionary = data.get("requires", {})
	var req_parts: PackedStringArray = []
	for prof: String in req:
		req_parts.append("%s %d" % [GameData.get_entry("proficiencies", prof).get("name", prof), int(req[prof])])
	desc.text = tr("%s · requer %s") % [data.get("desc", ""), ", ".join(req_parts)]
	desc.add_theme_font_size_override("font_size", 11)
	desc.modulate = Color(0.75, 0.75, 0.72)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(desc)
	row.add_child(text)
	if not learned:
		var button := Button.new()
		var reason := prog.learn_block_reason(id)
		button.text = "Aprender"
		button.disabled = reason != ""
		button.tooltip_text = reason
		button.pressed.connect(func() -> void:
			prog.learn(id))
		row.add_child(button)
	return row


# --- Texto dos bônus (dicas de itens) ---------------------------------------------------

const BONUS_NAMES := {
	"melee.damage": "Dano corpo a corpo", "ranged.damage": "Dano à distância", "magic.damage": "Dano mágico",
	"thrown.damage": "Dano de arremesso", "ranged.draw_time": "Tempo de puxada do arco", "move_speed": "Velocidade de movimento",
	"noise": "Barulho", "damage_taken": "Dano recebido", "max_stamina_add": "Stamina máxima", "max_mana_add": "Mana máxima",
	"magic.mana": "Custo de mana", "magic.cooldown": "Recarga de feitiços", "melee.stamina_cost": "Stamina por golpe",
	"sneak_damage": "Dano de ataque surpresa", "food": "Comida e bebida rendem", "heal": "Cura de bandagens e kits",
	"ranged.recover_chance": "Recuperar flechas", "attack_speed": "Velocidade de ataque", "cooldown_reduction": "Redução de recarga",
	"spell_resist": "Resistência a magia", "carry_weight_add": "Capacidade de carga", "loot_bonus": "Aumento de loot",
	"headshot_damage": "Dano na cabeça", "magic.channel": "Força da canalização", "melee.channel": "Carga do golpe",
	"ranged.arrow_speed": "Velocidade da flecha", "gather_yield": "Coleta de recursos", "craft_time": "Tempo de fabricação",
}


## "Dano corpo a corpo +4%, Capacidade de carga +10 kg" (nomes no idioma atual).
static func bonus_text(bonus: Dictionary) -> String:
	var parts: PackedStringArray = []
	for key: String in bonus:
		var v := float(bonus[key])
		var label := TranslationServer.translate(str(BONUS_NAMES.get(key, key)))
		var value := ("%+d" % roundi(v)) if key.ends_with("_add") else ("%+d%%" % roundi(v * 100.0))
		if key == "carry_weight_add":
			value += TranslationServer.translate(" kg")
		parts.append("%s %s" % [label, value])
	return ", ".join(parts)


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(900, 600)
	panel.position = -panel.custom_minimum_size * 0.5
	add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	margin.add_child(columns)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(400, 0)
	columns.add_child(left)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	left.add_child(_title)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(0, 12)
	_xp_bar.show_percentage = false
	left.add_child(_xp_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_profs = VBoxContainer.new()
	_profs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_profs.add_theme_constant_override("separation", 6)
	scroll.add_child(_profs)
	_mastery = Label.new()
	_mastery.add_theme_font_size_override("font_size", 12)
	_mastery.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_mastery)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	var skills_title := Label.new()
	skills_title.text = "Habilidades"
	skills_title.add_theme_font_size_override("font_size", 22)
	right.add_child(skills_title)
	_points = Label.new()
	right.add_child(_points)
	var skill_scroll := ScrollContainer.new()
	skill_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	skill_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(skill_scroll)
	_skills = VBoxContainer.new()
	_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skill_scroll.add_child(_skills)
	var hint := Label.new()
	hint.text = "[P] fechar"
	hint.modulate = Color(0.7, 0.7, 0.7)
	right.add_child(hint)
