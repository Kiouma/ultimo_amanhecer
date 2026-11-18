extends Node
## Cena inicial: menu principal e o contêiner do nível.
## Menu: Singleplayer, Multiplayer, Personagens, Configurações e Sair do jogo, sobre um
## cenário gerado na hora (MenuBackground).
## - Singleplayer: escolhe (ou cria) um mundo e depois o personagem que entra nele.
## - Multiplayer: hospedar (mundo + personagem) ou entrar pelo IP (só o personagem).
## - Personagens: criar (nome + passado) e excluir.
## O personagem leva inventário, equipamento, níveis e habilidades de mundo em mundo.
## O nível é criado pelo servidor dentro de "Level"; o LevelSpawner replica para os
## clientes, que recebem depois os jogadores e zumbis (ordem garantida pela replicação).

## Mundo aberto (Fase 7). --arena usa a arena de teste antiga.
const WORLD := preload("res://scenes/levels/world.tscn")
const ARENA := preload("res://scenes/levels/test_arena.tscn")

var _use_arena := false
## O que o jogador está fazendo no menu: "solo", "host", "join" ou "manage".
var _flow := "manage"
var _address := "127.0.0.1"
var _selected_world := ""
var _selected_character := ""
var _status_text := ""

var _background: MenuBackground
var _content: VBoxContainer
var _panel: PanelContainer

@onready var level_root: Node = $Level
@onready var menu: Control = %Menu


func _ready() -> void:
	Network.joined.connect(_on_joined)
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_closed.connect(func() -> void: _back_to_menu(tr("O host fechou a partida.")))
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if multiplayer.is_server():
			print("Jogador %d entrou." % id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if multiplayer.is_server():
			print("Jogador %d saiu." % id))
	_build_frame()
	_show_background(true)
	_show_main()
	_parse_command_line()


# --- Moldura e fundo -----------------------------------------------------------------

func _build_frame() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	menu.add_child(margin)
	var center := CenterContainer.new()
	margin.add_child(center)
	_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.07, 0.86)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(26)
	style.border_color = Color(0.95, 0.65, 0.4, 0.35)
	style.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", style)
	center.add_child(_panel)
	_content = VBoxContainer.new()
	_content.custom_minimum_size = Vector2(420, 0)
	_content.add_theme_constant_override("separation", 10)
	_panel.add_child(_content)


func _show_background(on: bool) -> void:
	if on and _background == null:
		_background = MenuBackground.new()
		add_child(_background)
	elif not on and _background:
		_background.queue_free()
		_background = null


func _clear() -> void:
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()


func _title(text: String, size := 30) -> void:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1.0, 0.86, 0.66))
	_content.add_child(l)


func _button(text: String, action: Callable, height := 42) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.pressed.connect(action)
	_content.add_child(b)
	return b


func _note(text: String, color := Color(0.65, 0.67, 0.62), size := 13) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	_content.add_child(l)
	return l


func _status() -> void:
	if _status_text != "":
		_note(_status_text, Color(0.95, 0.8, 0.45), 14)


# --- Telas -----------------------------------------------------------------------------

func _show_main() -> void:
	_clear()
	_title("Último Amanhecer", 38)
	var sub := _note("sobreviva até o amanhecer", Color(0.75, 0.72, 0.68), 14)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 10)
	_content.add_child(gap)
	_button("Singleplayer", func() -> void:
		_flow = "solo"
		_show_worlds())
	_button("Multiplayer", _show_multiplayer)
	_button("Personagens", func() -> void:
		_flow = "manage"
		_show_characters())
	_button("Configurações", _show_settings)
	_button("Sair do jogo", func() -> void: get_tree().quit())
	_status()


func _show_multiplayer() -> void:
	_clear()
	_title("Multiplayer")
	_note("Co-op: até 5 jogadores. O host usa a porta 7777 (UDP). Fora da mesma rede, o host precisa liberar essa porta no roteador.")
	_button("Hospedar partida (escolher mundo)", func() -> void:
		_flow = "host"
		_show_worlds())
	var row := HBoxContainer.new()
	var ip := LineEdit.new()
	ip.text = _address
	ip.placeholder_text = "IP do host"
	ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip.custom_minimum_size = Vector2(0, 40)
	row.add_child(ip)
	var join := Button.new()
	join.text = "Entrar"
	join.custom_minimum_size = Vector2(110, 40)
	join.pressed.connect(func() -> void:
		_address = ip.text.strip_edges() if ip.text.strip_edges() != "" else "127.0.0.1"
		_flow = "join"
		_show_characters())
	row.add_child(join)
	_content.add_child(row)
	_button("Voltar", _show_main, 36)
	_status()


func _show_settings() -> void:
	_clear()
	var panel := SettingsPanel.new()
	panel.closed.connect(_show_main)
	_content.add_child(panel)


## Mundos salvos (solo/host): escolher, criar ou excluir.
func _show_worlds() -> void:
	_clear()
	_title("Escolha o mundo")
	var worlds := SaveGame.list_worlds()
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 200)
	for w: Dictionary in worlds:
		var line: String = str(w.name) + "  ·  " + (tr("Dia %d") % int(w.day) if w.started else tr("novo"))
		list.add_item(line)
	_content.add_child(list)
	if worlds.is_empty():
		_note("Nenhum mundo ainda: crie um abaixo.")
	var create_row := HBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Nome do novo mundo"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.max_length = 32
	create_row.add_child(name_edit)
	var create := Button.new()
	create.text = "Criar mundo"
	create_row.add_child(create)
	_content.add_child(create_row)
	var go := _button("Continuar (escolher personagem)", func() -> void:
		_show_characters())
	var delete_world := func() -> void:
		SaveGame.delete_world(_selected_world)
		_selected_world = ""
		_show_worlds()
	var ask_delete := func() -> void:
		var world_label := str(SaveGame._read(SaveGame._world_path(_selected_world)).get("name", ""))
		_confirm(tr("Excluir o mundo \"%s\"? Não dá para desfazer.") % world_label, delete_world)
	var del := _button("Excluir mundo", ask_delete, 34)
	_button("Voltar", _show_main if _flow == "solo" else _show_multiplayer, 34)
	var select := func(index: int) -> void:
		_selected_world = str(worlds[index].id)
		go.disabled = false
		del.disabled = false
	list.item_selected.connect(select)
	list.item_activated.connect(func(index: int) -> void:
		select.call(index)
		_show_characters())
	go.disabled = true
	del.disabled = true
	for i in worlds.size():
		if worlds[i].id == _selected_world:
			list.select(i)
			select.call(i)
	var do_create := func() -> void:
		var n := name_edit.text.strip_edges()
		if n == "":
			n = tr("Mundo %d") % (worlds.size() + 1)
		_selected_world = SaveGame.create_world(n)
		_show_worlds()
	create.pressed.connect(do_create)
	name_edit.text_submitted.connect(func(_t: String) -> void: do_create.call())
	_status()


## Personagens: escolher para jogar (solo/host/join) ou só gerenciar.
func _show_characters() -> void:
	_clear()
	_title("Personagens" if _flow == "manage" else tr("Escolha o personagem"))
	if _flow != "manage":
		var where := tr("Mundo: %s") % SaveGame._read(SaveGame._world_path(_selected_world)).get("name", "") if _flow != "join" else tr("Entrar em %s") % _address
		_note(where, Color(0.8, 0.85, 0.75), 14)
	var chars := SaveGame.list_characters()
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(0, 190)
	for c: Dictionary in chars:
		var bg := str(GameData.get_entry("backgrounds", str(c.background)).get("name", ""))
		list.add_item("%s  ·  %s  ·  %s" % [c.name, tr("Nível %d") % int(c.level), bg])
	_content.add_child(list)
	if chars.is_empty():
		_note("Nenhum personagem ainda: crie um abaixo.")

	# Criar: nome + passado.
	var create_box := VBoxContainer.new()
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Nome do novo personagem"
	name_edit.max_length = 24
	create_box.add_child(name_edit)
	var bg_row := HBoxContainer.new()
	var picker := OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids: Array = GameData.get_all("backgrounds").keys()
	for id: String in ids:
		picker.add_item(str(GameData.get_entry("backgrounds", id).get("name", id)))
	bg_row.add_child(picker)
	var create := Button.new()
	create.text = "Criar personagem"
	bg_row.add_child(create)
	create_box.add_child(bg_row)
	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.7, 0.72, 0.66))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	create_box.add_child(desc)
	picker.item_selected.connect(func(i: int) -> void: desc.text = tr("Passado: %s") % GameData.get_entry("backgrounds", ids[i]).get("desc", ""))
	picker.select(0)
	desc.text = tr("Passado: %s") % GameData.get_entry("backgrounds", ids[0]).get("desc", "")
	_content.add_child(create_box)

	var play: Button = null
	if _flow != "manage":
		play = _button("Entrar no mundo" if _flow != "join" else tr("Conectar"), _start_with_selection)
	var delete_char := func() -> void:
		SaveGame.delete_character(_selected_character)
		_selected_character = ""
		_show_characters()
	var ask_delete := func() -> void:
		var char_label := str(SaveGame._read(SaveGame._character_path(_selected_character)).get("name", ""))
		_confirm(tr("Excluir o personagem \"%s\"? Itens e níveis serão perdidos.") % char_label, delete_char)
	var del := _button("Excluir personagem", ask_delete, 34)
	_button("Voltar", _character_back, 34)
	var select := func(index: int) -> void:
		_selected_character = str(chars[index].id)
		del.disabled = false
		if play:
			play.disabled = false
	list.item_selected.connect(select)
	if play:
		list.item_activated.connect(func(index: int) -> void:
			select.call(index)
			_start_with_selection())
		play.disabled = true
	del.disabled = true
	for i in chars.size():
		if chars[i].id == _selected_character:
			list.select(i)
			select.call(i)
	var do_create := func() -> void:
		var n := name_edit.text.strip_edges()
		if n == "":
			_status_text = tr("Dê um nome ao personagem.")
			_show_characters()
			return
		_status_text = ""
		_selected_character = SaveGame.create_character(n, str(ids[picker.selected]))
		_show_characters()
	create.pressed.connect(do_create)
	name_edit.text_submitted.connect(func(_t: String) -> void: do_create.call())
	_status()


func _character_back() -> void:
	match _flow:
		"solo", "host": _show_worlds()
		"join": _show_multiplayer()
		_: _show_main()


func _confirm(text: String, on_yes: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = text
	dialog.ok_button_text = tr("Excluir")
	dialog.cancel_button_text = tr("Cancelar")
	dialog.confirmed.connect(on_yes)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	menu.add_child(dialog)
	dialog.popup_centered()


# --- Começar ----------------------------------------------------------------------------

func _start_with_selection() -> void:
	if _selected_character == "":
		return
	_status_text = ""
	SaveGame.current_character_id = _selected_character
	match _flow:
		"solo":
			SaveGame.current_world_id = _selected_world
			Network.leave()
			_start_level()
		"host":
			SaveGame.current_world_id = _selected_world
			if Network.host() != OK:
				return
			_start_level()
		"join":
			SaveGame.current_world_id = ""
			if Network.join(_address) != OK:
				return
			_status_text = tr("Conectando a %s...") % _address
			_show_main()


func _on_joined() -> void:
	# O nível chega sozinho pelo LevelSpawner.
	menu.visible = false
	_show_background(false)


func _on_connection_failed(reason: String) -> void:
	_back_to_menu(reason)


func _start_level() -> void:
	menu.visible = false
	_show_background(false)
	var level := (ARENA if _use_arena else WORLD).instantiate()
	var saved := 0 if _use_arena else SaveGame.saved_seed()
	if saved != 0:
		level.world_seed = saved
		level.from_save = true
	level_root.add_child(level, true)
	if saved != 0:
		SaveGame.apply_world(level)
	else:
		# Mundo novo: grava logo a semente (e o resto) para ele aparecer como começado.
		get_tree().create_timer(2.0).timeout.connect(SaveGame.save_all)


func _back_to_menu(message: String) -> void:
	for child in level_root.get_children():
		child.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.visible = true
	_show_background(true)
	_status_text = message
	_show_main()


## Atalhos para testar sem clicar (depois de "--"): --solo, --host, --join=IP.
## --world=<id> e --character=<id> escolhem os saves (senão, o mais recente; sem
## nenhum, cria um). --new cria um mundo novo. --save-root=user://pasta isola os saves.
func _parse_command_line() -> void:
	var args := OS.get_cmdline_user_args()
	var world_arg := ""
	var char_arg := ""
	var new_world := false
	var background := "survivor"
	for arg in args:
		if arg == "--arena":
			_use_arena = true
		elif arg == "--new":
			new_world = true
		elif arg.begins_with("--world="):
			world_arg = arg.get_slice("=", 1)
		elif arg.begins_with("--character="):
			char_arg = arg.get_slice("=", 1)
		elif arg.begins_with("--background="):
			background = arg.get_slice("=", 1)
	for arg in args:
		if not (arg in ["--solo", "--host"] or arg.begins_with("--join")):
			continue
		var chars := SaveGame.list_characters()
		_selected_character = char_arg if char_arg != "" else (str(chars[0].id) if not chars.is_empty() else SaveGame.create_character(tr("Sobrevivente"), background))
		if arg.begins_with("--join"):
			_address = arg.get_slice("=", 1) if "=" in arg else "127.0.0.1"
			_flow = "join"
		else:
			var worlds := SaveGame.list_worlds()
			_selected_world = world_arg if world_arg != "" else (str(worlds[0].id) if not worlds.is_empty() and not new_world else SaveGame.create_world(tr("Mundo rápido")))
			_flow = "solo" if arg == "--solo" else "host"
		_start_with_selection.call_deferred()
		return
