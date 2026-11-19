shader_type canvas_item;
render_mode blend_add;
// The headlight caught by the water's ripples: the same moving contour lines as water.gdshader, lit only
// where the beam falls on them and shimmering as the surface moves. It covers the water polygon only, so
// light shone onto the land never reflects.

uniform float scale = 95.0;
uniform vec2 apex = vec2(0.0);
uniform vec2 dir = vec2(1.0, 0.0);
uniform float len = 200.0;
uniform float wide = 200.0;
uniform float power = 0.0;
uniform vec4 col : source_color = vec4(1.0);

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

// How much of the beam reaches this point: matches the beam picture (Game._make_beam).
float beam(vec2 p) {
	vec2 d = p - apex;
	float u = dot(d, dir) / len;
	if (u <= 0.0 || u >= 1.0) {
		return 0.0;
	}
	float v = abs(dot(d, vec2(-dir.y, dir.x))) / (wide * 0.5);
	float spread = 0.2 + 0.8 * u;
	return (1.0 - smoothstep(0.45, 1.0, v / spread)) * pow(1.0 - u, 1.2) * smoothstep(0.0, 0.08, u);
}

void fragment() {
	float b = power > 0.0 ? beam(wpos) : 0.0;
	if (b <= 0.002) {
		discard;
	}
	vec2 p = wpos / scale;
	float t = TIME * 0.10;
	float n = noise(p + vec2(t, t * 0.6)) * 0.62 + noise(p * 2.1 - vec2(t * 1.3, t * 0.4)) * 0.38;
	float band = abs(fract(n * 4.5) - 0.5);
	float line = 1.0 - smoothstep(0.0, 0.08, band);
	// The surface glitters unevenly along each line as small waves pass.
	float sh = noise(wpos / 6.0 + vec2(TIME * 1.6, -TIME * 1.1));
	float glitter = 0.25 + 1.1 * smoothstep(0.45, 0.85, sh);
	float a = line * smoothstep(0.25, 0.6, n) * b * power * glitter;
	COLOR = vec4(col.rgb, clamp(a, 0.0, 1.0));
}
