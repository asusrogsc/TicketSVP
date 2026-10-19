shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 oak_color : source_color = vec4(0.58, 0.39, 0.22, 1.0);
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
	// Physical coordinates keep the grain scale consistent on trimmed boards.
	vec2 p = local_position.xz + vec2(grain_seed * 7.31, grain_seed * 3.17);
	float broad = noise(p * vec2(24.0, 1.5));
	float warp = noise(p * vec2(13.0, 2.2));
	float fibers = noise(vec2(p.x * 360.0 + warp * 6.0, p.y * 6.0));
	float rings = sin(p.x * 210.0 + warp * 9.0 + broad * 3.0);
	float grain = (broad - 0.5) * 0.15 + (fibers - 0.5) * 0.065 + rings * 0.022;
	ALBEDO = oak_color.rgb * (1.0 + grain);
	ROUGHNESS = clamp(0.64 + (fibers - 0.5) * 0.10, 0.54, 0.74);
	SPECULAR = 0.3;
}
