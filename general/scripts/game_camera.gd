class_name GameCamera2D extends Camera2D

## 关卡级摄像机。把它放在关卡场景里，不要放进 Player。
##
## 功能：
##   • 平滑跟随目标（可调节柔和度）
##   • 软边界（靠近边界自动减速，不硬撞）
##   • 区域栈（CameraZone 进入时 push，退出时 pop，最高优先级生效）
##   • 隐藏房间锁定模式（角色进入时摄像机锁到房间中心，退出丝滑过渡）
##   • Zoom 在区域间平滑过渡
##   • 临时聚焦点（add_focus_point / remove_focus_point，供剧情/POI 使用）
##
## 用法：
##   1. 在关卡里实例化 game_camera.tscn
##   2. 在 Inspector 里把 follow_target 指到 Player 节点
##   3. 摆放 CameraZone 划定房间边界（详见 camera_zone.gd）

# ============================================================================
# 编辑器参数
# ============================================================================

@export_group("Follow")
## 跟随的目标节点（通常是 Player）
@export var follow_target: Node2D
## 跟随平滑度。值越大反应越快；典型范围 2~8
@export_range(0.1, 20.0, 0.1) var follow_smoothing: float = 4.0

@export_group("Look Ahead")
## 是否启用前视：朝向移动方向偏移摄像机，让玩家看见前方
@export var look_ahead_enabled: bool = true
## 前视最大距离（像素）
@export_range(0.0, 200.0, 1.0) var look_ahead_distance: float = 24.0
## 转向时前视生效的速度
@export_range(0.1, 20.0, 0.1) var look_ahead_turn_speed: float = 3.0
## 停止移动后前视回中的速度（建议比 turn_speed 慢，回得不那么急）
@export_range(0.1, 20.0, 0.1) var look_ahead_return_speed: float = 1.2
## 触发前视的最低速度（像素/秒）。低于此值视为停止
@export_range(0.0, 200.0, 1.0) var look_ahead_velocity_threshold: float = 30.0

@export_group("Bounds")
## 软边界宽度（像素）。摄像机靠近边界 softness 距离时开始减速。
## 0 = 硬边界（直接 clamp），>0 = 软减速
@export_range(0.0, 300.0, 1.0) var bounds_softness: float = 60.0

@export_group("Zoom")
## 默认 zoom（无 CameraZone 覆盖时使用）
@export var default_zoom: Vector2 = Vector2.ONE
## 切换 zoom 时的平滑速度
@export_range(0.1, 20.0, 0.1) var zoom_smoothing: float = 3.0

@export_group("Debug")
@export var draw_debug: bool = false


# ============================================================================
# 运行时状态（私有）
# ============================================================================

# 区域栈：每个元素是一个 ZoneContext 字典
var _zone_stack: Array = []
var _zone_order_counter: int = 0

# 当前“目标”状态（来自最高优先级 zone）
var _target_bounds: Rect2 = Rect2()
var _target_has_bounds: bool = false
var _target_lock_to_center: bool = false
var _target_lock_center: Vector2 = Vector2.ZERO
var _target_zoom: Vector2 = Vector2.ONE

# 当前“显示”状态（平滑过渡到目标值）
var _displayed_bounds: Rect2 = Rect2()
var _displayed_lock_weight: float = 0.0   # 0 = 完全跟随玩家，1 = 完全锁定房间中心
var _displayed_lock_center: Vector2 = Vector2.ZERO
var _displayed_zoom: Vector2 = Vector2.ONE

# 时间驱动的过渡（保证“N 秒过渡完毕”的语义）
var _bounds_tween_t: float = 1.0       # 0 = 刚切换；1 = 过渡完毕
var _bounds_tween_duration: float = 0.0
var _bounds_tween_from: Rect2 = Rect2()

var _lock_tween_t: float = 1.0
var _lock_tween_duration: float = 0.0
var _lock_tween_from_weight: float = 0.0
var _lock_tween_from_center: Vector2 = Vector2.ZERO

var _zoom_tween_t: float = 1.0
var _zoom_tween_duration: float = 0.0
var _zoom_tween_from: Vector2 = Vector2.ONE

# 跟随相关
var _smoothed_position: Vector2
var _facing_target: float = 0.0
var _look_ahead_value: float = 0.0
var _initialized: bool = false

# 临时聚焦点：id -> { position, weight_target, weight_current, fade_speed }
var _focus_points: Dictionary = {}


# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	position_smoothing_enabled = false
	make_current()

	_target_zoom = default_zoom
	_displayed_zoom = default_zoom
	zoom = default_zoom

	# Inspector 未指定时，自动查找 "player" 组的第一个成员
	if follow_target == null:
		follow_target = get_tree().get_first_node_in_group("player") as Node2D

	if follow_target:
		_smoothed_position = follow_target.global_position
		global_position = _smoothed_position
		_initialized = true


func _process(delta: float) -> void:
	# 延迟加载场景时，Player 可能比 Camera 晚 ready，这里重试自动发现
	if not is_instance_valid(follow_target):
		follow_target = get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(follow_target):
		return

	if not _initialized:
		_smoothed_position = follow_target.global_position
		global_position = _smoothed_position
		_initialized = true

	_advance_transitions(delta)
	_update_focus_points(delta)

	var target_pos := _compute_desired_position(delta)

	# 平滑追踪
	var t := 1.0 - exp(-follow_smoothing * delta)
	_smoothed_position = _smoothed_position.lerp(target_pos, t)

	# 平滑 zoom
	var zt := 1.0 - exp(-zoom_smoothing * delta)
	_displayed_zoom = _displayed_zoom.lerp(_target_zoom, zt)

	# 应用到摄像机
	# 边界硬夹作为安全网（target 已经被软限过，这里几乎不会真的夹）
	if _target_has_bounds:
		_smoothed_position = _hard_clamp_to_bounds(_smoothed_position, _displayed_bounds, _displayed_zoom)

	global_position = _smoothed_position
	zoom = _displayed_zoom

	if draw_debug:
		queue_redraw()


# ============================================================================
# 公开 API：CameraZone 调用
# ============================================================================

## 进入一个区域时调用。zone_id 通常用 get_instance_id()。
## config 字段：
##   priority: int                   优先级（越大越靠前），同优先级按进入顺序
##   bounds: Rect2                   摄像机活动边界（全局坐标）
##   lock_to_center: bool            是否锁定到 bounds 中心（隐藏房间用）
##   zoom_override: Vector2          要切换到的 zoom；如果是 Vector2.ZERO 则保持 default_zoom
##   transition_duration: float      过渡时长（秒）
func push_zone(zone_id: int, config: Dictionary) -> void:
	# 同一个 zone 重复 push 时先移除旧记录
	for i in range(_zone_stack.size() - 1, -1, -1):
		if _zone_stack[i]["id"] == zone_id:
			_zone_stack.remove_at(i)

	_zone_order_counter += 1
	var entry: Dictionary = config.duplicate()
	entry["id"] = zone_id
	entry["order"] = _zone_order_counter
	if not entry.has("priority"):
		entry["priority"] = 0
	if not entry.has("transition_duration"):
		entry["transition_duration"] = 0.4
	_zone_stack.append(entry)
	_resort_stack()
	_recompute_active_zone()


## 退出一个区域时调用。
func pop_zone(zone_id: int) -> void:
	for i in range(_zone_stack.size() - 1, -1, -1):
		if _zone_stack[i]["id"] == zone_id:
			_zone_stack.remove_at(i)
			break
	_recompute_active_zone()


## 添加一个聚焦点：摄像机会在玩家位置和 position 之间按 weight 加权。
## weight = 1.0 时和玩家平分（各 50%）；weight = 2.0 时聚焦点占 2/3。
## blend_in 是聚焦点权重淡入用时（秒）。
func add_focus_point(focus_id: int, world_position: Vector2, weight: float = 1.0, blend_in: float = 0.5) -> void:
	var fade_speed := 1.0 / maxf(blend_in, 0.0001)
	if _focus_points.has(focus_id):
		_focus_points[focus_id]["position"] = world_position
		_focus_points[focus_id]["weight_target"] = weight
		_focus_points[focus_id]["fade_speed"] = fade_speed
	else:
		_focus_points[focus_id] = {
			"position": world_position,
			"weight_target": weight,
			"weight_current": 0.0,
			"fade_speed": fade_speed,
		}


## 更新聚焦点位置（聚焦的物体在移动时调用）
func update_focus_point(focus_id: int, world_position: Vector2) -> void:
	if _focus_points.has(focus_id):
		_focus_points[focus_id]["position"] = world_position


## 移除聚焦点：把 weight_target 设为 0，淡出后真正删除
func remove_focus_point(focus_id: int, blend_out: float = 0.5) -> void:
	if not _focus_points.has(focus_id):
		return
	_focus_points[focus_id]["weight_target"] = 0.0
	_focus_points[focus_id]["fade_speed"] = 1.0 / maxf(blend_out, 0.0001)


## 立即切到玩家位置（瞬移用），跳过平滑。可在玩家死亡复活时调用。
func snap_to_target() -> void:
	if not is_instance_valid(follow_target):
		return
	_smoothed_position = follow_target.global_position
	global_position = _smoothed_position
	_displayed_lock_weight = 0.0 if not _target_lock_to_center else 1.0
	_lock_tween_t = 1.0
	_bounds_tween_t = 1.0
	_zoom_tween_t = 1.0
	_displayed_zoom = _target_zoom
	_displayed_bounds = _target_bounds


# ============================================================================
# 内部：区域栈解析
# ============================================================================

func _resort_stack() -> void:
	_zone_stack.sort_custom(func(a, b):
		if a["priority"] == b["priority"]:
			return a["order"] < b["order"]
		return a["priority"] < b["priority"]
	)


func _recompute_active_zone() -> void:
	if _zone_stack.is_empty():
		_begin_bounds_transition(Rect2(), false, 0.4)
		_begin_lock_transition(false, Vector2.ZERO, 0.4)
		_begin_zoom_transition(default_zoom, 0.4)
		return

	var top: Dictionary = _zone_stack.back()
	var duration: float = float(top.get("transition_duration", 0.4))
	var bounds: Rect2 = top.get("bounds", Rect2())
	var has_bounds: bool = bounds.size != Vector2.ZERO
	var lock_to_center: bool = bool(top.get("lock_to_center", false))
	var lock_center: Vector2 = bounds.position + bounds.size * 0.5
	var zoom_override: Vector2 = top.get("zoom_override", Vector2.ZERO)
	var target_zoom_value: Vector2 = zoom_override if zoom_override != Vector2.ZERO else default_zoom

	_begin_bounds_transition(bounds, has_bounds, duration)
	_begin_lock_transition(lock_to_center, lock_center, duration)
	_begin_zoom_transition(target_zoom_value, duration)


func _begin_bounds_transition(new_bounds: Rect2, has_bounds: bool, duration: float) -> void:
	# 第一次设置边界时直接吸附，不做过渡，避免开场从 0 大小拉过来
	if has_bounds and not _target_has_bounds:
		_displayed_bounds = new_bounds
		_bounds_tween_t = 1.0
	else:
		_bounds_tween_from = _displayed_bounds
		_bounds_tween_duration = max(duration, 0.0001)
		_bounds_tween_t = 0.0

	_target_bounds = new_bounds
	_target_has_bounds = has_bounds


func _begin_lock_transition(lock_to_center: bool, center: Vector2, duration: float) -> void:
	_lock_tween_from_weight = _displayed_lock_weight
	_lock_tween_from_center = _displayed_lock_center
	_lock_tween_duration = max(duration, 0.0001)
	_lock_tween_t = 0.0

	_target_lock_to_center = lock_to_center
	_target_lock_center = center


func _begin_zoom_transition(new_zoom: Vector2, duration: float) -> void:
	_zoom_tween_from = _displayed_zoom
	_zoom_tween_duration = max(duration, 0.0001)
	_zoom_tween_t = 0.0
	_target_zoom = new_zoom


func _advance_transitions(delta: float) -> void:
	# 边界过渡
	if _bounds_tween_t < 1.0:
		_bounds_tween_t = min(_bounds_tween_t + delta / _bounds_tween_duration, 1.0)
		var s := _smoothstep01(_bounds_tween_t)
		_displayed_bounds = Rect2(
			_bounds_tween_from.position.lerp(_target_bounds.position, s),
			_bounds_tween_from.size.lerp(_target_bounds.size, s)
		)

	# 锁定权重过渡
	if _lock_tween_t < 1.0:
		_lock_tween_t = min(_lock_tween_t + delta / _lock_tween_duration, 1.0)
		var s := _smoothstep01(_lock_tween_t)
		var target_weight: float = 1.0 if _target_lock_to_center else 0.0
		_displayed_lock_weight = lerpf(_lock_tween_from_weight, target_weight, s)
		_displayed_lock_center = _lock_tween_from_center.lerp(_target_lock_center, s)
	else:
		_displayed_lock_center = _target_lock_center

	# Zoom 过渡（注意：实际 zoom 平滑在 _process 里 lerp 来做，这里只更新 _target_zoom）
	if _zoom_tween_t < 1.0:
		_zoom_tween_t = min(_zoom_tween_t + delta / _zoom_tween_duration, 1.0)


# ============================================================================
# 内部：每帧位置计算
# ============================================================================

func _compute_desired_position(delta: float) -> Vector2:
	var target_pos: Vector2 = follow_target.global_position

	# 1. 前视偏移
	if look_ahead_enabled:
		var intent := _read_facing_intent()
		_facing_target = intent
		var speed: float = look_ahead_turn_speed if intent != 0.0 else look_ahead_return_speed
		var t := 1.0 - exp(-speed * delta)
		_look_ahead_value = lerpf(_look_ahead_value, _facing_target, t)
		target_pos.x += _look_ahead_value * look_ahead_distance

	# 2. 聚焦点权重混合
	if not _focus_points.is_empty():
		var total_weight: float = 1.0  # 玩家自身权重 = 1
		var weighted: Vector2 = target_pos
		for fp in _focus_points.values():
			var w: float = fp["weight_current"]
			if w > 0.0001:
				weighted += fp["position"] * w
				total_weight += w
		target_pos = weighted / total_weight

	# 3. 房间锁定混合（隐藏房间）
	if _displayed_lock_weight > 0.0001:
		target_pos = target_pos.lerp(_displayed_lock_center, _displayed_lock_weight)

	# 4. 软边界减速
	if _target_has_bounds:
		target_pos = _soft_clamp_to_bounds(target_pos, _displayed_bounds, _displayed_zoom)

	return target_pos


func _read_facing_intent() -> float:
	# 优先用目标节点提供的接口（更准确，可以反映按键意图）
	if follow_target.has_method("get_camera_facing_intent"):
		return follow_target.get_camera_facing_intent()
	# 回退：根据 velocity.x 推断
	if "velocity" in follow_target:
		var vx: float = follow_target.velocity.x
		if absf(vx) < look_ahead_velocity_threshold:
			return 0.0
		return signf(vx)
	return 0.0


func _update_focus_points(delta: float) -> void:
	var to_remove: Array = []
	for id in _focus_points.keys():
		var fp: Dictionary = _focus_points[id]
		var t := 1.0 - exp(-fp["fade_speed"] * delta)
		fp["weight_current"] = lerpf(fp["weight_current"], fp["weight_target"], t)
		# 已淡出且 target 是 0 → 真正删除
		if fp["weight_target"] <= 0.0 and fp["weight_current"] < 0.001:
			to_remove.append(id)
	for id in to_remove:
		_focus_points.erase(id)


# ============================================================================
# 内部：边界数学
# ============================================================================

func _get_camera_half_view(zoom_value: Vector2) -> Vector2:
	# 摄像机在世界里看到的尺寸 = viewport_size * zoom（注意 Camera2D 的 zoom 是“缩放系数”，
	# 而不是 “zoom 倍率”——zoom < 1 时画面被放大，zoom > 1 时画面被缩小）
	# 所以视图尺寸 = viewport_size / zoom_factor，但 Camera2D 的 zoom 字段意义比较绕：
	# 实测：Godot 4 的 Camera2D.zoom，> 1 = 放大（看到更少），< 1 = 缩小（看到更多）。
	# 即 视图尺寸 = viewport_size / zoom。
	var viewport_size := get_viewport_rect().size
	if zoom_value.x <= 0.0 or zoom_value.y <= 0.0:
		return viewport_size * 0.5
	return Vector2(viewport_size.x / zoom_value.x, viewport_size.y / zoom_value.y) * 0.5


func _soft_clamp_to_bounds(pos: Vector2, bounds: Rect2, zoom_value: Vector2) -> Vector2:
	var half := _get_camera_half_view(zoom_value)
	var min_pos := bounds.position + half
	var max_pos := bounds.end - half

	pos.x = _soft_limit_axis(pos.x, min_pos.x, max_pos.x, bounds_softness)
	pos.y = _soft_limit_axis(pos.y, min_pos.y, max_pos.y, bounds_softness)
	return pos


func _hard_clamp_to_bounds(pos: Vector2, bounds: Rect2, zoom_value: Vector2) -> Vector2:
	var half := _get_camera_half_view(zoom_value)
	var min_pos := bounds.position + half
	var max_pos := bounds.end - half

	if min_pos.x <= max_pos.x:
		pos.x = clampf(pos.x, min_pos.x, max_pos.x)
	else:
		pos.x = (min_pos.x + max_pos.x) * 0.5

	if min_pos.y <= max_pos.y:
		pos.y = clampf(pos.y, min_pos.y, max_pos.y)
	else:
		pos.y = (min_pos.y + max_pos.y) * 0.5

	return pos


func _soft_limit_axis(value: float, min_val: float, max_val: float, softness: float) -> float:
	# 边界比视图还小：直接居中
	if min_val > max_val:
		return (min_val + max_val) * 0.5
	# 无软边界：硬 clamp
	if softness <= 0.0:
		return clampf(value, min_val, max_val)
	# 已经在外侧：吸附到边界
	if value <= min_val:
		return min_val
	if value >= max_val:
		return max_val
	# 在软区内：用 smoothstep 减速逼近
	var soft := minf(softness, (max_val - min_val) * 0.5)
	if value < min_val + soft:
		var t := (value - min_val) / soft
		t = _smoothstep01(t)
		return lerpf(min_val, value, t)
	if value > max_val - soft:
		var t := (max_val - value) / soft
		t = _smoothstep01(t)
		return lerpf(max_val, value, t)
	return value


func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# ============================================================================
# Debug 可视化（按需打开）
# ============================================================================

func _draw() -> void:
	if not draw_debug:
		return
	if _target_has_bounds:
		var local_rect := Rect2(_displayed_bounds.position - global_position, _displayed_bounds.size)
		draw_rect(local_rect, Color(1, 1, 0, 0.6), false, 2.0)
	for fp in _focus_points.values():
		var local_pos: Vector2 = fp["position"] - global_position
		draw_circle(local_pos, 6.0, Color(0.4, 1.0, 0.4, fp["weight_current"]))
