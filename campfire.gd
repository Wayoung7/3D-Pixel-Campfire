@tool
extends Node3D

const PARTICLES := 40
const SPARKS := 60

@export_range(0.0, 1.0, 0.01) var burn := 0.6
@export_range(0.0, 8.0, 0.01) var light_energy := 2.4
@export_range(1.0, 20.0, 0.1) var light_range := 6.0
@export var light_color := Color(1.0, 0.46, 0.2)
@export_range(0.0, 1.0, 0.01) var flicker := 0.3
@export_range(0.1, 3.0, 0.01) var animation_speed := 1.0
@export_range(0.0, 1.0, 0.01) var sparks := 0.35

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _positions := PackedVector3Array()
var _velocities := PackedVector3Array()
var _ages := PackedFloat32Array()
var _lifetimes := PackedFloat32Array()
var _sizes := PackedFloat32Array()
var _particle_spheres := PackedVector4Array()
var _particle_heat := PackedFloat32Array()
var _particle_activity := 1.0
var _flame_material: ShaderMaterial
var _spark_material: ShaderMaterial
var _animated_materials: Array[ShaderMaterial] = []

@onready var _flame: MeshInstance3D = $Flame
@onready var _embers: MultiMeshInstance3D = $Embers
@onready var _light: OmniLight3D = $Light


func _ready() -> void:
	_noise.frequency = 1.0
	_rng.seed = 7
	for mesh: GeometryInstance3D in [_flame, _embers, $Logs, $Coals]:
		var material := mesh.material_override.duplicate() as ShaderMaterial
		mesh.material_override = material
		_animated_materials.append(material)
	_flame_material = _flame.material_override
	_spark_material = _embers.material_override
	_positions.resize(PARTICLES)
	_velocities.resize(PARTICLES)
	_ages.resize(PARTICLES)
	_lifetimes.resize(PARTICLES)
	_sizes.resize(PARTICLES)
	_particle_spheres.resize(PARTICLES)
	_particle_heat.resize(PARTICLES)
	for i in PARTICLES:
		_spawn(i)
		_ages[i] = _rng.randf() * _lifetimes[i]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = QuadMesh.new()
	multimesh.instance_count = SPARKS
	for i in SPARKS:
		multimesh.set_instance_transform(i, Transform3D.IDENTITY)
		multimesh.set_instance_custom_data(i, Color(_rng.randf(), _rng.randf(), _rng.randf(), 0.0))
	_embers.multimesh = multimesh
	_embers.custom_aabb = AABB(Vector3(-1, 0, -1), Vector3(2, 5, 2))
	if Engine.is_editor_hint():
		for i in 90:
			_process(1.0 / 60.0)
		set_process(false)


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05) * animation_speed
	_clock += dt
	var burn_variation := clampf(_noise.get_noise_1d(_clock * 0.25 + 600.0) * 1.6, -1.0, 1.0)
	var burn_level := clampf(burn + 0.08 * burn_variation, 0.0, 1.0)
	var fire_scale := 0.6 + 0.7 * pow(burn_level, 0.95)
	var opacity: Vector3
	var turbulence_strength: float
	if burn_level < 0.6:
		var normalized_burn := clampf((burn_level - 0.08) / 0.52, 0.0, 1.0)
		_particle_activity = 1.0 - pow(1.0 - normalized_burn, 2.0)
		opacity = Vector3(0.48, 0.72, 0.92).lerp(Vector3(0.75, 0.87, 0.96), burn_level / 0.6)
		turbulence_strength = 0.6 + 0.4 * burn_level / 0.6
	else:
		_particle_activity = 1.0 + 0.25 * (burn_level - 0.6) / 0.4
		opacity = Vector3(0.75, 0.87, 0.96).lerp(Vector3(0.95, 1.0, 1.0), (burn_level - 0.6) / 0.4)
		turbulence_strength = 1.0 + 0.3 * (burn_level - 0.6) / 0.4
	var breathing := 0.55 * _noise.get_noise_1d(_clock * 1.3)
	var brightness := clampf(0.5 + breathing + 0.3 * _noise.get_noise_1d(_clock * 6.0 + 50.0), 0.0, 1.0)
	var light_flicker := 1.0 + flicker * (brightness - 0.5) * 2.0
	_light.light_energy = light_energy * light_flicker * pow(fire_scale, 1.3)
	_light.omni_range = light_range * (0.55 + 0.45 * fire_scale)
	_light.light_color = light_color.lerp(light_color * Color(1.0, 0.7, 0.6), (1.0 - brightness) * 0.35)
	var light_sway := Vector3(
		_noise.get_noise_1d(_clock * 2.0 + 100.0),
		0.5 * _noise.get_noise_1d(_clock * 2.5 + 200.0),
		_noise.get_noise_1d(_clock * 2.0 + 300.0)
	)
	_light.position = Vector3(0, 0.45 + 0.15 * fire_scale, 0) + light_sway * 0.05
	var flare := 0.5 + (clampf(0.5 + breathing, 0.0, 1.0) - 0.5) * flicker / 0.3
	for material in _animated_materials:
		material.set_shader_parameter(&"flare", flare)
	_flame.scale = Vector3.ONE * fire_scale
	_flame.position.y = 1.12 * fire_scale
	_flame_material.set_shader_parameter(&"fire_time", _clock)
	_flame_material.set_shader_parameter(&"fire_alpha", opacity)
	var body_height := lerpf(1.18, 0.55, minf(_particle_activity, 1.0)) - 0.2 * maxf(_particle_activity - 1.0, 0.0)
	_flame_material.set_shader_parameter(&"fire_body", body_height)
	var heat_steps := Vector2(
		0.08 * clampf((0.6 - burn_level) / 0.3, 0.0, 1.0),
		-0.2 * clampf((0.35 - burn_level) / 0.35, 0.0, 1.0)
	)
	_flame_material.set_shader_parameter(&"fire_steps", heat_steps)
	_flame_material.set_shader_parameter(&"fire_girth", 0.85 + 0.15 * minf(burn_level / 0.6, 1.0))
	_flame_material.set_shader_parameter(&"fire_turbulence", turbulence_strength)
	_embers.scale = Vector3.ONE * fire_scale
	_spark_material.set_shader_parameter(&"spark_time", _clock)
	_spark_material.set_shader_parameter(&"spark_amount", minf(sparks * pow(_particle_activity, 1.5), 1.0))
	_simulate(dt, brightness)


func _spawn(i: int) -> void:
	var angle := _rng.randf() * TAU
	var weak := 1.0 - minf(_particle_activity, 1.0)
	var y := 0.08 + 1.35 * 0.55 * _rng.randf_range(0.15, 0.6 - 0.3 * weak)
	var radius := sqrt(_rng.randf()) * 0.3 * (1.0 - 0.4 * weak)
	_positions[i] = Vector3(cos(angle) * radius, y, sin(angle) * radius)
	_velocities[i] = Vector3(_rng.randf_range(-0.15, 0.15), _rng.randf_range(0.4, 0.8), _rng.randf_range(-0.15, 0.15))
	_ages[i] = 0.0
	_lifetimes[i] = _rng.randf_range(0.55, 1.0) * (1.0 - 0.4 * weak + 0.6 * maxf(_particle_activity - 1.0, 0.0))
	_sizes[i] = _rng.randf_range(0.19, 0.29) * (1.0 - 0.25 * weak)


func _simulate(dt: float, brightness: float) -> void:
	var gather := 2.0 * (1.0 + 1.5 * (1.0 - minf(_particle_activity, 1.0)))
	var buoyancy := Vector3.UP * 3.2 * (0.8 + 0.4 * brightness)
	var drag := exp(-1.2 * dt)
	var heat := 0.85 * minf(_particle_activity, 1.0)
	for i in PARTICLES:
		var p := _positions[i]
		var swirl := Vector3(
			_noise.get_noise_3d(p.x * 1.5, p.y - _clock * 0.8, p.z * 1.5),
			0,
			_noise.get_noise_3d(p.x * 1.5 + 50.0, p.y - _clock * 0.8, p.z * 1.5)
		) * 1.1
		var acceleration := buoyancy + swirl - Vector3(p.x, 0, p.z) * gather
		_velocities[i] = (_velocities[i] + acceleration * dt) * drag
		_positions[i] += _velocities[i] * dt
		_ages[i] += dt
		if _ages[i] >= _lifetimes[i]:
			_spawn(i)
		var age := _ages[i] / _lifetimes[i]
		_particle_spheres[i] = Vector4(_positions[i].x, _positions[i].y, _positions[i].z, _sizes[i] * (1.0 - 0.7 * age))
		_particle_heat[i] = heat * minf(_ages[i] / 0.25, 1.0) * (1.0 - age)
	_flame_material.set_shader_parameter(&"fire_particles", _particle_spheres)
	_flame_material.set_shader_parameter(&"fire_particle_heat", _particle_heat)
