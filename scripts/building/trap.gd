class_name Trap
extends StaticBody3D
## Armadilha colocada no chão (GDD 9.2): espetos, mandíbula...
## Dados no item ("type": "trap", campo "trap"): dano, intervalo por zumbi, lentidão
## (slow = fator de velocidade; 0 = prende) e por quanto tempo.
## Cada acerto gasta 1 de durabilidade. Com 0 para de funcionar mas não some:
## E recolhe (volta ao inventário com a durabilidade que tem) e a bancada conserta.
## Só fere inimigos. Não bloqueia passagem nem entra na malha de navegação
## (os zumbis andam por cima). Rede: só o servidor fere e gasta.

const PICKUP_RANGE := 3.5

var item_id := "spike_trap"
## Durabilidade restante (-1 = cheia, definida no _ready).
var uses := -1.0
var data: Dictionary = {}
var trap: Dictionary = {}

var _area: Area3D
var _next_hit := {}  # id do zumbi → hora (ms) em que pode ser ferido de novo
var _spikes: Node3D


func _ready() -> void:
	data = GameData.get_item(item_id)
	trap = data.get("trap", {})
	if uses < 0.0:
		uses = float(data.get("durability", 50.0))
	collision_layer = 32  # só interagível (E)
	collision_mask = 0
	_build()
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 4  # zumbis
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.0, 1.2)
	shape.shape = box
	shape.position.y = 0.5
	_area.add_child(shape)
	add_child(_area)
	set_physics_process(multiplayer.is_server())
	_show_state()


func max_uses() -> float:
	return float(data.get("durability", 50.0))


func display_name() -> String:
	return str(data.get("name", item_id))


func get_prompt() -> String:
	var state := "QUEBRADA · " if uses <= 0.0 else ""
	return "[E] Recolher %s (%s%d/%d)" % [display_name().to_lower(), state, ceili(uses), int(max_uses())]


func interact(player: Node3D) -> void:
	if multiplayer.is_server():
		_pickup(player)
	elif Network.is_online():
		_request_pickup.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup() -> void:
	var sender := multiplayer.get_remote_sender_id()
	for p: Node3D in get_tree().get_nodes_in_group("player"):
		if p.get_multiplayer_authority() == sender:
			_pickup(p)


func _pickup(player: Node3D) -> void:
	if is_queued_for_deletion() or player.global_position.distance_to(global_position) > PICKUP_RANGE:
		return
	(player.get_node(^"Inventory") as Inventory).grant(item_id, 1, {"dur": maxf(uses, 0.0)})
	queue_free()


func _physics_process(_delta: float) -> void:
	if uses <= 0.0:
		return
	var now := Time.get_ticks_msec()
	for body in _area.get_overlapping_bodies():
		if not body is Zombie:
			continue
		var health := Health.find_in(body)
		if health == null or health.is_dead:
			continue
		var key := body.get_instance_id()
		if now < int(_next_hit.get(key, 0)):
			continue
		_next_hit[key] = now + int(float(trap.get("interval", 1.0)) * 1000.0)
		# Sem fonte: o zumbi não "persegue" a armadilha.
		health.take_damage(float(trap.get("damage", 10.0)), null)
		if trap.has("slow"):
			body.apply_slow(float(trap.slow), float(trap.get("slow_time", 1.0)))
		uses = maxf(uses - 1.0, 0.0)
		_show_state()
		if Network.is_online():
			_sync_uses.rpc(uses)
		if uses <= 0.0:
			return


@rpc("authority", "call_remote", "reliable")
func _sync_uses(value: float) -> void:
	uses = value
	_show_state()


## Quebrada: espetos/mandíbula abaixados.
func _show_state() -> void:
	if _spikes:
		_spikes.position.y = -0.12 if uses <= 0.0 else 0.0


func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.1, 0.25, 1.1)
	shape.shape = box
	shape.position.y = 0.12
	add_child(shape)
	_spikes = Node3D.new()
	add_child(_spikes)
	match str(trap.get("look", "spikes")):
		"jaw":
			add_child(Weapon.cylinder(0.42, 0.04, Color(0.3, 0.3, 0.32), Vector3(0, 0.02, 0)))
			for side in [-1, 1]:
				var jaw := Weapon.box(Vector3(0.7, 0.14, 0.05), Color(0.45, 0.45, 0.48), Vector3(0, 0.1, 0.18 * side))
				_spikes.add_child(jaw)
				for k in 5:
					_spikes.add_child(Weapon.box(Vector3(0.04, 0.08, 0.04), Color(0.6, 0.6, 0.62),
						Vector3(-0.28 + k * 0.14, 0.2, 0.16 * side)))
			add_child(Weapon.box(Vector3(0.18, 0.03, 0.18), Color(0.55, 0.45, 0.2), Vector3(0, 0.05, 0)))
		_:
			add_child(Weapon.box(Vector3(1.1, 0.06, 1.1), Color(0.42, 0.29, 0.17), Vector3(0, 0.03, 0)))
			for x in 4:
				for z in 4:
					var spike := Weapon.cylinder(0.035, 0.32, Color(0.62, 0.5, 0.33),
						Vector3(-0.39 + x * 0.26, 0.2, -0.39 + z * 0.26))
					spike.rotation = Vector3(randf_range(-0.15, 0.15), 0, randf_range(-0.15, 0.15))
					_spikes.add_child(spike)
	for m: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
