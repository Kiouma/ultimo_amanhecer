class_name CraftingStation
extends StaticBody3D
## Estação de fabricação colocada no mundo (GDD 8.2): fogueira, bancada...
## E abre a tela de inventário com as receitas dela. Receitas de uma estação só
## avançam na fila de fabricação com o jogador perto (ver CraftQueue).
## Visual provisório: formas simples.

## Distância para usar a estação e para a fila continuar fabricando.
const USE_RANGE := 4.0

var item_id := "campfire"
## Tipo de estação (campo "station" do item): "campfire", "workbench"...
var station := ""

var _flame: OmniLight3D
var _time := randf() * 10.0


func _ready() -> void:
	station = str(GameData.get_item(item_id).get("station", item_id))
	collision_layer = 1 | 8 | 32  # mundo, construções, interagível
	collision_mask = 0
	add_to_group("navmesh_source")
	_build()


func display_name() -> String:
	return str(GameData.get_item(item_id).get("name", item_id))


func get_prompt() -> String:
	return tr("[E] Usar %s") % display_name().to_lower()


func interact(player: Node3D) -> void:
	EventBus.station_opened.emit(self, player)


func _process(delta: float) -> void:
	if _flame:
		_time += delta
		_flame.light_energy = 2.0 + sin(_time * 9.0) * 0.25 + sin(_time * 23.0) * 0.15


func _build() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	match station:
		"campfire":
			for i in 7:
				var a := TAU * i / 7.0
				add_child(Weapon.sphere(0.13, Color(0.45, 0.45, 0.47), Vector3(cos(a) * 0.45, 0.08, sin(a) * 0.45)))
			for i in 3:
				var wood_log := Weapon.box(Vector3(0.09, 0.09, 0.6), Color(0.35, 0.22, 0.12), Vector3(0, 0.12, 0))
				wood_log.rotation.y = TAU * i / 3.0
				wood_log.rotation.x = 0.35
				add_child(wood_log)
			add_child(Weapon.sphere(0.16, Color(1.0, 0.55, 0.15), Vector3(0, 0.28, 0), true))
			_flame = OmniLight3D.new()
			_flame.light_color = Color(1.0, 0.6, 0.3)
			_flame.omni_range = 9.0
			_flame.shadow_enabled = true
			_flame.position.y = 0.6
			add_child(_flame)
			box.size = Vector3(1.1, 0.4, 1.1)
			shape.position.y = 0.2
		_:  # bancada
			add_child(Weapon.box(Vector3(1.6, 0.08, 0.8), Color(0.5, 0.34, 0.2), Vector3(0, 0.9, 0)))
			for x in [-0.7, 0.7]:
				for z in [-0.32, 0.32]:
					add_child(Weapon.box(Vector3(0.08, 0.9, 0.08), Color(0.4, 0.27, 0.16), Vector3(x, 0.45, z)))
			add_child(Weapon.box(Vector3(0.3, 0.12, 0.2), Color(0.5, 0.5, 0.52), Vector3(0.4, 1.0, 0.1)))
			box.size = Vector3(1.6, 1.0, 0.8)
			shape.position.y = 0.5
	shape.shape = box
	add_child(shape)
	for m: GeometryInstance3D in find_children("*", "GeometryInstance3D", true, false):
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
