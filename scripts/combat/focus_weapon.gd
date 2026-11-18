class_name FocusWeapon
extends Weapon
## Cajado (foco arcano): conjura a última habilidade (a do Q).
## Toque = conjuração normal. Segurar = canalizar: paga o custo base ao começar e, em
## FULL - TAP segundos, queima TODA a mana que sobrou na barra (a barra chega a zero;
## a regeneração reduzida que entra enquanto segura também é queimada). Quanto mais mana
## queimada, mais forte o efeito (dano, cura, alcance, raio): REF_COST vezes o custo da
## habilidade já dá o máximo, MAX_POWER vezes. Soltar conjura.

const TAP := 0.2
const FULL := 2.0
## Mana extra (em vezes o custo base) que dá a potência máxima.
const REF_COST := 5.0
const MAX_POWER := 3.0

var _pressing := false
var _time := 0.0
## Progresso da canalização (0 a 1, pelo tempo).
var _charge := 0.0
var _caster: SpellCaster
## Custo base já pago no começo da canalização (0 = ainda não pagou).
var _prepaid := 0.0
## Mana extra queimada nesta canalização e o ritmo (mana por segundo).
var _burned := 0.0
var _burn_rate := 0.0
var _orb: MeshInstance3D


func handle_attack(held: bool, just_pressed: bool) -> void:
	if just_pressed and not _pressing:
		if is_broken():
			warn_broken()
			return
		_caster = user.weapons.caster_for(user.progression.last_spell)
		if _caster == null or user.progression.spell_level(user.progression.last_spell) <= 0:
			user.notify(tr("Nenhuma habilidade aprendida (leia um grimório)"))
			return
		if _caster.casting or _caster.cooldown > 0.0:
			return
		var pool: StatPool = user.get(&"mana")
		if pool and not pool.has(_caster.stat("mana", 15.0)):
			user.notify(tr("Mana insuficiente"))
			return
		_pressing = true
		_time = 0.0
		_charge = 0.0
		_prepaid = 0.0
		_burned = 0.0
	if not _pressing:
		return
	if held:
		var dt := get_process_delta_time()
		_time += dt
		var mana: StatPool = user.get(&"mana")
		if _time > TAP and _prepaid <= 0.0:
			# Começou a canalizar: paga o custo base agora (a conjuração não cobra de novo)
			# e decide o ritmo para queimar o resto da barra até o fim da carga.
			var base := _caster.stat("mana", 15.0)
			if mana and not mana.spend(base):
				_pressing = false
				_time = 0.0
				user.notify(tr("Mana insuficiente"))
				hud_changed.emit()
				return
			_prepaid = base
			_burn_rate = (mana.current if mana else 0.0) / (FULL - TAP)
			_set_channeling(true)
		if _time > TAP and mana:
			# Até a carga completar, queima no ritmo; depois, queima o que a regeneração devolver.
			var want := _burn_rate * dt if _charge < 1.0 else mana.current
			_burn(mana, minf(maxf(want, 0.0), mana.current))
		if _time > TAP:
			_charge = minf(_charge + dt / (FULL - TAP), 1.0)
		hud_changed.emit()
	else:
		_release()


func _burn(mana: StatPool, amount: float) -> void:
	if amount > 0.0:
		mana.drain(amount)
		_burned += amount


func _set_channeling(on: bool) -> void:
	var mana: StatPool = user.get(&"mana") if user else null
	if mana:
		mana.channeling = on


## Potência pela mana queimada (REF_COST vezes o custo base = máximo).
func _power() -> float:
	if _prepaid <= 0.0:
		return 1.0
	var frac := clampf(_burned / (_prepaid * REF_COST), 0.0, 1.0)
	return 1.0 + (MAX_POWER - 1.0) * frac * user.progression.mult("magic.channel")


func _release() -> void:
	var mana: StatPool = user.get(&"mana")
	if _prepaid > 0.0 and mana:
		_burn(mana, mana.current)  # o restinho que sobrou também vai
	_pressing = false
	_set_channeling(false)
	var power := _power()
	var prepaid := _prepaid > 0.0
	_prepaid = 0.0
	_burned = 0.0
	_time = 0.0
	hud_changed.emit()
	if await _caster.cast(power, prepaid):
		wear(1.0)


## 0 a 1 enquanto canaliza; -1 parado.
func channel_fraction() -> float:
	if not _pressing or _time <= TAP:
		return -1.0
	return clampf(_charge, 0.0, 1.0)


func channel_label() -> String:
	return tr("Canalizando %s") % GameData.get_item(user.progression.last_spell).get("name", "")


func on_unequip() -> void:
	# Trocou de arma no meio da canalização: devolve a mana já paga e queimada.
	if _prepaid > 0.0 and user:
		var mana: StatPool = user.get(&"mana")
		if mana:
			mana.restore(_prepaid + _burned)
	_prepaid = 0.0
	_burned = 0.0
	_pressing = false
	_time = 0.0
	_charge = 0.0
	_set_channeling(false)


func hud_text() -> String:
	var spell := user.progression.last_spell
	return tr("clique: %s (Nv %d) · segure para canalizar") % [GameData.get_item(spell).get("name", "—"), user.progression.spell_level(spell)]


func _process(delta: float) -> void:
	super(delta)
	if _orb:
		var f := maxf(channel_fraction(), 0.0)
		_orb.scale = Vector3.ONE * (1.0 + f * 1.5)
		var mat := _orb.get_active_material(0) as StandardMaterial3D
		if mat:
			mat.albedo_color = SpellIcon.school_color(user.progression.last_spell)
			mat.emission = mat.albedo_color


func _build_viewmodel() -> void:
	var stick := Weapon.box(Vector3(0.03, 0.75, 0.03), Color(0.42, 0.29, 0.17), Vector3(0, 0.05, 0))
	stick.rotation.x = -0.35
	add_child(stick)
	_orb = Weapon.sphere(0.05, Color(0.9, 0.6, 1.0), Vector3(0, 0.42, -0.14), true)
	add_child(_orb)
