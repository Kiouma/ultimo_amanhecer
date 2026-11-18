class_name RecipeCard
## Cartão de uma receita (inventário e telas de estação):
##   Nome do item ×N                                   6 s
##   Madeira 999/5      Pedra 55/5               [ Fabricar ]
## O número da esquerda é o que você tem; o da direita, o que a receita pede (verde se
## tem o bastante, vermelho se falta). O botão fica verde quando dá para fabricar.

const OK_COLOR := Color(0.45, 0.9, 0.45)
const MISSING_COLOR := Color(1.0, 0.42, 0.38)


static func build(player: Player, recipe: Dictionary, on_craft: Callable) -> Control:
	var inv := player.inventory
	var possible := Crafting.max_times(inv, recipe)
	var result := GameData.get_item(str(recipe.result))
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.13, 0.95) if possible > 0 else Color(0.1, 0.1, 0.1, 0.9)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 10
	style.border_color = Color(0.45, 0.7, 0.4, 0.6) if possible > 0 else Color(0.3, 0.3, 0.28, 0.6)
	style.border_width_left = 3
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = str(result.get("name", recipe.result)) + (" ×%d" % int(recipe.amount) if int(recipe.get("amount", 1)) > 1 else "")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.97, 0.95, 0.88) if possible > 0 else Color(0.62, 0.62, 0.58))
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	title.tooltip_text = "\n".join(ItemTooltip.effect_lines({"id": str(recipe.result), "count": 1}))
	head.add_child(title)
	var time := Label.new()
	time.text = "%s s" % str(recipe.get("time", 2))
	time.add_theme_font_size_override("font_size", 12)
	time.add_theme_color_override("font_color", Color(0.55, 0.56, 0.52))
	head.add_child(time)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	box.add_child(row)
	var ingredients: Dictionary = recipe.get("ingredients", {})
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.add_theme_constant_override("h_separation", 22)
	flow.add_theme_constant_override("v_separation", 2)
	row.add_child(flow)
	for id: String in ingredients:
		var need := int(ingredients[id])
		var have := inv.count_of(id)
		var label := RichTextLabel.new()
		label.bbcode_enabled = true
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.scroll_active = false
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_font_size_override("normal_font_size", 13)
		var color := OK_COLOR if have >= need else MISSING_COLOR
		label.text = "[color=#c9c9c0]%s[/color] [color=#ffffff]%d[/color][color=#888888]/[/color][color=#%s]%d[/color]" % [
			GameData.get_item(id).get("name", id), mini(have, 9999), color.to_html(false), need]
		flow.add_child(label)
	var craft := Button.new()
	craft.text = "Fabricar"
	craft.custom_minimum_size = Vector2(96, 30)
	craft.focus_mode = Control.FOCUS_NONE
	_color_button(craft, possible > 0)
	craft.pressed.connect(func() -> void:
		if Crafting.max_times(player.inventory, recipe) > 0:
			on_craft.call(recipe, 1)
		else:
			player.notify(TranslationServer.translate("Faltam recursos")))
	craft.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(craft)
	if possible >= 2:
		var all := Button.new()
		all.text = TranslationServer.translate("Tudo (%d)") % possible
		all.focus_mode = Control.FOCUS_NONE
		all.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		all.pressed.connect(func() -> void: on_craft.call(recipe, Crafting.max_times(player.inventory, recipe)))
		row.add_child(all)
	return card


## Botão verde (dá) ou vermelho (falta recurso).
static func _color_button(button: Button, ok: bool) -> void:
	var base := Color(0.22, 0.48, 0.24) if ok else Color(0.5, 0.18, 0.16)
	for state: Array in [["normal", base], ["hover", base.lightened(0.15)], ["pressed", base.darkened(0.2)], ["disabled", base.darkened(0.3)]]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = state[1]
		sb.set_corner_radius_all(4)
		sb.set_content_margin_all(4)
		button.add_theme_stylebox_override(state[0], sb)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
