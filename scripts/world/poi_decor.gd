class_name PoiDecor
extends Node3D
## Móveis e objetos dos lugares (Fantasy Props e Medieval Village): dentro das casas e
## cabanas, barracas e carroça na praça do vilarejo, armas e caixotes no forte, caldeirão
## e velas nas ruínas. Montado a partir dos lugares planejados (World.pois) e da semente:
## igual em todas as máquinas, sem rede. Objetos grandes têm colisão simples.

const CELL := 3.0
## Tipo de lugar → [modelo, largura em metros, sólido?]
const SETS := {
	"house": [["Table_Large", 1.8, true], ["Chair_1", 0.5, true], ["Bed_Twin2", 1.9, true], ["Barrel", 0.65, true],
		["Crate_Wooden", 0.8, true], ["Bookcase_2", 1.3, true], ["Cabinet", 1.0, true], ["Bucket_Wooden_1", 0.4, false],
		["Pot_1", 0.4, false], ["Mug", 0.12, false]],
	"cabin": [["Bed_Twin1", 1.9, true], ["Cauldron", 0.9, true], ["Barrel", 0.65, true], ["Stool", 0.45, true],
		["Bucket_Wooden_1", 0.4, false], ["Crate_Wooden", 0.8, true], ["Anvil_Log", 0.8, true]],
	"military": [["WeaponStand", 1.3, true], ["Crate_Metal", 0.9, true], ["Crate_Wooden", 0.9, true], ["Barrel", 0.65, true],
		["Anvil", 1.0, true], ["Dummy", 0.8, true], ["Shield_Wooden", 0.7, false], ["Chain_Coil", 0.6, false]],
	"ruins": [["Cauldron", 1.0, true], ["BookStand", 0.7, true], ["CandleStick_Stand", 0.5, true], ["Vase_Rubble_Medium", 0.9, false],
		["Vase_4", 0.5, true], ["Scroll_2", 0.4, false], ["Book_Stack_2", 0.5, false], ["Chalice", 0.2, false]],
}
const VILLAGE_SQUARE := [["Stall_Empty", 2.0, true], ["Stall_Cart_Empty", 3.0, true], ["Barrel_Apples", 0.7, true],
	["FarmCrate_Apple", 0.8, true], ["FarmCrate_Carrot", 0.8, true], ["Bench", 1.5, true], ["Barrel_Holder", 1.6, true]]

var _world: Node


func _init(world: Node) -> void:
	_world = world
	name = "PoiDecor"


func _ready() -> void:
	var square := Vector2.ZERO
	var village := 0
	for poi: Dictionary in _world.pois:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(poi.seed) + 99
		match str(poi.type):
			"house", "cabin", "military", "ruins":
				_furnish(poi, rng)
		if str(poi.name) == "Vilarejo":
			square += poi.pos
			village += 1
	if village > 0:
		_village_square(square / village)


## Objetos encostados por dentro das paredes (cantos e meio dos lados).
func _furnish(poi: Dictionary, rng: RandomNumberGenerator) -> void:
	var options: Array = SETS.get(str(poi.type), [])
	if options.is_empty():
		return
	var cell: Vector2i = poi.cell
	var size: Vector2i = poi.size
	var lo := Vector2(cell) * CELL + Vector2(0.75, 0.75)
	var hi := Vector2(cell + size) * CELL - Vector2(0.75, 0.75)
	var spots := [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(lo.x, hi.y), Vector2(hi.x, hi.y),
		Vector2((lo.x + hi.x) * 0.5, lo.y), Vector2((lo.x + hi.x) * 0.5, hi.y)]
	var count := clampi(2 + size.x * size.y, 3, spots.size())
	var y := 0.05 if str(poi.type) in ["house", "cabin"] else 0.0  # em cima da fundação
	for i in count:
		var spot: Vector2 = spots[rng.randi() % spots.size()]
		spots.erase(spot)
		var pick: Array = options[rng.randi() % options.size()]
		# Mesa grande só cabe no meio de um lado; perto do canto vai algo menor.
		if float(pick[1]) > 1.6 and i < 4:
			pick = options[3 % options.size()]
		_place(str(pick[0]), float(pick[1]), bool(pick[2]), Vector3(spot.x, y, spot.y), rng.randi_range(0, 3) * PI * 0.5)


func _village_square(center: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(_world.world_seed) + 1234
	for i in VILLAGE_SQUARE.size():
		var pick: Array = VILLAGE_SQUARE[i]
		var a := TAU * i / VILLAGE_SQUARE.size() + rng.randf_range(-0.2, 0.2)
		var p := center + Vector2(cos(a), sin(a)) * rng.randf_range(2.0, 3.2)
		_place(str(pick[0]), float(pick[1]), bool(pick[2]), Vector3(p.x, _world.ground_height(p.x, p.y), p.y), -a + PI * 0.5)
	# Cerquinha de madeira em volta da praça, com aberturas.
	for k in 10:
		if k % 3 == 2:
			continue
		var a := TAU * k / 10.0
		var p := center + Vector2(cos(a), sin(a)) * 5.5
		var fence := ModelKit.fit_width(ModelKit.VILLAGE + "Prop_WoodenFence_Single.gltf", 2.0)
		if fence:
			fence.rotation.y = -a
			fence.position += Vector3(p.x, _world.ground_height(p.x, p.y), p.y)
			add_child(fence)
	_place_village_model("Prop_Wagon", 3.4, center + Vector2(6.5, 1.5), 0.6)


func _place_village_model(model: String, width: float, at: Vector2, rot: float) -> void:
	var path := ModelKit.VILLAGE + model + ".gltf"
	var node := ModelKit.fit_width(path, width)
	if node == null:
		return
	var holder := Node3D.new()
	holder.position = Vector3(at.x, _world.ground_height(at.x, at.y), at.y)
	holder.rotation.y = rot
	holder.add_child(node)
	add_child(holder)
	_add_collision(holder, ModelKit.fitted_size(path, width))


func _place(model: String, width: float, solid: bool, at: Vector3, rot: float) -> void:
	var path := ModelKit.PROPS + model + ".gltf"
	var node := ModelKit.fit_width(path, width)
	if node == null:
		return
	var holder := Node3D.new()
	holder.position = at
	holder.rotation.y = rot
	holder.add_child(node)
	add_child(holder)
	for m: GeometryInstance3D in holder.find_children("*", "GeometryInstance3D", true, false):
		m.visibility_range_end = 70.0
		m.visibility_range_end_margin = 6.0
		m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	if solid:
		_add_collision(holder, ModelKit.fitted_size(path, width))


func _add_collision(holder: Node3D, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size * Vector3(0.9, 1.0, 0.9)
	shape.shape = box
	shape.position.y = size.y * 0.5
	body.add_child(shape)
	holder.add_child(body)
