class_name FocusWeapon
extends Weapon
## Cajado (foco arcano): conjura a última habilidade (a do Q).
## Toque = conjuração normal. Segurar = canalizar: gasta mana enquanto segura, até
## MAX_COST vezes o custo da habilidade, e aumenta o efeito (dano, cura, alcance,
## raio) até MAX_POWER vezes. Soltar conjura. Sem mana, solta sozinho.

const TAP := 0.2
const FULL := 2.0
const MAX_COST := 6.0
const MAX_POWER := 3.0

var _pressing := false
var _time := 0.0
var _caster: SpellCaster
var _orb: MeshInstance3D


func handle_attack(held: bool, just_pressed: bool) -> void:
	if just_pressed and not _pressing:
		if is_broken():
			warn_broken()
			return
		_caster = user.weapons.caster_for(user.progression.last_spell)
		if _caster == null or user.progression.spell_level(user.progression.last_spell) <= 0:
			user.notify("Nenhuma habilidade aprendida (leia um grimório)")
			return
		if _caster.casting or _caster.cooldown > 0.0:
			return
		_pressing = true
		_time = 0.0
	if not _pressing:
		return
	if held:
		var dt := get_process_delta_time()
		_time += dt
		if _time > TAP and _time < FULL:
			# Canalizando: o custo extra (MAX_COST - 1 vezes) se espalha até FULL segundos.
			var extra := _caster.stat("mana", 15.0) * (MAX_COST - 1.0) / (FULL - TAP) * dt
			var mana: StatPool = user.get(&"mana")
			if mana and not mana.spend(extra):
				_release()
				return
		hud_changed.emit()
	else:
		_release()


func _release() -> void:
	var frac := channel_fraction()  # antes de soltar (depois vira -1)
	_pressing = false
	var power := 1.0 + (MAX_POWER - 1.0) * maxf(frac, 0.0) * user.progression.mult("magic.channel")
	_time = 0.0
	hud_changed.emit()
	if await _caster.cast(power):
		wear(1.0)


## 0 a 1 enquanto canaliza; -1 parado.
func channel_fraction() -> float:
	if not _pressing or _time <= TAP:
		return -1.0
	return clampf((_time - TAP) / (FULL - TAP), 0.0, 1.0)


func channel_label() -> String:
	return "Canalizando %s" % GameData.get_item(user.progression.last_spell).get("name", "")


func on_unequip() -> void:
	_pressing = false
	_time = 0.0


func hud_text() -> String:
	var spell := user.progression.last_spell
	return "clique: %s (Nv %d) · segure para canalizar" % [GameData.get_item(spell).get("name", "—"), user.progression.spell_level(spell)]


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
