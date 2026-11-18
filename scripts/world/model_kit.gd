class_name ModelKit
## Modelos prontos (Fantasy Props e Medieval Village, Quaternius, CC0): carrega uma vez,
## mede a caixa do modelo e o encaixa onde precisa:
## - fit_box: estica para ocupar exatamente uma caixa (paredes das construções);
## - fit_width: escala por igual até a largura pedida, apoiado no chão (móveis, estações).

const PROPS := "res://assets/models/props/fantasy/"
const VILLAGE := "res://assets/models/buildings/village/"

static var _scenes := {}
static var _aabbs := {}


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene if ResourceLoader.exists(path) else null
	return _scenes[path]


## Caixa do modelo (todas as malhas, no espaço da raiz da cena).
static func aabb(path: String) -> AABB:
	if not _aabbs.has(path):
		var box := AABB()
		var first := true
		var packed := scene(path)
		if packed:
			var root := packed.instantiate() as Node3D
			for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
				var xform := Transform3D.IDENTITY
				var n: Node = mi
				while n and n != root:
					if n is Node3D:
						xform = (n as Node3D).transform * xform
					n = n.get_parent()
				var b := xform * mi.get_aabb()
				box = b if first else box.merge(b)
				first = false
			root.free()
		_aabbs[path] = box
	return _aabbs[path]


static func instance(path: String) -> Node3D:
	var packed := scene(path)
	return packed.instantiate() as Node3D if packed else null


## Modelo esticado para ocupar a caixa de tamanho `size` centrada em `center`.
static func fit_box(path: String, size: Vector3, center: Vector3) -> Node3D:
	var node := instance(path)
	if node == null:
		return null
	var a := aabb(path)
	var s := Vector3(size.x / maxf(a.size.x, 0.001), size.y / maxf(a.size.y, 0.001), size.z / maxf(a.size.z, 0.001))
	node.scale = s
	node.position = center - a.get_center() * s
	return node


## Escala por igual até a maior medida horizontal ser `width`; base no chão (y = 0).
static func fit_width(path: String, width: float) -> Node3D:
	var node := instance(path)
	if node == null:
		return null
	var a := aabb(path)
	var s := width / maxf(maxf(a.size.x, a.size.z), 0.001)
	node.scale = Vector3.ONE * s
	var c := a.get_center()
	node.position = Vector3(-c.x * s, -a.position.y * s, -c.z * s)
	return node


## Tamanho que o modelo terá com fit_width (para colisão).
static func fitted_size(path: String, width: float) -> Vector3:
	var a := aabb(path)
	return a.size * (width / maxf(maxf(a.size.x, a.size.z), 0.001))
