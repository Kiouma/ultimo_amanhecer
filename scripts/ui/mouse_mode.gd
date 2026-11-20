class_name MouseMode
extends RefCounted
## Quem decide o modo do mouse (docs/PROXIMOS_PASSOS.md, seção 7).
## - Mouse travado (padrão): girar o mouse gira a câmera.
## - Mouse livre (Alt esquerdo alterna): o cursor aparece; a câmera só gira segurando o
##   botão direito; dá para clicar na HUD (hotbar, botões do minimapa...). A mira continua
##   no centro da tela.
## - Com uma tela cheia aberta (inventário, mapa, pausa...), o cursor aparece sempre.
## As telas se registram (register) e, ao abrir/fechar, chamam refresh() em vez de mexer
## em Input.mouse_mode direto.

## Modo livre ligado pelo jogador (Alt esquerdo).
static var free := false
## Segurando o botão direito no modo livre: o mouse trava enquanto gira a câmera.
static var rotating := false

static var _screens: Array[WeakRef] = []
static var _cursor_before_rotate := Vector2.ZERO


static func register(screen: Control) -> void:
	_screens.append(weakref(screen))


## Alguma tela cheia está aberta.
static func any_open() -> bool:
	for ref: WeakRef in _screens:
		var s := ref.get_ref() as Control
		if s and s.is_inside_tree() and s.visible:
			return true
	return false


## O jogador está no jogo (nenhuma tela cheia aberta): movimento, ataques, teclas.
static func playing() -> bool:
	return not any_open()


## Aplica o modo certo para o momento.
static func refresh() -> void:
	_screens = _screens.filter(func(ref: WeakRef) -> bool: return ref.get_ref() != null)
	if any_open():
		rotating = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif free and not rotating:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func toggle_free() -> void:
	free = not free
	rotating = false
	refresh()


## Modo livre: começa/termina de girar a câmera com o botão direito. O cursor volta para
## onde estava ao soltar.
static func set_rotating(on: bool, viewport: Viewport) -> void:
	if not free or any_open() or on == rotating:
		return
	if on:
		_cursor_before_rotate = viewport.get_mouse_position()
	rotating = on
	refresh()
	if not on:
		viewport.warp_mouse(_cursor_before_rotate)


## A câmera segue o mouse agora (travado, ou girando no modo livre).
static func looking() -> bool:
	return playing() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED


## Clique no mundo vale como ataque: no modo livre, não pode estar em cima de um
## controle clicável da HUD.
static func can_attack(viewport: Viewport) -> bool:
	if not playing():
		return false
	if not free or rotating:
		return true
	return viewport.gui_get_hovered_control() == null
