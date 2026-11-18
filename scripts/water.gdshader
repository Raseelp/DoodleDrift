shader_type canvas_item;
// Soft animated contour ripples drawn over the water bands.

uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.10;
uniform float scale = 95.0;

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
	vec2 p = wpos / scale;
	float t = TIME * 0.10;
	float n = noise(p + vec2(t, t * 0.6)) * 0.62 + noise(p * 2.1 - vec2(t * 1.3, t * 0.4)) * 0.38;
	float band = abs(fract(n * 4.5) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.06, band);
	float a = line * strength * smoothstep(0.25, 0.6, n);
	COLOR = vec4(tint.rgb, a);
}
