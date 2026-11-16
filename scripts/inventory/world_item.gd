extends StaticBody3D
## Um item solto no chão. Olhe para ele e aperte E (interagir) para pegar.
## Visual provisório: um pacotinho com a cor do tipo e o nome flutuando.

const TYPE_COLORS := {
	"resource": Color(0.55, 0.42, 0.28),
	"ammo": Color(0.75, 0.6, 0.2),
	"consumable": Color(0.85, 0.85, 0.85),
	"firearm": Color(0.2, 0.2, 0.22),
	"melee": Color(0.5, 0.52, 0.55),
	"tool": Color(0.6, 0.35, 0.15),
	"grimoire": Color(0.45, 0.2, 0.6),
}

var item_id := ""
var count := 1
## Peer id de quem soltou (0 = o mundo). Ver WorldItems.DROP_COOLDOWN.
var dropped_by := 0
## Estado do item (durabilidade, balas no pente), ver Inventory.EXTRA_KEYS.
var extra: Dictionary = {}

var _born_msec := Time.get_ticks_msec()

var _label: Label3D
var _time := randf() * TAU


func _ready() -> void:
	collision_layer = 32  # interagíveis
	collision_mask = 0
	var data := GameData.get_item(item_id)
	var color: Color = TYPE_COLORS.get(str(data.get("type", "")), Color(0.7, 0.7, 0.7))

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.45, 0.45, 0.45)
	shape.shape = box
	shape.position.y = 0.2
	add_child(shape)

	var mesh := Weapon.box(Vector3(0.3, 0.2, 0.3), color, Vector3(0, 0.12, 0))
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = false
	_label.font_size = 28
	_label.pixel_size = 0.004
	_label.outline_size = 8
	_label.position.y = 0.5
	_label.text = display_text()
	add_child(_label)


func _process(delta: float) -> void:
	_time += delta
	_label.position.y = 0.5 + sin(_time * 2.0) * 0.03


## Segundos desde que o item apareceu nesta máquina.
func age() -> float:
	return (Time.get_ticks_msec() - _born_msec) / 1000.0


func display_text() -> String:
	var item_name := str(GameData.get_item(item_id).get("name", item_id))
	return item_name if count <= 1 else "%s ×%d" % [item_name, count]


## Texto do aviso na tela quando o jogador olha para o item.
func get_prompt() -> String:
	return "[E] Pegar %s" % display_text()


func interact(player: Node3D) -> void:
	WorldItems.request_pickup(self, player)
