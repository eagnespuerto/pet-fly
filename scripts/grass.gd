class_name Grass
extends MultiMeshInstance3D

## A procedural lawn for the vial to stand on.
##
## One tapered blade mesh, instanced a few thousand times through a MultiMesh,
## with the wind sway done entirely in the vertex shader (see grass.gdshader).
## Blades are scattered in a ring so none of them grow through the vial.

@export var blade_count := 22000
@export var inner_radius := 3.15      # keep clear of the vial footprint
@export var outer_radius := 11.0
@export var blade_height := 0.46
@export var blade_width := 0.115
@export var segments := 4
@export var rng_seed := 20260910

var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/shaders/grass.gdshader")
	material_override = _material
	_build()


func set_daylight(v: float) -> void:
	if _material:
		_material.set_shader_parameter("day", clampf(v, 0.0, 1.0))


func set_wind(strength: float) -> void:
	if _material:
		_material.set_shader_parameter("wind_strength", strength)


func _build() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _make_blade()
	mm.instance_count = blade_count

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var placed := 0
	for i in blade_count:
		# Uniform disc sampling over an annulus: sqrt keeps density even.
		var t := rng.randf()
		var r := sqrt(lerpf(inner_radius * inner_radius, outer_radius * outer_radius, t))
		var a := rng.randf() * TAU
		var pos := Vector3(cos(a) * r, 0.0, sin(a) * r)

		# Thin the lawn out towards the far edge so it fades rather than stops.
		var edge := inverse_lerp(inner_radius, outer_radius, r)
		if edge > 0.82 and rng.randf() < (edge - 0.82) * 2.4:
			# Leave this slot empty by shrinking it to nothing.
			mm.set_instance_transform(i, Transform3D().scaled(Vector3.ZERO))
			continue

		var xf := Transform3D()
		xf = xf.rotated(Vector3.UP, rng.randf() * TAU)
		# A little lean so the lawn is not a field of perfect verticals.
		xf = xf.rotated(Vector3.FORWARD, rng.randf_range(-0.16, 0.16))
		var s := rng.randf_range(0.68, 1.34)
		xf = xf.scaled(Vector3(rng.randf_range(0.8, 1.2), s, 1.0))
		xf.origin = pos
		mm.set_instance_transform(i, xf)
		# A little variation in tint so the lawn is not one flat green.
		var g := rng.randf_range(0.82, 1.12)
		mm.set_instance_color(i, Color(g, g, g, 1.0))
		placed += 1

	multimesh = mm
	# Grass is small and everywhere; a generous AABB stops it popping out of
	# view when the camera swings low.
	custom_aabb = AABB(Vector3(-outer_radius, -0.2, -outer_radius),
			Vector3(outer_radius * 2.0, blade_height * 2.0, outer_radius * 2.0))


func _make_blade() -> ArrayMesh:
	## A tapered blade that curves forward slightly, built as a triangle strip.
	## COLOR.r = height fraction (drives sway + colour), COLOR.g = dryness.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var dry := randf() * 0.0   # per-blade dryness is set below, kept flat here
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []

	for s in segments + 1:
		var f := float(s) / float(segments)
		var y := blade_height * f
		# Taper to a point, and curve gently forward as it rises.
		var half := blade_width * (1.0 - f) * 0.5
		var z := f * f * 0.10
		verts.append(Vector3(-half, y, z))
		verts.append(Vector3(half, y, z))
		var c := Color(f, dry, 0.0)
		cols.append(c)
		cols.append(c)

	var normal := Vector3(0, 0, 1)
	for s in segments:
		var i0 := s * 2
		var i1 := s * 2 + 1
		var i2 := s * 2 + 2
		var i3 := s * 2 + 3
		for idx in [i0, i2, i1, i1, i2, i3]:
			st.set_color(cols[idx])
			st.set_normal(normal)
			st.add_vertex(verts[idx])

	st.generate_normals()
	return st.commit()
