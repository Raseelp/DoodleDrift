shader_type canvas_item;
// Mottled ground colour for the land around a lake.

uniform vec4 base : source_color = vec4(0.5, 0.6, 0.45, 1.0);
uniform vec4 dark : source_color = vec4(0.4, 0.5, 0.38, 1.0);

varying vec2 wpos;

void vertex() {
	wpos = VERTEX;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	float n = noise(wpos / 160.0) * 0.6 + noise(wpos / 48.0) * 0.4;
	float m = smoothstep(0.38, 0.72, n);
	COLOR = mix(base, dark, m * 0.85);
}
