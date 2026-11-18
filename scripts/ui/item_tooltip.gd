class_name ItemTooltip
## Painel de informações de um item (mouse em cima de um slot): nome, tipo, efeitos
## ("Recupera 40 de sede"), números de arma/armadura, durabilidade, peso e, no rodapé,
## as etiquetas "Material" (usado em alguma receita) e "Consumível".

const TYPE_NAMES := {
	"melee": "Arma corpo a corpo", "unarmed": "Desarmado", "bow": "Arma à distância", "thrown": "Arma de arremesso",
	"focus": "Cajado", "tool": "Ferramenta", "armor": "Equipamento", "consumable": "Consumível", "resource": "Recurso",
	"ammo": "Munição", "grimoire": "Grimório", "station": "Estação", "trap": "Armadilha", "spell": "Habilidade",
}

static var _materials := {}


static func t(text: String) -> String:
	return TranslationServer.translate(text)


## Itens usados como ingrediente em alguma receita.
static func is_material(id: String) -> bool:
	if _materials.is_empty():
		for rid: String in GameData.get_all("recipes"):
			for ing: String in GameData.get_entry("recipes", rid).get("ingredients", {}):
				_materials[ing] = true
	return _materials.has(id)


## Linhas de efeito do item (sem nome, tipo, peso): usado no painel e em testes.
static func effect_lines(s: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var data := GameData.get_item(str(s.get("id", "")))
	var type := str(data.get("type", ""))
	var power := Inventory.quality_multiplier(s) * Inventory.refine_multiplier(s) if data.has("durability") else 1.0
	if float(data.get("food", 0.0)) > 0.0:
		lines.append(t("Recupera %d de fome") % roundi(float(data.food)))
	if float(data.get("water", 0.0)) > 0.0:
		lines.append(t("Recupera %d de sede") % roundi(float(data.water)))
	if float(data.get("heals", 0.0)) > 0.0:
		lines.append(t("Recupera %d de vida") % roundi(float(data.heals)))
	if float(data.get("sick_chance", 0.0)) > 0.0:
		lines.append(t("Chance de passar mal: %d%%") % roundi(float(data.sick_chance) * 100.0))
	if data.has("returns"):
		lines.append(t("Devolve: %s") % GameData.get_item(str(data.returns)).get("name", data.returns))
	match type:
		"melee", "thrown":
			lines.append(t("Dano: %d") % roundi(float(data.get("damage", 0.0)) * power))
			lines.append(t("Tempo de ataque: %.2f s") % float(data.get("attack_time", 0.65)))
			if data.has("stamina_cost"):
				lines.append(t("Stamina por golpe: %d") % roundi(float(data.stamina_cost)))
			var gather: Dictionary = data.get("gather", {})
			if not gather.is_empty():
				var parts := PackedStringArray()
				for kind: String in gather:
					parts.append("%s ×%.1f" % [t({"tree": "madeira", "rock": "pedra"}.get(kind, kind)), float(gather[kind]) * power])
				lines.append(t("Coleta: %s") % ", ".join(parts))
			if float(data.get("sneak_mult", 1.0)) > 1.0:
				lines.append(t("Ataque surpresa: ×%.1f") % float(data.sneak_mult))
		"bow":
			lines.append(t("Dano: %d") % roundi(float(data.get("damage", 0.0)) * power))
			lines.append(t("Puxada: %.1f s") % float(data.get("draw_time", 0.8)))
			lines.append(t("Munição: %s") % GameData.get_item(str(data.get("ammo", "arrow"))).get("name", ""))
		"focus":
			lines.append(t("Conjura a habilidade escolhida no Q; segure para canalizar"))
		"armor":
			var armor := float(data.get("armor", 0.0)) * power
			if armor > 0.0:
				lines.append(t("Proteção: %d") % roundi(armor))
			var bonus := ProgressionUI.bonus_text(data.get("bonus", {}))
			if bonus != "":
				lines.append(bonus)
			if str(data.get("set", "")) != "":
				var set_data := GameData.get_entry("sets", str(data.set))
				lines.append(t("Conjunto: %s") % "%s (%s)" % [set_data.get("name", data.set), set_data.get("style", "")])
		"grimoire":
			var names := PackedStringArray()
			for spell: String in data.get("teaches", []):
				names.append(str(GameData.get_item(spell).get("name", spell)))
			lines.append(t("Ensina: %s") % ", ".join(names))
			for prof: String in data.get("requires", {}):
				lines.append(t("Requer: %s %d") % [GameData.get_entry("proficiencies", prof).get("name", prof), int(data.requires[prof])])
		"station", "trap":
			lines.append(t("Selecione na hotbar e clique para colocar à frente"))
		"ammo":
			var users := PackedStringArray()
			for wid: String in GameData.get_all("items"):
				if str(GameData.get_entry("items", wid).get("ammo", "")) == str(s.get("id", "")):
					users.append(str(GameData.get_entry("items", wid).get("name", wid)))
			if not users.is_empty():
				lines.append(t("Usada por: %s") % ", ".join(users))
	if str(data.get("desc", "")) != "":
		lines.append(str(data.desc))
	return lines


## Etiquetas do rodapé ("Material", "Consumível").
static func tags(s: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var id := str(s.get("id", ""))
	if is_material(id):
		out.append(t("Material"))
	if GameData.get_item(id).get("type", "") == "consumable":
		out.append(t("Consumível"))
	return out


static func build(s: Dictionary) -> Control:
	var data := GameData.get_item(str(s.get("id", "")))
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.075, 0.07, 0.96)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(10)
	style.set_border_width_all(1)
	var tier := Inventory.tier_of(s)
	style.border_color = Inventory.TIER_COLORS[tier - 1] if tier > 0 else Color(0.4, 0.4, 0.38)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	box.custom_minimum_size = Vector2(240, 0)
	panel.add_child(box)
	_label(box, Inventory.display_name_of(s), 16, style.border_color.lightened(0.3) if tier > 0 else Color(0.97, 0.95, 0.88))
	var type := str(data.get("type", ""))
	var type_text := t(str(TYPE_NAMES.get(type, type)))
	if type == "armor":
		type_text += " · " + t(str(Equipment.SLOT_NAMES.get(str(data.get("slot", "")), "Anel" if data.get("slot", "") == "ring" else "")))
	_label(box, type_text, 12, Color(0.65, 0.66, 0.6))
	for line in effect_lines(s):
		_label(box, line, 13, Color(0.75, 0.95, 0.75))
	var max_dur := Inventory.max_durability_of(s)
	if max_dur > 0.0:
		_label(box, t("Durabilidade: %d/%d") % [roundi(Inventory.durability_of(s)), roundi(max_dur)], 12,
			Color(1, 0.5, 0.4) if Inventory.is_broken(s) else Color(0.8, 0.8, 0.76))
		_label(box, t("Qualidade %d (+%d%% dano, durabilidade e eficiência)") % [Inventory.quality_of(s), roundi((Inventory.quality_multiplier(s) - 1.0) * 100)], 12, Color(0.8, 0.8, 0.76))
		if Inventory.refine_of(s) > 0:
			_label(box, t("Refino +%d (+%d%% dano/eficiência)") % [Inventory.refine_of(s), Inventory.refine_of(s) * 5], 12, Color(0.8, 0.8, 0.76))
	var weight := float(data.get("weight", 0.0))
	var count := int(s.get("count", 1))
	_label(box, t("Peso: %.2f kg") % weight + (t(" (pilha: %.1f kg)") % (weight * count) if count > 1 else ""), 11, Color(0.6, 0.6, 0.56))
	var footer := tags(s)
	if not footer.is_empty():
		box.add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		for tag in footer:
			var chip := PanelContainer.new()
			var chip_style := StyleBoxFlat.new()
			chip_style.bg_color = Color(0.25, 0.32, 0.45, 0.9) if tag == t("Material") else Color(0.42, 0.3, 0.18, 0.9)
			chip_style.set_corner_radius_all(3)
			chip_style.set_content_margin_all(3)
			chip_style.content_margin_left = 7
			chip_style.content_margin_right = 7
			chip.add_theme_stylebox_override("panel", chip_style)
			var l := Label.new()
			l.text = tag
			l.add_theme_font_size_override("font_size", 11)
			chip.add_child(l)
			row.add_child(chip)
		box.add_child(row)
	return panel


static func _label(parent: Control, text: String, size: int, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(240, 0)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
