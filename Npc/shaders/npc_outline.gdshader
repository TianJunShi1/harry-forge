shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;

	// 将 sprite 轮廓向外扩 1px：对当前像素及 8 方向邻居取最大 alpha
	float a = texture(TEXTURE, UV).a;
	a = max(a, texture(TEXTURE, UV + vec2( px.x,  0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x,  0.0)).a);
	a = max(a, texture(TEXTURE, UV + vec2( 0.0,   px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2( 0.0,  -px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2( px.x,  px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x,  px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2( px.x, -px.y)).a);
	a = max(a, texture(TEXTURE, UV + vec2(-px.x, -px.y)).a);

	COLOR = vec4(outline_color.rgb, a * outline_color.a);
}
