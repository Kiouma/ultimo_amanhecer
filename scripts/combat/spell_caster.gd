class_name SpellCaster
extends Weapon
## Feitiço equipado na mão (GDD 5.4). Gasta mana, tem tempo de conjuração e recarga.
## Por enquanto só feitiços de projétil (dardo de fogo); os outros vêm na Fase 6.

const PROJECTILE := preload("res://scripts/combat/projectile.gd")

var casting := false

var _orb: MeshInstance3D
var _light: OmniLight3D
var _time := 0.0


func _process(delta: float) -> void:
	super(delta)
	_time += delta
	if _orb:
		var pulse := 1.0 + sin(_time * 6.0) * 0.08 + (0.4 if casting else 0.0)
		_orb.scale = Vector3.ONE * pulse
		_light.light_energy = 1.2 * pulse


func handle_attack(_held: bool, just_pressed: bool) -> void:
	if just_pressed:
		cast()


## Também usado pelo atalho Q (feitiço rápido), mesmo com outra arma na mão.
func cast() -> bool:
	if casting or cooldown > 0.0:
		return false
	var mana: StatPool = user.get(&"mana")
	if mana and not mana.spend(stat("mana", 15.0)):
		return false
	casting = true
	cooldown = stat("cooldown", 1.0) + stat("cast_time", 0.4)
	play_body_anim(&"Spell_Simple_Shoot")
	hud_changed.emit()
	await get_tree().create_timer(stat("cast_time", 0.4)).timeout
	casting = false
	if not is_instance_valid(user):
		return false
	_launch()
	hud_changed.emit()
	return true


func _launch() -> void:
	var from := head.global_position + (-head.global_basis.z) * 0.7 + head.global_basis.x * 0.15
	var aim_point: Vector3 = aim_ray(stat("range", 80.0)).position
	var bolt: Area3D = PROJECTILE.new()
	bolt.damage = stat("damage", 30.0)
	bolt.speed = stat("speed", 22.0)
	bolt.caster = user
	bolt.color = _school_color()
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = from
	bolt.direction = (aim_point - from).normalized()
	user.broadcast_fx(&"bolt", from, aim_point, bolt.color)
	make_noise(stat("noise", 0.6))
	kick(Vector3(0, 0, 0.08), Vector3(0.3, 0, 0), 0.2)


func hud_text() -> String:
	var cost := int(stat("mana", 15.0))
	if casting:
		return "conjurando..."
	if cooldown > 0.0:
		return "recarga %.1fs · %d mana" % [cooldown, cost]
	return "%d mana" % cost


func _school_color() -> Color:
	match str(data.get("school", "")):
		"fire": return Color(1.0, 0.45, 0.1)
		"ice": return Color(0.5, 0.8, 1.0)
		"lightning": return Color(0.8, 0.8, 1.0)
		"life": return Color(0.4, 1.0, 0.5)
		_: return Color(0.9, 0.6, 1.0)


func _build_viewmodel() -> void:
	var color := _school_color()
	_orb = sphere(0.035, color, Vector3.ZERO, true)
	add_child(_orb)
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = 3.0
	_light.light_energy = 1.2
	add_child(_light)
