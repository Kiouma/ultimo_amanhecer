class_name MenuBackground
extends Node3D
## Cenário da tela inicial, gerado na hora (leve): um vale ao amanhecer com colinas,
## um lago, árvores e pedras do Nature MegaKit, grama em MultiMesh, uma fogueira e a
## câmera girando devagar. Muda um pouco a cada vez (semente aleatória).

const RADIUS := 60.0
const GRID := 48
const ORBIT_SPEED := 0.035

var _camera: Camera3D
var _angle := 0.0
var _noise := FastNoiseLite.new()
var _fire: OmniLight3D
var _time := 0.0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_noise.seed = rng.randi()
	_noise.frequency = 0.035
	_angle = rng.randf() * TAU
	_build_environment()
	_build_terrain()
	_build_water()
	_scatter(rng)
	_build_campfire()
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 300.0
	add_child(_camera)
	_camera.current = true
	_update_camera()


func _process(delta: float) -> void:
	_angle += delta * ORBIT_SPEED
	_time += delta
	_update_camera()
	if _fire:
		_fire.light_energy = 2.2 + sin(_time * 9.0) * 0.25 + sin(_time * 23.0) * 0.15


func _update_camera() -> void:
	var pos := Vector3(cos(_angle) * 22.0, 0.0, sin(_angle) * 22.0)
	pos.y = _height(pos.x, pos.z) + 4.5
	_camera.position = pos
	_camera.look_at(Vector3(0, 2.2, 0))


## Vale: fundo plano perto do centro, colinas subindo para fora.
func _height(x: float, z: float) -> float:
	var d := Vector2(x, z).length()
	var hills := smoothstep(18.0, RADIUS, d) * 14.0
	return hills + _noise.get_noise_2d(x, z) * (0.6 + hills * 0.25)


func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.24, 0.32, 0.52)
	sky_mat.sky_horizon_color = Color(0.98, 0.62, 0.42)
	sky_mat.ground_horizon_color = Color(0.55, 0.42, 0.36)
	sky_mat.ground_bottom_color = Color(0.12, 0.12, 0.14)
	sky_mat.sun_angle_max = 12.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.85, 0.6, 0.5)
	env.fog_density = 0.008
	env.fog_sky_affect = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.72, 0.5)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	sun.rotation = Vector3(deg_to_rad(-12.0), deg_to_rad(-60.0), 0.0)
	add_child(sun)


func _build_terrain() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := RADIUS * 2.0 / GRID
	for j in GRID:
		for i in GRID:
			var corners := [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]
			for c: Array in corners:
				var x := -RADIUS + int(c[0]) * step
				var z := -RADIUS + int(c[1]) * step
				var h := _height(x, z)
				var grass := Color(0.27, 0.36, 0.2).lerp(Color(0.4, 0.42, 0.28), clampf(h / 12.0, 0.0, 1.0))
				st.set_color(grass.lightened(_noise.get_noise_2d(x * 4.0, z * 4.0) * 0.08))
				st.add_vertex(Vector3(x, h, z))
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var mesh := MeshInstance3D.new()
	mesh.mesh = st.commit()
	mesh.material_override = mat
	add_child(mesh)


func _build_water() -> void:
	var water := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 7.0
	disc.bottom_radius = 7.0
	disc.height = 0.05
	disc.radial_segments = 40
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.35, 0.45, 0.85)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.4
	mat.roughness = 0.05
	water.mesh = disc
	water.material_override = mat
	water.position = Vector3(9.0, _height(9.0, -6.0) + 0.08, -6.0)
	add_child(water)


func _scatter(rng: RandomNumberGenerator) -> void:
	var trees := ["Tree_1_A_Color1", "Tree_1_B_Color1", "Tree_2_A_Color1", "Tree_2_C_Color1", "Tree_3_A_Color1", "Tree_4_A_Color1", "Tree_4_B_Color1", "Tree_Bare_2_A_Color1"]
	for k in 46:
		var a := rng.randf() * TAU
		var d := rng.randf_range(12.0, RADIUS - 6.0)
		var p := Vector2(cos(a), sin(a)) * d
		if p.distance_to(Vector2(9, -6)) < 9.0:
			continue
		var model: String = trees[rng.randi() % trees.size()]
		var tree := NatureKit.instance(model, rng.randf_range(6.0, 10.0) if not model.begins_with("Tree_Bare") else rng.randf_range(7.0, 9.0))
		if tree == null:
			continue
		tree.position = Vector3(p.x, _height(p.x, p.y) - 0.1, p.y)
		tree.rotation.y = rng.randf() * TAU
		add_child(tree)
	for k in 10:
		var a := rng.randf() * TAU
		var d := rng.randf_range(5.0, RADIUS - 10.0)
		var rock := NatureKit.instance("Rock_3_%s_Color1" % "ABCDEFGH"[k % 8], rng.randf_range(0.8, 2.0))
		if rock:
			rock.position = Vector3(cos(a) * d, _height(cos(a) * d, sin(a) * d) - 0.1, sin(a) * d)
			rock.rotation.y = rng.randf() * TAU
			add_child(rock)
	# Grama e flores: uma MultiMesh por modelo.
	for model: String in ["Grass_1_A_Color1", "Grass_2_B_Color1", "Bush_1_A_Color1", "Bush_2_A_Color1"]:
		var mesh := NatureKit.mesh(model)
		if mesh == null:
			continue
		var count := 260 if model.begins_with("Grass") else 40
		var scale_range: Vector2 = {"Grass_1_A_Color1": Vector2(0.74, 1.11), "Grass_2_B_Color1": Vector2(0.45, 0.68), "Bush_1_A_Color1": Vector2(1.79, 2.68), "Bush_2_A_Color1": Vector2(0.76, 1.14)}.get(model, Vector2.ONE)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = count
		for k in count:
			var a := rng.randf() * TAU
			var d := sqrt(rng.randf()) * (RADIUS - 8.0)
			var x := cos(a) * d
			var z := sin(a) * d
			var s := rng.randf_range(scale_range.x, scale_range.y)
			mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, _height(x, z) - 0.03, z)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## Fogueira no centro: pedras em roda, lenha e uma luz que tremula.
func _build_campfire() -> void:
	var base := Vector3(0, _height(0, 0), 0)
	for k in 8:
		var a := TAU * k / 8.0
		var stone := NatureKit.instance("Rock_1_%s_Color1" % "ABCDE"[k % 5], 0.0)
		if stone:
			stone.scale = Vector3.ONE * 0.5
			stone.position = base + Vector3(cos(a) * 0.65, 0.0, sin(a) * 0.65)
			add_child(stone)
	for k in 3:
		var log_mesh := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.07
		cyl.bottom_radius = 0.07
		cyl.height = 0.9
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.2, 0.12)
		cyl.material = mat
		log_mesh.mesh = cyl
		log_mesh.position = base + Vector3(0, 0.12, 0)
		log_mesh.rotation = Vector3(PI * 0.5, TAU * k / 3.0, 0)
		add_child(log_mesh)
	var flame := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.22
	sphere.height = 0.6
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.55, 0.15)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.5, 0.1)
	flame_mat.emission_energy_multiplier = 3.0
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = flame_mat
	flame.mesh = sphere
	flame.position = base + Vector3(0, 0.35, 0)
	add_child(flame)
	_fire = OmniLight3D.new()
	_fire.light_color = Color(1.0, 0.6, 0.3)
	_fire.omni_range = 9.0
	_fire.position = base + Vector3(0, 0.8, 0)
	add_child(_fire)
