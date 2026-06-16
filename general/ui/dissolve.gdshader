shader_type canvas_item;

uniform vec2 node_resolution = vec2(64.0, 64.0);

uniform float factor : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float width = 0.4;
// 擦除方向：0=从左到右，1=从右到左，2=从上到下，3=从下到上，4=径向从中心向外
uniform int direction = 4;

group_uniforms shape;
uniform sampler2D shape_texture;
uniform float shape_tiling = 0.4;
uniform float shape_feathering : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float shape_treshold : hint_range(0.0, 2.0, 0.01) = 1.0;

vec2 rotate(vec2 uv, vec2 pivot, float angle) {
	mat2 r = mat2(vec2(sin(angle), -cos(angle)), vec2(cos(angle), sin(angle)));
	uv -= pivot;
	uv = uv * r;
	uv += pivot;
	return uv;
}

void fragment() {
	float progress = mix(-width, 1.0, factor);
	float aspect = node_resolution.y / node_resolution.x;

	float dir_uv;
	if (direction == 1) {
		dir_uv = 1.0 - UV.x;
	} else if (direction == 2) {
		dir_uv = UV.y;
	} else if (direction == 3) {
		dir_uv = 1.0 - UV.y;
	} else if (direction == 4) {
		vec2 radial_uv = (UV - vec2(0.5)) * vec2(1.0, aspect);
		dir_uv = length(radial_uv) * 2.0;
	} else {
		dir_uv = UV.x;
	}

	float value = clamp((dir_uv - progress) / width, 0.0, 1.0);

	vec2 aspect_uv = ((UV - vec2(0.0, 0.5)) * vec2(1.0, aspect)) + vec2(0.0, 0.5);
	vec2 tiled_uv = mod(aspect_uv * shape_tiling, 1.0);
	float shape_value = 1.0 - texture(shape_texture, tiled_uv).r;

	shape_value = mix(shape_feathering * 0.5, 1.0 - shape_feathering * 0.5, shape_value);
	float shaped_gradient = smoothstep(value - (shape_feathering * 0.5), value + (shape_feathering * 0.5), shape_treshold - shape_value);

	// 保留原始贴图/文字内容，只用溶解蒙版控制 alpha
	COLOR.a *= shaped_gradient;
}
