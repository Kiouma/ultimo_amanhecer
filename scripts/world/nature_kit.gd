class_name NatureKit
## Modelos do Stylized Nature MegaKit (Quaternius, CC0) em assets/models/environment/nature/.
## Carrega cada modelo uma vez e guarda a cena, a malha e a altura (para escalar por
## altura desejada em vez de por fator: os modelos do kit têm tamanhos bem diferentes).

const DIR := "res://assets/models/environment/nature/"

static var _scenes := {}
static var _meshes := {}
static var _heights := {}


static func scene(model: String) -> PackedScene:
	if not _scenes.has(model):
		_scenes[model] = load(DIR + model + ".gltf") as PackedScene
	return _scenes[model]


## Malha do modelo (todos os modelos do kit têm uma só, sem transformação no nó).
static func mesh(model: String) -> Mesh:
	if not _meshes.has(model):
		var m: Mesh = null
		var packed := scene(model)
		if packed:
			var inst := packed.instantiate()
			var mi := inst as MeshInstance3D
			if mi == null:
				var found := inst.find_children("*", "MeshInstance3D", true, false)
				mi = found[0] if not found.is_empty() else null
			if mi:
				m = mi.mesh
			inst.free()
		_meshes[model] = m
	return _meshes[model]


## Altura do modelo em metros (do pé ao topo).
static func height(model: String) -> float:
	if not _heights.has(model):
		var m := mesh(model)
		_heights[model] = maxf(m.get_aabb().end.y, 0.01) if m else 1.0
	return _heights[model]


## Instância do modelo com altura `target_height` (0 = tamanho original).
static func instance(model: String, target_height := 0.0) -> Node3D:
	var packed := scene(model)
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if target_height > 0.0:
		node.scale = Vector3.ONE * (target_height / height(model))
	return node


## Número estável a partir de uma posição: todos (servidor e clientes) escolhem a
## mesma variante para o mesmo recurso sem precisar mandar isso pela rede.
static func position_hash(p: Vector3) -> int:
	return absi(hash(Vector2i(roundi(p.x * 10.0), roundi(p.z * 10.0))))
