class_name Skills
extends Node
## Habilidades do personagem (nó "Skills" do Player, etapa 6). Dados em data/skills.
## - Cada classe tem 6 habilidades ("class", "unlock" = nível do personagem em que abre).
##   A básica (nível 1) já vem aprendida; as outras se desbloqueiam com ouro.
## - Habilidades únicas ("book": true) só se aprendem lendo o "Livro de habilidade",
##   que cai de chefes. Servem para qualquer classe.
## - Evoluir do nível 1 ao 20 custa ouro; os níveis 5, 10, 15 e 20 pedem também
##   Essência de chefe e dão um efeito extra ("milestones").
## - Barra de 5 slots (teclas 1 a 5). Habilidades de área mostram um círculo no chão:
##   a tecla começa a mirar e o clique esquerdo (ou a mesma tecla) solta; Esc cancela.
## Roda na máquina do dono do personagem (o dano passa pelo servidor, como as armas).

signal changed

const BAR_SIZE := 5
const MAX_LEVEL := 20
const MILESTONES := [5, 10, 15, 20]
const ESSENCE := "boss_essence"

## id → nível (1 a MAX_LEVEL).
var learned := {}
## Habilidade em cada slot da barra ("" = vazio).
var bar: Array = ["", "", "", "", ""]

var _player: Player
var _casters := {}
## Habilidade de área esperando o clique (círculo no chão).
var _aiming := ""
var _aim_ring: MeshInstance3D
## Habilidade canalizada (segurar a tecla) e o slot dela.
var _channel := ""
var _channel_slot := -1


func _ready() -> void:
	_player = get_parent() as Player


static func data(id: String) -> Dictionary:
	return GameData.get_entry("skills", id)


# --- Consulta -----------------------------------------------------------------------------

## Habilidades da classe do personagem, pela ordem de desbloqueio.
func class_skills() -> Array:
	var out: Array = []
	var cls := _player.progression.char_class if _player else ""
	for id: String in GameData.get_all("skills"):
		if str(data(id).get("class", "")) == cls and cls != "":
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return int(data(a).get("unlock", 1)) < int(data(b).get("unlock", 1)))
	return out


## Habilidades únicas (livros) já aprendidas.
func book_skills() -> Array:
	var out: Array = []
	for id: String in learned:
		if bool(data(id).get("book", false)):
			out.append(id)
	return out


func level_of(id: String) -> int:
	return int(learned.get(id, 0))


## Ouro para desbloquear (100 × nível de desbloqueio).
static func unlock_cost(id: String) -> int:
	return 100 * maxi(int(data(id).get("unlock", 1)), 1)


## Ouro para evoluir até `next_level` (40 × nível²).
static func level_cost(next_level: int) -> int:
	return 40 * next_level * next_level


## Essência de chefe para evoluir até `next_level` (1, 2, 3 e 4 nos marcos).
static func essence_cost(next_level: int) -> int:
	return next_level / 5 if next_level in MILESTONES else 0


## Por que não dá para desbloquear ("" = dá).
func unlock_block_reason(id: String) -> String:
	var d := data(id)
	if d.is_empty() or level_of(id) > 0:
		return tr("Já aprendida")
	if bool(d.get("book", false)):
		return tr("Só com o livro de habilidade (cai de chefes)")
	if str(d.get("class", "")) != _player.progression.char_class:
		return tr("Habilidade de outra classe")
	if _player.progression.char_level < int(d.get("unlock", 1)):
		return tr("Abre no nível %d") % int(d.get("unlock", 1))
	if _player.inventory.gold < unlock_cost(id):
		return tr("Falta ouro (%d)") % unlock_cost(id)
	return ""


func unlock(id: String) -> bool:
	if unlock_block_reason(id) != "":
		return false
	_player.inventory.add_gold(-unlock_cost(id))
	_learn(id)
	_player.notify(tr("Aprendeu %s") % str(data(id).get("name", id)))
	return true


## Por que não dá para evoluir ("" = dá).
func level_block_reason(id: String) -> String:
	var level := level_of(id)
	if level <= 0:
		return tr("Ainda não aprendida")
	if level >= MAX_LEVEL:
		return tr("Nível máximo")
	var next := level + 1
	if _player.inventory.gold < level_cost(next):
		return tr("Falta ouro (%d)") % level_cost(next)
	var essence := essence_cost(next)
	if essence > 0 and _player.inventory.count_of(ESSENCE) < essence:
		return tr("Falta Essência de chefe (%d)") % essence
	return ""


func level_up(id: String) -> bool:
	if level_block_reason(id) != "":
		return false
	var next := level_of(id) + 1
	_player.inventory.add_gold(-level_cost(next))
	if essence_cost(next) > 0:
		_player.inventory.remove_item(ESSENCE, essence_cost(next))
	learned[id] = next
	var extra := str(data(id).get("milestone_text", {}).get(str(next), ""))
	_player.notify(tr("%s nível %d") % [str(data(id).get("name", id)), next] + ((" · " + extra) if extra != "" else ""))
	changed.emit()
	return true


## Livro de habilidade: aprende a habilidade única (ou sobe 1 nível, se já sabe).
func read_book(item: Dictionary) -> bool:
	var id := str(item.get("teaches", ""))
	if data(id).is_empty():
		return false
	if level_of(id) >= MAX_LEVEL:
		_player.notify(tr("Você já domina %s") % str(data(id).get("name", id)))
		return false
	if level_of(id) > 0:
		learned[id] = level_of(id) + 1
		_player.notify(tr("%s subiu para o nível %d") % [str(data(id).get("name", id)), level_of(id)])
		changed.emit()
	else:
		_learn(id)
		_player.notify(tr("Aprendeu %s (veja em Habilidades, K)") % str(data(id).get("name", id)))
	_player.progression.gain("magic", 10.0)
	return true


func _learn(id: String) -> void:
	learned[id] = 1
	if not id in bar:
		var free := bar.find("")
		if free >= 0:
			bar[free] = id
	changed.emit()


## Põe a habilidade no slot (troca de lugar se ela já estava em outro).
func assign(id: String, slot: int) -> void:
	if slot < 0 or slot >= BAR_SIZE or (id != "" and level_of(id) <= 0):
		return
	var old := bar.find(id) if id != "" else -1
	if old >= 0:
		bar[old] = bar[slot]
	bar[slot] = id
	changed.emit()


## Personagem sem a habilidade básica da classe (novo ou de versão antiga): ganha agora.
func ensure_basic() -> void:
	for id: String in class_skills():
		if int(data(id).get("unlock", 1)) <= 1 and level_of(id) <= 0:
			_learn(id)


# --- Uso ------------------------------------------------------------------------------------

## Objeto que executa a habilidade (criado uma vez, invisível, guarda a recarga).
func caster(id: String) -> SkillCaster:
	if _casters.has(id):
		return _casters[id]
	var d := data(id)
	if d.is_empty():
		return null
	var c := SkillCaster.new()
	c.skills = self
	_player.weapons.add_child(c)
	c.setup(d, _player, _player.camera, _player.head)
	c.visible = false
	_casters[id] = c
	return c


## Tecla 1 a 5 (ou clique no slot da barra).
func use_slot(slot: int) -> void:
	if slot < 0 or slot >= BAR_SIZE or not _can_act():
		return
	var id := str(bar[slot])
	if id == "":
		return
	var c := caster(id)
	if c == null:
		return
	if _aiming != "":
		if _aiming == id:
			_confirm_aim()
			return
		_cancel_aim()
	var block := c.block_reason()
	if block != "":
		_player.notify(block)
		return
	match str(data(id).get("kind", "")):
		"ground":
			_aiming = id
		"channel":
			_channel = id
			_channel_slot = slot
			c.start_channel()
		_:
			c.cast()


func is_aiming() -> bool:
	return _aiming != ""


## Habilidade canalizada (Redemoinho) em andamento.
func is_channeling() -> bool:
	return _channel != ""


func _confirm_aim() -> void:
	var id := _aiming
	_cancel_aim()
	_player.weapons.suppress_until = Time.get_ticks_msec() + 400
	var c := caster(id)
	if c:
		c.cast(ground_point(c.stat("range", 20.0)))


func _cancel_aim() -> void:
	_aiming = ""
	if _aim_ring:
		_aim_ring.visible = false


## Ponto no chão sob o cursor, até `max_range` do personagem.
func ground_point(max_range: float) -> Vector3:
	var hit: Dictionary = _player.cursor_ray(max_range + 30.0, 1 | 8)
	var p: Vector3 = hit.position
	var flat := Vector3(p.x - _player.global_position.x, 0.0, p.z - _player.global_position.z)
	if flat.length() > max_range:
		flat = flat.normalized() * max_range
		p = _player.global_position + flat
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 20.0, p + Vector3.DOWN * 40.0, 1 | 8)
		var down := _player.get_world_3d().direct_space_state.intersect_ray(q)
		p = down.position if not down.is_empty() else p
	return p


func _unhandled_input(event: InputEvent) -> void:
	if _player == null or not _player.is_local():
		return
	for i in BAR_SIZE:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			use_slot(i)
			get_viewport().set_input_as_handled()
			return
	if _aiming != "":
		if event.is_action_pressed("attack"):
			_confirm_aim()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("pause"):
			_cancel_aim()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _player == null or not _player.is_local():
		return
	if _aiming != "" and not _can_act():
		_cancel_aim()
	if _aiming != "":
		_update_ring()
	if _channel != "":
		var c := caster(_channel)
		var held := _channel_slot >= 0 and Input.is_action_pressed("hotbar_%d" % (_channel_slot + 1)) and _can_act()
		if not held or not c.channel_tick():
			c.stop_channel()
			_channel = ""
			_channel_slot = -1


func _can_act() -> bool:
	return _player.is_local() and MouseMode.playing() and not _player.health.is_dead \
		and not (_player.build and _player.build.active)


func _update_ring() -> void:
	var c := caster(_aiming)
	if c == null:
		return
	if _aim_ring == null:
		_aim_ring = MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.94
		torus.outer_radius = 1.0
		torus.rings = 48
		torus.ring_segments = 4
		_aim_ring.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1.0, 0.85, 0.4, 0.8)
		_aim_ring.material_override = mat
		_aim_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_aim_ring.top_level = true
		add_child(_aim_ring)
	var r := c.stat("radius", 3.0)
	_aim_ring.visible = true
	_aim_ring.global_transform = Transform3D(Basis().scaled(Vector3(r, 1.0, r)), ground_point(c.stat("range", 20.0)) + Vector3.UP * 0.08)
	(_aim_ring.material_override as StandardMaterial3D).albedo_color = c.color()


# --- Salvar ---------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"learned": learned.duplicate(), "bar": bar.duplicate()}


func from_save(d: Dictionary) -> void:
	learned.clear()
	for id: String in d.get("learned", {}):
		if not data(id).is_empty():
			learned[id] = clampi(int(d.learned[id]), 1, MAX_LEVEL)
	var saved: Array = d.get("bar", [])
	for i in BAR_SIZE:
		var id := str(saved[i]) if i < saved.size() else ""
		bar[i] = id if level_of(id) > 0 else ""
	changed.emit()
