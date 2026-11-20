class_name UITabs
extends HBoxContainer
## Abas das telas cheias (Inventário, Equipamentos, Personagem, Auras, Mapa e, no modo criativo, Criativo):
## clicar troca de tela sem fechar e reabrir. Ficam logo acima do painel da tela
## (frame), não no topo da janela. Cada tela adiciona a sua (UITabs.attach) e o HUD troca.

const TABS := [["inventory", "Inventário (Tab)"], ["equipment", "Equipamentos (V)"], ["character", "Personagem (P)"], ["auras", "Auras (C)"], ["map", "Mapa (M)"], ["creative", "Criativo"]]
const GAP := 6.0

var _screen: Control
var _frame: Control
var _current := ""


## Põe a barra de abas em `panel` (tela cheia), colada acima de `frame` (o painel
## visível; se null, o primeiro PanelContainer da tela). current: aba ativa.
static func attach(panel: Control, current: String, frame: Control = null) -> UITabs:
	var bar := UITabs.new()
	bar._screen = panel
	bar._current = current
	bar._frame = frame
	bar.add_theme_constant_override("separation", 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(bar)
	bar._rebuild()
	EventBus.creative_changed.connect(bar._on_creative_changed)
	panel.visibility_changed.connect(bar._rebuild)
	return bar


func _exit_tree() -> void:
	if EventBus.creative_changed.is_connected(_on_creative_changed):
		EventBus.creative_changed.disconnect(_on_creative_changed)


func _on_creative_changed(_on: bool) -> void:
	_rebuild()


func _creative_on() -> bool:
	var p: Variant = _screen.get(&"player") if _screen else null
	return is_instance_valid(p) and p is Node and bool(p.get(&"creative"))


func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	for tab: Array in TABS:
		var target: String = tab[0]
		if target == "creative" and not _creative_on() and _current != "creative":
			continue
		var b := Button.new()
		b.text = tab[1]
		b.toggle_mode = true
		b.button_pressed = target == _current
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void:
			b.button_pressed = target == _current
			if target == _current:
				return
			var hud := _screen.get_parent()
			if hud and hud.has_method(&"open_panel"):
				hud.open_panel(target))
		add_child(b)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _frame == null or not is_instance_valid(_frame):
		var found := _screen.find_children("*", "PanelContainer", true, false)
		if found.is_empty():
			return
		_frame = found[0]
	var rect := _frame.get_global_rect()
	var min_size := get_combined_minimum_size()
	size = min_size
	global_position = Vector2(rect.get_center().x - min_size.x * 0.5, maxf(rect.position.y - min_size.y - GAP, 4.0))
