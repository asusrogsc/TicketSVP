shader_type spatial;
render_mode diffuse_burley;
uniform vec4 base_color : source_color = vec4(0.27, 0.29, 0.29, 1.0);
uniform bool fabric = false;
varying vec3 local_position;
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
void vertex() { local_position = VERTEX; }
void fragment() {
	vec2 p = fabric ? vec2(local_position.x, local_position.y + local_position.z) : local_position.xz;
	float scale = fabric ? 320.0 : 260.0;
	float speckle = hash(floor(p * scale));
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	float visibility = 1.0 - smoothstep(0.002, 0.012, footprint);
	vec3 color = base_color.rgb * (1.0 + (speckle - 0.5) * 0.16 * visibility);
	if (fabric) {
		vec2 cell = floor(p * vec2(72.0, 50.0));
		float fleck = step(0.92, hash(cell));
		color = mix(color, vec3(0.43, 0.57, 0.59), fleck * visibility * 0.35);
	}
	ALBEDO = color;
	ROUGHNESS = fabric ? 0.92 : 0.82;
	SPECULAR = 0.23;
}
