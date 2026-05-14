shader_type canvas_item;

uniform float grain_amount : hint_range(0.0, 0.2) = 0.035;
uniform float grain_speed  : hint_range(0.0, 10.0) = 2.0;
uniform float vignette_strength : hint_range(0.0, 6.0) = 2.8;

float rand(vec2 uv) {
	return fract(sin(dot(uv, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	// 胶片颗粒：TIME 偏移让每帧噪声不同，floor 保持像素对齐
	vec2 g_uv = floor(UV * vec2(1280.0, 720.0) + TIME * grain_speed * 17.0);
	float grain = (rand(g_uv) * 2.0 - 1.0) * grain_amount;
	col.rgb += grain;

	// 暗角：二次方衰减，中心不变，边角渐暗
	vec2 c = UV - vec2(0.5);
	float vignette = 1.0 - dot(c, c) * vignette_strength;
	col.rgb *= clamp(vignette, 0.0, 1.0);

	COLOR = col;
}
