shader_type canvas_item;

uniform vec4 base_color : source_color;
uniform vec2 node_resolution;

uniform float factor : hint_range(0.0, 1.0, 0.01) = 0.54;
uniform float width = 0.4;
// 擦除方向：0=从左到右，1=从右到左，2=从上到下，3=从下到上，4=径向从中心向外
uniform int direction = 0;

group_uniforms shape;
uniform sampler2D shape_texture;
uniform float shape_tiling = 32.0;
uniform float shape_rotation = 0.0;
uniform vec2 shape_scroll = vec2(0.0);
uniform float shape_feathering : hint_range(0.0, 1.0, 0.01) = 0.00;
uniform float shape_treshold : hint_range(0.0, 2.0, 0.01) = 1.0;

vec2 rotate(vec2 uv, vec2 pivot, float angle)
{
	mat2 rotation = mat2(vec2(sin(angle), -cos(angle)),
						vec2(cos(angle), sin(angle)));
	uv -= pivot;
	uv = uv * rotation;
	uv += pivot;
	return uv;
}

void fragment() {
	float progress = mix(-width, 1.0, factor);
	float aspect = node_resolution.y / node_resolution.x;

	// 根据方向选择驱动轴
	float dir_uv;
	if (direction == 1) {
		dir_uv = 1.0 - UV.x;  // 从右到左
	} else if (direction == 2) {
		dir_uv = UV.y;         // 从上到下
	} else if (direction == 3) {
		dir_uv = 1.0 - UV.y;  // 从下到上
	} else if (direction == 4) {
		// 径向：以屏幕中心为原点，修正宽高比后算距离，使遮罩圆形而非椭圆
		vec2 radial_uv = (UV - vec2(0.5)) * vec2(1.0, aspect);
		dir_uv = length(radial_uv) * 2.0;
	} else {
		dir_uv = UV.x;         // 从左到右（默认）
	}

	float value = clamp((dir_uv - progress) / width, 0.0, 1.0);

	vec2 aspect_uv = ((UV - vec2(0.0, 0.5)) * vec2(1.0, aspect)) + vec2(0.0, 0.5);
	vec2 tiled_uv = rotate(mod((aspect_uv + vec2(TIME) * shape_scroll) * shape_tiling, 1.0), vec2(0.5), radians(shape_rotation));
	float shape_value = 1.0 - texture(shape_texture, tiled_uv).r;

	shape_value = mix(shape_feathering * 0.5, 1.0 - shape_feathering * 0.5, shape_value);
	float shaped_gradient = smoothstep(value - (shape_feathering * 0.5), value + (shape_feathering * 0.5), shape_treshold - shape_value);

	COLOR.rgb = base_color.rgb;
	COLOR.a = shaped_gradient;
}
