shader_type canvas_item;

uniform bool outline_enabled = false;
uniform vec4 outline_color : source_color = vec4(0.25, 0.85, 1.0, 1.0);
uniform float glow_intensity : hint_range(0.0, 3.0) = 1.8;
uniform float pulse_speed : hint_range(0.0, 8.0) = 2.5;

void fragment() {
	vec4 base = texture(TEXTURE, UV);

	if (!outline_enabled) {
		COLOR = base;
		return;
	}

	// 透明像素才绘制描边，保留 sprite 原色
	if (base.a > 0.05) {
		COLOR = base;
		return;
	}

	vec2 px = TEXTURE_PIXEL_SIZE;

	// 8 方向向量（避免在循环内动态计算）
	vec2 d0 = vec2( px.x,  0.0);
	vec2 d1 = vec2(-px.x,  0.0);
	vec2 d2 = vec2( 0.0,   px.y);
	vec2 d3 = vec2( 0.0,  -px.y);
	vec2 d4 = vec2( px.x,  px.y);
	vec2 d5 = vec2(-px.x,  px.y);
	vec2 d6 = vec2( px.x, -px.y);
	vec2 d7 = vec2(-px.x, -px.y);

	// r=1：硬边描边
	float a1 = 0.0;
	a1 = max(a1, texture(TEXTURE, UV + d0).a);
	a1 = max(a1, texture(TEXTURE, UV + d1).a);
	a1 = max(a1, texture(TEXTURE, UV + d2).a);
	a1 = max(a1, texture(TEXTURE, UV + d3).a);
	a1 = max(a1, texture(TEXTURE, UV + d4).a);
	a1 = max(a1, texture(TEXTURE, UV + d5).a);
	a1 = max(a1, texture(TEXTURE, UV + d6).a);
	a1 = max(a1, texture(TEXTURE, UV + d7).a);

	// r=2：中层辉光
	float a2 = 0.0;
	a2 = max(a2, texture(TEXTURE, UV + d0 * 2.0).a);
	a2 = max(a2, texture(TEXTURE, UV + d1 * 2.0).a);
	a2 = max(a2, texture(TEXTURE, UV + d2 * 2.0).a);
	a2 = max(a2, texture(TEXTURE, UV + d3 * 2.0).a);
	a2 = max(a2, texture(TEXTURE, UV + d4 * 2.0).a);
	a2 = max(a2, texture(TEXTURE, UV + d5 * 2.0).a);
	a2 = max(a2, texture(TEXTURE, UV + d6 * 2.0).a);
	a2 = max(a2, texture(TEXTURE, UV + d7 * 2.0).a);

	// r=3：外层淡晕
	float a3 = 0.0;
	a3 = max(a3, texture(TEXTURE, UV + d0 * 3.0).a);
	a3 = max(a3, texture(TEXTURE, UV + d1 * 3.0).a);
	a3 = max(a3, texture(TEXTURE, UV + d2 * 3.0).a);
	a3 = max(a3, texture(TEXTURE, UV + d3 * 3.0).a);
	a3 = max(a3, texture(TEXTURE, UV + d4 * 3.0).a);
	a3 = max(a3, texture(TEXTURE, UV + d5 * 3.0).a);
	a3 = max(a3, texture(TEXTURE, UV + d6 * 3.0).a);
	a3 = max(a3, texture(TEXTURE, UV + d7 * 3.0).a);

	// 三层叠加：内圈实心 + 中层半透 + 外层淡晕
	float glow_a = a1 * 1.0 + (a2 - a1) * 0.55 + (a3 - a2) * 0.25;
	glow_a = clamp(glow_a, 0.0, 1.0);

	if (glow_a < 0.01) {
		COLOR = base;
		return;
	}

	// 呼吸脉冲：sin 调制亮度 [1.0, 1.0 + glow_intensity]
	float pulse = sin(TIME * pulse_speed) * 0.5 + 0.5;
	float brightness = 1.0 + pulse * glow_intensity;

	COLOR = vec4(outline_color.rgb * brightness, glow_a * outline_color.a);
}
