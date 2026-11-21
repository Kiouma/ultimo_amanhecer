class_name FocusWeapon
extends Weapon
## Cajado (foco arcano): o ataque básico dispara um projétil arcano no alvo (sem custo
## de mana), com o dano do cajado × dano mágico. As magias de verdade são habilidades
## (teclas 1 a 5, nó Skills).

const PROJECTILE := preload("res://scripts/combat/projectile.gd")
const COLOR := Color(0.75, 0.5, 1.0)


func handle_attack(held: bool, _just_pressed: bool) -> void:
	if not held or cooldown > 0.0:
		return
	if is_broken():
		warn_broken()
		return
	cooldown = stat("attack_time", 0.6)
	var aim_point: Vector3 = aim_ray(stat("range", 60.0)).position
	var from: Vector3 = user.shot_origin(aim_point)
	play_body_anim(&"Spell_Simple_Shoot", cooldown, true)
	var bolt: Area3D = PROJECTILE.new()
	bolt.damage = stat("damage", 14.0) * user.death_penalty.damage_factor()
	bolt.speed = stat("speed", 26.0)
	bolt.caster = user
	bolt.color = COLOR
	bolt.max_lifetime = stat("range", 60.0) / bolt.speed
	get_tree().current_scene.add_child(bolt)
	bolt.global_position = from
	bolt.direction = (aim_point - from).normalized()
	user.broadcast_fx(&"bolt", from, aim_point, COLOR)
	make_noise(stat("noise", 0.2))
	Sfx.play("spell", user.global_position + Vector3.UP * 1.4, -8.0)
	count_use()
	wear(0.5)


func hud_text() -> String:
	return tr("projétil arcano")
