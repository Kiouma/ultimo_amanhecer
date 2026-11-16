class_name Weapon
extends Node3D
## Base de todas as armas (tiro, melee, magia). Cada arma lê seus números de um
## registro em data/ (equipment.json ou spells.json) e fica presa na câmera como
## "viewmodel" da 1ª pessoa.

## Emitido quando algo que o HUD mostra mudou (munição, recarga, etc.).
signal hud_changed

## Converte o "noise" dos JSON (0 a 1) em metros de alcance do som.
const NOISE_TO_METERS := 50.0
## Camadas que um ataque pode acertar: mundo, zumbis, construções.
const HIT_MASK := 1 | 4 | 8

var data: Dictionary = {}
var user: Player
var camera: Camera3D
var head: Node3D
var cooldown := 0.0
## Slot do inventário de onde a arma foi equipada (guarda estado como balas no pente).
var slot: Dictionary = {}

var _last_broken_warning := -10000

var _rest_position := Vector3.ZERO
var _rest_rotation := Vector3.ZERO


func setup(entry: Dictionary, owner_player: Player, cam: Camera3D, head_node: Node3D) -> void:
	data = entry
	user = owner_player
	camera = cam
	head = head_node
	_build_viewmodel()
	_rest_position = position
	_rest_rotation = rotation


func _process(delta: float) -> void:
	cooldown = maxf(cooldown - delta, 0.0)


## Arma do slot sem durabilidade (ex.: 0 de 250)? Não funciona até ser reparada.
func is_broken() -> bool:
	return float(data.get("durability", 0.0)) > 0.0 and Inventory.is_broken(slot)


## Desgasta a arma (só itens com "durability"). Avisa quando quebra.
func wear(amount := 1.0) -> void:
	if float(data.get("durability", 0.0)) <= 0.0 or slot.is_empty() or user == null:
		return
	if user.inventory.wear(slot, amount) <= 0.0:
		user.notify("%s quebrou: repare na bancada" % display_name())


## Tentou usar quebrada: avisa (no máximo a cada 2 s).
func warn_broken() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_broken_warning > 2000:
		_last_broken_warning = now
		user.notify("%s está quebrado(a): repare na bancada" % display_name())


func display_name() -> String:
	return str(data.get("name", data.get("id", "?")))


## Chamado todo frame enquanto a arma está equipada. just_pressed = clicou agora.
func handle_attack(_held: bool, _just_pressed: bool) -> void:
	pass


func reload() -> void:
	pass


## Texto extra do HUD (ex.: "12 / 48").
func hud_text() -> String:
	return ""


func on_equip() -> void:
	position = _rest_position
	rotation = _rest_rotation


func on_unequip() -> void:
	pass


## Número do JSON, já com qualidade e refino do item na mão: dano maior (qualidade
## e refino) e custo de stamina menor (qualidade).
func stat(key: String, default: float) -> float:
	var value := float(data.get(key, default))
	if key == "damage":
		value *= power_multiplier()
	elif key == "stamina_cost":
		value /= quality_multiplier()
	# Proficiências e habilidades: "melee.damage", "ranged.draw_time", "magic.mana"...
	var prog := user.progression if user else null
	if prog:
		value = prog.apply(category() + "." + key, value)
		if key == "damage":
			value *= prog.mastery_mult(weapon_type())
	return value


## "bow", "firearm", "melee", "spell" (maestria).
func weapon_type() -> String:
	return str(data.get("type", "melee"))


## Grupo dos modificadores: "ranged" (arco e arma de fogo), "melee" ou "magic".
func category() -> String:
	match weapon_type():
		"bow", "firearm": return "ranged"
		"spell": return "magic"
	return "melee"


## Usou a arma (disparo, golpe, feitiço): maestria e um pouco de XP.
func count_use() -> void:
	if user and user.progression:
		user.progression.use_weapon(weapon_type())
		user.progression.gain({"ranged": "firearms", "melee": "melee", "magic": "magic"}[category()], 0.3)


func quality_multiplier() -> float:
	return Inventory.quality_multiplier(slot) if not slot.is_empty() and data.has("durability") else 1.0


## Qualidade × refino: vale para dano e eficiência de coleta.
func power_multiplier() -> float:
	if slot.is_empty() or not data.has("durability"):
		return 1.0
	return Inventory.quality_multiplier(slot) * Inventory.refine_multiplier(slot)


# --- Utilitários para as armas ---------------------------------------------------

func make_noise(factor: float) -> void:
	var stealth := user.progression.mult("noise") if user.progression else 1.0
	Network.emit_noise(user.global_position, factor * NOISE_TO_METERS * stealth, user)


## Raio a partir do centro da tela (mira). Ignora o próprio jogador.
func aim_ray(max_range: float, spread_deg := 0.0) -> Dictionary:
	var origin := camera.global_position
	var dir := -camera.global_basis.z
	if spread_deg > 0.0:
		var s := deg_to_rad(spread_deg)
		dir = dir.rotated(camera.global_basis.x, randf_range(-s, s))
		dir = dir.rotated(camera.global_basis.y, randf_range(-s, s))
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, HIT_MASK)
	query.exclude = [user.get_rid()]
	var hit := user.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		hit = {"position": origin + dir * max_range, "miss": true}
	return hit


## Aplica dano em quem tiver o componente Health. Retorna true se acertou algo vivo.
## Num cliente, o dano vira um pedido ao servidor (ver Health).
func deal_damage(target: Object, amount: float) -> bool:
	if not target is Node:
		return false
	var health := Health.find_in(target)
	if health == null or health.is_dead:
		return false
	amount = Progression.on_hit(user, target, amount, weapon_type())
	health.take_damage(amount * user.death_penalty.damage_factor(), user)
	return true


## Animação de ação do personagem (vista na 3ª pessoa e pelos outros jogadores).
func play_body_anim(anim_name: StringName) -> void:
	if user.has_method(&"play_action_synced"):
		user.play_action_synced(anim_name)


## Pequeno "coice" visual do viewmodel.
func kick(offset: Vector3, rot: Vector3, duration := 0.12) -> void:
	var tw := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "position", _rest_position + offset, duration * 0.3)
	tw.parallel().tween_property(self, "rotation", _rest_rotation + rot, duration * 0.3)
	tw.tween_property(self, "position", _rest_position, duration * 0.7)
	tw.parallel().tween_property(self, "rotation", _rest_rotation, duration * 0.7)


## Rastro de bala de from até to (some rápido). Estático para os outros jogadores usarem também.
static func spawn_tracer(context: Node, from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var tracer := box(Vector3(0.008, 0.008, length), Color(1.0, 0.9, 0.6), Vector3.ZERO, true)
	context.get_tree().current_scene.add_child(tracer)
	tracer.global_position = (from + to) * 0.5
	tracer.look_at(to)
	var tw := tracer.create_tween()
	tw.tween_property(tracer, "transparency", 1.0, 0.06)
	tw.tween_callback(tracer.queue_free)


## Os modelos de verdade ainda não existem: cada arma monta formas simples.
func _build_viewmodel() -> void:
	pass


static func box(size: Vector3, color: Color, pos := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh_node(mesh, color, pos, emissive)


static func cylinder(radius: float, height: float, color: Color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return _mesh_node(mesh, color, pos, false)


static func sphere(radius: float, color: Color, pos := Vector3.ZERO, emissive := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	return _mesh_node(mesh, color, pos, emissive)


static func _mesh_node(mesh: PrimitiveMesh, color: Color, pos: Vector3, emissive: bool) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if emissive:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node
