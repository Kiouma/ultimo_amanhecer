class_name UITabs
extends HBoxContainer
## Abas no topo das telas cheias (Inventário, Personagem, Mapa): clicar troca de tela
## sem fechar e reabrir. Cada tela adiciona a sua (UITabs.attach) e o HUD faz a troca.

const TABS := [["inventory", "Inventário (Tab)"], ["character", "Personagem (P)"], ["map", "Mapa (M)"]]


## Põe a barra de abas no topo de `panel` (Control de tela cheia). current: aba ativa.
static func attach(panel: Control, current: String) -> UITabs:
	var bar := UITabs.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.add_theme_constant_override("separation", 6)
	for tab: Array in TABS:
		var b := Button.new()
		b.text = tab[1]
		b.toggle_mode = true
		b.button_pressed = tab[0] == current
		b.focus_mode = Control.FOCUS_NONE
		var target: String = tab[0]
		b.pressed.connect(func() -> void:
			b.button_pressed = target == current
			if target == current:
				return
			var hud := panel.get_parent()
			if hud and hud.has_method(&"open_panel"):
				hud.open_panel(target))
		bar.add_child(b)
	panel.add_child(bar)
	return bar
