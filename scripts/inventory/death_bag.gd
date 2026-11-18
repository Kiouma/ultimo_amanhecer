class_name DeathBag
extends StaticBody3D
## Bag deixada onde um jogador morreu (GDD 7): guarda os itens da mochila dele.
## E pega tudo (o que não couber no inventário cai no chão ao lado). Some quando
## é esvaziada. Qualquer jogador pode pegar (co-op).
## Rede: o conteúdo só é confiável no servidor; ver WorldItems.loot_bag.

## [{ "id": String, "count": int }, ...]
var contents: Array = []
var owner_name := ""

var _label: Label3D


func _ready() -> void:
	collision_layer = 32  # interagível
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 0.6, 0.7)
	shape.shape = box
	shape.position.y = 0.3
	add_child(shape)

	var sack := Weapon.sphere(0.32, Color(0.35, 0.25, 0.18), Vector3(0, 0.28, 0))
	sack.scale = Vector3(1.0, 0.8, 1.0)
	sack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(sack)
	add_child(Weapon.cylinder(0.08, 0.12, Color(0.3, 0.2, 0.14), Vector3(0, 0.55, 0)))
	# Pequena luz para achar a bag à noite.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.85, 0.5)
	glow.light_energy = 0.6
	glow.omni_range = 2.5
	glow.position.y = 0.8
	add_child(glow)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 30
	_label.pixel_size = 0.004
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.85, 0.5)
	_label.position.y = 1.0
	_label.text = _title()
	add_child(_label)


func item_total() -> int:
	var total := 0
	for stack in contents:
		total += int(stack.count)
	return total


func get_prompt() -> String:
	return tr("[E] Pegar tudo da %s") % _title()


func interact(player: Node3D) -> void:
	WorldItems.loot_bag(self, player)


func _title() -> String:
	return tr("bag de %s (%d itens)") % [owner_name, item_total()]
