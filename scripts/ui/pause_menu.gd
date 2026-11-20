class_name PauseMenu
extends Control
## Menu de pausa (Esc): voltar, salvar, configurações (idioma, mouse, volume, Shift/Ctrl),
## modo de jogo e sair para o menu. Não pausa o jogo (co-op: o mundo continua para todos).

var player: Player
var _status: Label
var _mode: OptionButton
var _main_box: VBoxContainer
var _settings: SettingsPanel
var _share_box: VBoxContainer
var _share_label: Label
var _copy_button: Button


func _ready() -> void:
	MouseMode.register(self)
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
	var stack := VBoxContainer.new()
	panel.add_child(stack)

	_main_box = VBoxContainer.new()
	_main_box.custom_minimum_size = Vector2(340, 0)
	_main_box.add_theme_constant_override("separation", 10)
	stack.add_child(_main_box)
	var title := Label.new()
	title.text = "Pausa"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	_main_box.add_child(title)
	_button(_main_box, "Voltar ao jogo", toggle)
	_button(_main_box, "Salvar agora", func() -> void:
		SaveGame.save_all()
		_status.text = tr("Salvo.") if multiplayer.is_server() else tr("Personagem salvo (o mundo é salvo pelo host)."))
	_button(_main_box, "Configurações", func() -> void: _show_settings(true))
	var mode_label := Label.new()
	mode_label.text = "Modo de jogo"
	_main_box.add_child(mode_label)
	_mode = OptionButton.new()
	_mode.add_item("Sobrevivência", 0)
	_mode.add_item("Criativo (invencível, itens infinitos, voo)", 1)
	_mode.item_selected.connect(func(index: int) -> void:
		if player:
			player.creative = index == 1
			_status.text = tr("Modo criativo: abra o Tab e use a aba Criativo.") if player.creative else tr("Modo sobrevivência."))
	_main_box.add_child(_mode)
	# Hospedando: como os amigos entram (IP público e porta, ou aviso de CGNAT/VPN).
	_share_box = VBoxContainer.new()
	_share_label = Label.new()
	_share_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_share_label.custom_minimum_size = Vector2(340, 0)
	_share_label.add_theme_font_size_override("font_size", 12)
	_share_label.add_theme_color_override("font_color", Color(0.75, 0.95, 0.75))
	_share_box.add_child(_share_label)
	_copy_button = Button.new()
	_copy_button.text = "Copiar endereço para os amigos"
	_copy_button.pressed.connect(func() -> void:
		DisplayServer.clipboard_set(Network.share_address())
		_status.text = tr("Endereço copiado: %s") % Network.share_address())
	_share_box.add_child(_copy_button)
	_main_box.add_child(_share_box)
	_button(_main_box, "Salvar e sair para o menu", _quit_to_menu)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.7, 1.0, 0.7)
	_main_box.add_child(_status)
	var help := Label.new()
	help.text = "Tab inventário · P personagem · M mapa · B construir\nE usar · R girar/melhorar · Q habilidade (segure: escolher) · V câmera"
	help.add_theme_font_size_override("font_size", 11)
	help.modulate = Color(0.75, 0.75, 0.72)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_main_box.add_child(help)

	_settings = SettingsPanel.new()
	_settings.visible = false
	_settings.closed.connect(func() -> void: _show_settings(false))
	stack.add_child(_settings)


func bind(p: Player) -> void:
	player = p


func _show_settings(on: bool) -> void:
	_settings.visible = on
	_main_box.visible = not on


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(action)
	parent.add_child(b)


func _unhandled_input(event: InputEvent) -> void:
	if player == null or not event.is_action_pressed("pause"):
		return
	# Com outra tela aberta (inventário, mapa...), o Esc é dela.
	if not visible and MouseMode.any_open():
		return
	if visible and _settings.visible:
		_show_settings(false)  # Esc nas configurações volta para a pausa
	else:
		toggle()
	get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible
	_status.text = ""
	_show_settings(false)
	if _mode and player:
		_mode.select(1 if player.creative else 0)
	var hosting := Network.is_online() and multiplayer.is_server()
	_share_box.visible = hosting
	if hosting:
		_share_label.text = Network.share_text()
		_copy_button.visible = Network.share_address() != ""
	MouseMode.refresh()


func _quit_to_menu() -> void:
	SaveGame.save_all()
	visible = false
	Network.leave()
	var main := get_tree().current_scene
	if main.has_method(&"_back_to_menu"):
		main._back_to_menu(tr("Jogo salvo."))
