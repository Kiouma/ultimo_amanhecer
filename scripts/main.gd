extends Node
## Cena inicial: menu (solo / hospedar / entrar) e o contêiner do nível.
## O nível é criado pelo servidor dentro de "Level"; o LevelSpawner replica para os
## clientes, que recebem depois os jogadores e zumbis (ordem garantida pela replicação).

## Mundo aberto (Fase 7). --arena usa a arena de teste antiga.
const WORLD := preload("res://scenes/levels/world.tscn")
const ARENA := preload("res://scenes/levels/test_arena.tscn")

var _use_arena := false

@onready var level_root: Node = $Level
@onready var menu: Control = %Menu
@onready var address_edit: LineEdit = %Address
@onready var status_label: Label = %Status
@onready var buttons: Array[Button] = [%SoloButton, %HostButton, %JoinButton]


func _ready() -> void:
	%SoloButton.pressed.connect(_on_solo)
	%HostButton.pressed.connect(_on_host)
	%JoinButton.pressed.connect(_on_join)
	Network.joined.connect(_on_joined)
	Network.connection_failed.connect(_on_connection_failed)
	Network.server_closed.connect(func() -> void: _back_to_menu("O host fechou a partida."))
	multiplayer.peer_connected.connect(func(id: int) -> void:
		if multiplayer.is_server():
			print("Jogador %d entrou." % id))
	multiplayer.peer_disconnected.connect(func(id: int) -> void:
		if multiplayer.is_server():
			print("Jogador %d saiu." % id))
	status_label.text = ""
	_build_background_picker()
	_build_save_options()
	_parse_command_line()


## Opções de carregar o mundo e o personagem salvos (aparecem se houver save).
func _build_save_options() -> void:
	var vbox := (%SoloButton as Control).get_parent()
	var at := (%SoloButton as Control).get_index()
	if SaveGame.has_character():
		var check := CheckBox.new()
		check.text = "Continuar personagem salvo (%s)" % SaveGame.character_summary()
		check.button_pressed = true
		SaveGame.load_character = true
		check.toggled.connect(func(on: bool) -> void: SaveGame.load_character = on)
		vbox.add_child(check)
		vbox.move_child(check, at)
		at += 1
	if SaveGame.has_world():
		var check := CheckBox.new()
		check.text = "Continuar mundo salvo (%s) · sozinho ou hospedando" % SaveGame.world_summary()
		check.button_pressed = true
		SaveGame.load_world = true
		check.toggled.connect(func(on: bool) -> void: SaveGame.load_world = on)
		vbox.add_child(check)
		vbox.move_child(check, at)


## Escolha do passado (GDD 4.4), acima dos botões do menu.
func _build_background_picker() -> void:
	var vbox := (%SoloButton as Control).get_parent()
	var label := Label.new()
	label.text = "Passado do personagem"
	var picker := OptionButton.new()
	var desc := Label.new()
	desc.add_theme_font_size_override("font_size", 12)
	desc.modulate = Color(0.8, 0.8, 0.75)
	var ids: Array = GameData.get_all("backgrounds").keys()
	for id: String in ids:
		picker.add_item(str(GameData.get_entry("backgrounds", id).get("name", id)))
	var select := func(index: int) -> void:
		Network.background = ids[index]
		desc.text = str(GameData.get_entry("backgrounds", ids[index]).get("desc", ""))
	picker.item_selected.connect(select)
	var start := maxi(ids.find(Network.background), 0)
	picker.select(start)
	select.call(start)
	var at := (%SoloButton as Control).get_index()
	vbox.add_child(label)
	vbox.move_child(label, at)
	vbox.add_child(picker)
	vbox.move_child(picker, at + 1)
	vbox.add_child(desc)
	vbox.move_child(desc, at + 2)


func _on_solo() -> void:
	Network.leave()
	_start_level()


func _on_host() -> void:
	if Network.host() != OK:
		return
	_start_level()
	status_label.text = "Hospedando na porta %d." % Network.DEFAULT_PORT


func _on_join() -> void:
	var address := address_edit.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	if Network.join(address) != OK:
		return
	status_label.text = "Conectando a %s..." % address
	_set_buttons_enabled(false)


func _on_joined() -> void:
	# O nível chega sozinho pelo LevelSpawner.
	menu.visible = false


func _on_connection_failed(reason: String) -> void:
	_back_to_menu(reason)


func _start_level() -> void:
	menu.visible = false
	var level := (ARENA if _use_arena else WORLD).instantiate()
	var loading := not _use_arena and SaveGame.load_world and SaveGame.saved_seed() != 0
	if loading:
		level.world_seed = SaveGame.saved_seed()
		level.from_save = true
	level_root.add_child(level, true)
	if loading:
		SaveGame.apply_world(level)


func _back_to_menu(message: String) -> void:
	for child in level_root.get_children():
		child.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu.visible = true
	status_label.text = message
	_set_buttons_enabled(true)


func _set_buttons_enabled(enabled: bool) -> void:
	for b in buttons:
		b.disabled = not enabled


## Atalhos para testar sem clicar: --host, --join=IP ou --solo depois de "--".
## Ex.: godot -- --host    |    godot -- --join=127.0.0.1
func _parse_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--arena":
			_use_arena = true
		if arg == "--new":
			SaveGame.load_world = false
			SaveGame.load_character = false
		if arg.begins_with("--background="):
			Network.background = arg.get_slice("=", 1)
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host.call_deferred()
		elif arg == "--solo":
			_on_solo.call_deferred()
		elif arg.begins_with("--join"):
			address_edit.text = arg.get_slice("=", 1) if "=" in arg else "127.0.0.1"
			_on_join.call_deferred()
