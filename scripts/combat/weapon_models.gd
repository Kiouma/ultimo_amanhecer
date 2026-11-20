class_name WeaponModels
extends RefCounted
## Modelos 3D de armas e ferramentas (KayKit Adventurers e Fantasy Weapons Bits, CC0).
## O campo "model" dos itens (e "weapon_model" dos monstros) é o caminho dentro de
## res://assets/models/ sem extensão, ex.: "weapons/kaykit/sword_A". Cada cena é
## carregada uma vez.

const ROOT := "res://assets/models/"

static var _scenes := {}


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		var packed: PackedScene = null
		for ext in [".gltf", ".glb"]:
			if ResourceLoader.exists(ROOT + path + ext):
				packed = load(ROOT + path + ext) as PackedScene
				break
		_scenes[path] = packed
	return _scenes[path]


static func instance(path: String) -> Node3D:
	var packed := scene(path)
	return packed.instantiate() as Node3D if packed else null


## Instância com o comprimento (maior lado) igual a `length` metros, para a 1ª pessoa.
static func instance_sized(path: String, length: float) -> Node3D:
	var node := instance(path)
	if node == null:
		return null
	var size := Vector3.ZERO
	for m: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		size = size.max(m.get_aabb().size)
	if node is MeshInstance3D:
		size = size.max((node as MeshInstance3D).get_aabb().size)
	var longest := maxf(maxf(size.x, size.y), size.z)
	if longest > 0.001:
		node.scale = Vector3.ONE * (length / longest)
	return node
