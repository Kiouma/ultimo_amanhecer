class_name PauseMenu
extends Control
## Menu de pausa (Esc): voltar, salvar, sair para o menu, sensibilidade do mouse.
## Não pausa o jogo (co-op: o mundo continua para todos).

const SETTINGS_PATH := "user://settings.cfg"

var player: Player
var _sensitivity: HSlider
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Pausa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	_button(box, "Voltar ao jogo", toggle)
	_button(box, "Salvar agora", func() -> void:
		SaveGame.save_all()
		_status.text = "Salvo." if multiplayer.is_server() else "Personagem salvo (o mundo é salvo pelo host).")
	_button(box, "Salvar e sair para o menu", _quit_to_menu)
	var sens_label := Label.new()
	sens_label.text = "Sensibilidade do mouse"
	box.add_child(sens_label)
	_sensitivity = HSlider.new()
	_sensitivity.min_value = 0.0005
	_sensitivity.max_value = 0.006
	_sensitivity.step = 0.0001
	_sensitivity.value_changed.connect(func(v: float) -> void:
		if player:
			player.mouse_sensitivity = v
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("controls", "mouse_sensitivity", v)
		cfg.save(SETTINGS_PATH))
	box.add_child(_sensitivity)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.7, 1.0, 0.7)
	box.add_child(_status)
	var help := Label.new()
	help.text = "Tab inventário · P personagem · M mapa · B construir\nE usar · R recarregar/girar · Q/F feitiço · V câmera"
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(0.75, 0.75, 0.72)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(help)


## Aplica as configurações salvas (sensibilidade) e mostra no controle.
func bind(p: Player) -> void:
	player = p
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		p.mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", p.mouse_sensitivity))
	_sensitivity.set_value_no_signal(p.mouse_sensitivity)


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not event.is_action_pressed("pause"):
		return
	# Com outra tela aberta (inventário, mapa...), o Esc é dela.
	if not visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	toggle()
	get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	_status.text = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if visible else Input.MOUSE_MODE_CAPTURED


func _quit_to_menu() -> void:
	SaveGame.save_all()
	visible = false
	Network.leave()
	var main := get_tree().current_scene
	if main.has_method(&"_back_to_menu"):
		main._back_to_menu("Jogo salvo.")
