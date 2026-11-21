class_name PartyFrames
extends VBoxContainer
## Barra da party (etapa 9), na lateral esquerda: um quadro por jogador do grupo, com o
## nome, o nível e as barras de vida, stamina e mana (os dos outros chegam pela rede:
## Health e Player.net_pools). O aliado selecionado como alvo fica com borda verde.
## Clicar no quadro de um aliado abre: Selecionar (alvo), Trocar itens e Seguir.

const FRAME_SIZE := Vector2(170, 52)

var player: Player
var _frames := {}  # Player → Control
var _menu: PopupMenu
var _menu_target: Player
var _timer := 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT, Control.PRESET_MODE_MINSIZE, 12)
	position.y -= 120
	_menu = PopupMenu.new()
	_menu.add_item(tr("Selecionar (alvo)"), 0)
	_menu.add_item(tr("Trocar itens"), 1)
	_menu.add_item(tr("Seguir"), 2)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func _process(delta: float) -> void:
	_timer -= delta
	if player == null or _timer > 0.0:
		return
	_timer = 0.2
	var players: Array = get_tree().get_nodes_in_group("player").filter(func(p: Node) -> bool: return p is Player)
	players.sort_custom(func(a: Player, b: Player) -> bool: return (a == player) or (b != player and str(a.name) < str(b.name)))
	# Sozinho: não mostra (a vida e a mana já estão nas esferas).
	visible = players.size() > 1
	for p: Player in _frames.keys():
		if not is_instance_valid(p) or not p in players:
			_frames[p].queue_free()
			_frames.erase(p)
	for p: Player in players:
		if not _frames.has(p):
			_frames[p] = _make_frame(p)
			add_child(_frames[p])
		_frames[p].queue_redraw()


func _make_frame(p: Player) -> Control:
	var frame := PartyFrame.new()
	frame.bars = self
	frame.who = p
	frame.custom_minimum_size = FRAME_SIZE
	frame.tooltip_text = tr("Clique: selecionar, trocar itens ou seguir") if p != player else ""
	return frame


func frame_clicked(p: Player) -> void:
	if p == player:
		return
	_menu_target = p
	_menu.set_item_text(0, tr("Tirar seleção") if player.ally_target == p else tr("Selecionar (alvo)"))
	_menu.set_item_text(2, tr("Parar de seguir") if player.follow_target == p else tr("Seguir"))
	_menu.position = Vector2i(get_global_mouse_position())
	_menu.popup()


func _on_menu(id: int) -> void:
	var p := _menu_target
	if not is_instance_valid(p):
		return
	match id:
		0: player.set_ally_target(null if player.ally_target == p else p)
		1: player.trade.invite(p)
		2:
			if player.follow_target == p:
				player.stop_follow()
			else:
				player.start_follow(p)


class PartyFrame extends Control:
	var bars: PartyFrames
	var who: Player

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			bars.frame_clicked(who)
			accept_event()

	func _draw() -> void:
		if not is_instance_valid(who):
			return
		var me := bars.player
		var font := get_theme_default_font()
		var selected := me and me.ally_target == who
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.06, 0.06, 0.07, 0.8))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 1.0, 0.45) if selected else Color(0.3, 0.3, 0.3), false, 2.0 if selected else 1.0)
		var lvl := int(me.progression.char_level) if who == me else int(who.net_pools.z)
		var title := "%s  ·  Nv %d" % [who.display_name(), lvl]
		if me and me.follow_target == who:
			title += "  " + tr("(seguindo)")
		draw_string(font, Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 10, 12, Color.WHITE if not who.health.is_dead else Color(0.6, 0.6, 0.6))
		var hp := clampf(who.health.current / maxf(who.health.max_health, 1.0), 0.0, 1.0)
		var pools := who.net_pools
		if who == me:
			pools = Vector3(me.stamina.current / maxf(me.stamina.max_value, 1.0), me.mana.current / maxf(me.mana.max_value, 1.0), lvl)
		_bar(20, 12, hp, Color(0.8, 0.15, 0.12))
		_bar(34, 6, pools.x, Color(0.85, 0.75, 0.2))
		_bar(42, 6, pools.y, Color(0.25, 0.45, 0.95))

	func _bar(y: float, h: float, frac: float, color: Color) -> void:
		draw_rect(Rect2(6, y, size.x - 12, h), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(6, y, (size.x - 12) * clampf(frac, 0.0, 1.0), h), color)
