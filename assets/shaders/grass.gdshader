shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Grass blades for the lawn the culture vial stands on.
// Vertex COLOR.r carries height along the blade: 0 at the root, 1 at the tip.
// That drives both the wind sway (tips move, roots do not) and the colour ramp.

uniform vec3 root_color : source_color = vec3(0.11, 0.24, 0.09);
uniform vec3 tip_color : source_color = vec3(0.44, 0.70, 0.26);
uniform vec3 dry_color : source_color = vec3(0.55, 0.58, 0.24);
uniform float wind_strength = 0.19;
uniform float wind_speed = 1.35;
uniform float gust = 0.35;
// 1.0 in full daylight, 0.0 at night; driven from the circadian clock.
uniform float day : hint_range(0.0, 1.0) = 1.0;

varying float blade_h;
varying float dryness;
varying float tint;

void vertex() {
	blade_h = COLOR.r;
	dryness = COLOR.g;
	// MultiMesh instance colour arrives via INSTANCE_CUSTOM-free COLOR blending,
	// so read it from the instance colour the MultiMesh supplies.
	tint = INSTANCE_CUSTOM.r > 0.0 ? INSTANCE_CUSTOM.r : 1.0;

	vec3 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float phase = world.x * 0.55 + world.z * 0.42;

	// Two sine waves at different rates read as a breeze rather than a pulse.
	float sway = sin(TIME * wind_speed + phase)
		+ gust * sin(TIME * wind_speed * 2.37 + phase * 1.73);

	// Bend, not shear: displacement grows with the square of blade height so
	// the blade pivots from its root.
	float bend = blade_h * blade_h * wind_strength;
	VERTEX.x += sway * bend;
	VERTEX.z += sway * bend * 0.55;
	VERTEX.y -= abs(sway) * bend * 0.18;   // shorten slightly as it leans
}

void fragment() {
	vec3 green = mix(root_color, tip_color, blade_h);
	vec3 c = mix(green, dry_color, dryness * 0.55);
	// Night grass goes dim and slightly blue rather than merely dark.
	vec3 night = vec3(0.10, 0.15, 0.24) * (0.45 + 0.55 * blade_h);
	ALBEDO = mix(night, c, day) * tint;
	ROUGHNESS = 0.88;
	SPECULAR = 0.15;
}
