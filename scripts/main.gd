extends Node
## Cena inicial: menu (solo / hospedar / entrar) e o contêiner do nível.
## O nível é criado pelo servidor dentro de "Level"; o LevelSpawner replica para os
## clientes, que recebem depois os jogadores e zumbis (ordem garantida pela replicação).

const LEVEL := preload("res://scenes/levels/test_arena.tscn")

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
	_parse_command_line()


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
	level_root.add_child(LEVEL.instantiate(), true)


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
		if arg == "--host":
			_on_host.call_deferred()
		elif arg == "--solo":
			_on_solo.call_deferred()
		elif arg.begins_with("--join"):
			address_edit.text = arg.get_slice("=", 1) if "=" in arg else "127.0.0.1"
			_on_join.call_deferred()
