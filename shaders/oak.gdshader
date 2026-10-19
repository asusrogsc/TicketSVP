shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 oak_color : source_color = vec4(0.67, 0.485, 0.285, 1.0);
uniform float grain_seed = 0.0;
varying vec3 local_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), u.x), u.y);
}
void vertex() {
	local_position = VERTEX;
}
void fragment() {
	// Meter-based grain: long, softly curved fibers, no periodic sine stripes.
	vec2 p = local_position.xz + vec2(grain_seed * 7.31, grain_seed * 3.17);
	float bend = noise(p * vec2(9.0, 0.85));
	float drift = noise(p * vec2(19.0, 2.4));
	float cross_grain = p.x + (bend - 0.5) * 0.028 + (drift - 0.5) * 0.006;
	float broad = noise(vec2(cross_grain * 39.0, p.y * 1.2));
	float medium = noise(vec2(cross_grain * 110.0, p.y * 2.8));
	float fine = noise(vec2(cross_grain * 280.0, p.y * 9.0));
	// Fade small detail with distance to prevent shimmering and harsh stripes.
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float fine_visibility = 1.0 - smoothstep(0.0015, 0.008, footprint);
	float medium_visibility = 1.0 - smoothstep(0.005, 0.025, footprint);
	float pores = smoothstep(0.73, 0.92, fine) * fine_visibility;
	float grain = (broad - 0.5) * 0.12
		+ (medium - 0.5) * 0.065 * medium_visibility
		+ (fine - 0.5) * 0.022 * fine_visibility - pores * 0.026;
	ALBEDO = oak_color.rgb * (1.0 + grain);
	ROUGHNESS = clamp(0.59 + (broad - 0.5) * 0.06 + pores * 0.04, 0.54, 0.65);
	SPECULAR = 0.28;
}
