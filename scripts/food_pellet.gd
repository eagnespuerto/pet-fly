class_name FoodPellet
extends RigidBody3D

## A piece of food dropped in through the mouth of the vial.
##
## It falls under Jolt physics, squashes on impact, throws a short splash of
## droplets, and then dissolves into the dish while the dish's blob grows. The
## splash uses CPUParticles3D rather than GPU particles so it renders correctly
## under the GL compatibility renderer.

signal landed(pellet: FoodPellet)

const RADIUS := 0.19
const DISSOLVE_AFTER := 0.85       # seconds resting before it soaks in
const DISSOLVE_TIME := 0.55

var food: Dictionary = {}
var _mesh: MeshInstance3D
var _mat: StandardMaterial3D
var _splash: CPUParticles3D
var _trail: CPUParticles3D
var _has_landed := false
var _rest_t := 0.0
var _dissolving := false


static func spawn(parent: Node3D, food_def: Dictionary, from: Vector3) -> FoodPellet:
	var p := FoodPellet.new()
	p.food = food_def
	parent.add_child(p)
	p.global_position = from
	# A little sideways drift so repeated drops do not stack identically.
	p.linear_velocity = Vector3(randf_range(-0.25, 0.25), -0.4, randf_range(-0.25, 0.25))
	p.angular_velocity = Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3))
	return p


func _ready() -> void:
	var colour: Color = food.get("colour", Color(0.93, 0.78, 0.31))

	mass = 0.05
	gravity_scale = 1.15
	continuous_cd = true          # small and fast: do not tunnel through the medium
	contact_monitor = true
	max_contacts_reported = 4

	var phys := PhysicsMaterial.new()
	phys.friction = 0.85
	phys.bounce = 0.18
	physics_material_override = phys

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = RADIUS
	shape.shape = sphere
	add_child(shape)

	_mesh = MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = RADIUS
	m.height = RADIUS * 2.0
	m.radial_segments = 18
	m.rings = 10
	_mesh.mesh = m
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = colour
	_mat.roughness = 0.30
	_mat.metallic_specular = 0.6
	# Water and sucrose read better with a little translucency.
	if float(food.get("water", 0.0)) > 0.3:
		_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mat.albedo_color.a = 0.78
	_mesh.material_override = _mat
	add_child(_mesh)

	_trail = _make_particles(colour, 14, 0.35, 0.5)
	_trail.emitting = true
	add_child(_trail)

	_splash = _make_particles(colour, 26, 0.55, 1.8)
	_splash.emitting = false
	_splash.one_shot = true
	add_child(_splash)

	body_entered.connect(_on_body_entered)


func _make_particles(colour: Color, amount: int, lifetime: float,
		speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.0
	p.direction = Vector3.UP
	p.spread = 55.0
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6.5, 0)
	p.scale_amount_min = 0.035
	p.scale_amount_max = 0.075
	p.damping_min = 0.5
	p.damping_max = 1.5

	var pm := StandardMaterial3D.new()
	pm.albedo_color = colour
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.vertex_color_use_as_albedo = true
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	p.mesh = sm
	p.material_override = pm

	var ramp := Gradient.new()
	ramp.set_color(0, colour)
	ramp.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	p.color_ramp = ramp
	return p


func _on_body_entered(_body: Node) -> void:
	if _has_landed:
		return
	_has_landed = true
	_trail.emitting = false
	_splash.emitting = true
	# Squash on impact, then spring back - cheap but it sells the landing.
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3(1.35, 0.55, 1.35), 0.06)
	tw.tween_property(_mesh, "scale", Vector3(0.95, 1.08, 0.95), 0.10)
	tw.tween_property(_mesh, "scale", Vector3.ONE, 0.12)
	landed.emit(self)


func _physics_process(delta: float) -> void:
	if _dissolving:
		return
	if _has_landed and linear_velocity.length() < 0.25:
		_rest_t += delta
		if _rest_t >= DISSOLVE_AFTER:
			_dissolve()
	else:
		_rest_t = 0.0
	# Safety net: never leave a pellet lying around forever.
	if global_position.y < -2.0:
		queue_free()


func _dissolve() -> void:
	_dissolving = true
	freeze = true
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_mesh, "scale", Vector3(1.5, 0.05, 1.5), DISSOLVE_TIME)
	tw.tween_property(_mat, "albedo_color:a", 0.0, DISSOLVE_TIME)
	tw.chain().tween_callback(queue_free)
