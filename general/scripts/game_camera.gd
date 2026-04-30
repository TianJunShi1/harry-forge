class_name GameCamera2D extends Camera2D

## 关卡级摄像机。把它放在关卡场景里，不要放进 Player。
##
## 功能：
##   • 平滑跟随目标（指数衰减，帧率无关）
##   • 软边界（靠近边界自动减速，不硬撞）
##   • 区域栈（CameraZone 进入时 push，退出时 pop，最高优先级生效）
##   • 隐藏房间锁定：进入时相机直接 smoothstep 插值到房间中心（绕过 follow smoothing 消除双重缓动）；
##     退出时相机留在原位，follow smoothing 自然追上玩家，不产生任何跳变
##   • Zoom 区域间平滑过渡
##   • 临时聚焦点（add_focus_point / remove_focus_point，供剧情/POI 使用）

# ============================================================================
# 编辑器参数
# ============================================================================

@export_group("Follow")
## 跟随的目标节点（通常是 Player）；留空则自动查找 "player" 组
@export var follow_target: Node2D
## 跟随平滑度，值越大反应越快（典型范围 2~8）
@export_range(0.1, 20.0, 0.1) var follow_smoothing: float = 3.0

@export_group("Look Ahead")
## 是否启用前视偏移
@export var look_ahead_enabled: bool = true
## 前视最大距离（像素）
@export_range(0.0, 200.0, 1.0) var look_ahead_distance: float = 24.0
## 转向时前视建立速度
@export_range(0.1, 20.0, 0.1) var look_ahead_turn_speed: float = 3.0
## 停止移动后前视归零速度（建议比 turn_speed 慢）
@export_range(0.1, 20.0, 0.1) var look_ahead_return_speed: float = 1.2
## 触发前视的最低速度（像素/秒）
@export_range(0.0, 200.0, 1.0) var look_ahead_velocity_threshold: float = 30.0

@export_group("Bounds")
## 软边界宽度（像素）。0 = 硬 clamp，>0 = 靠近边界时减速
@export_range(0.0, 300.0, 1.0) var bounds_softness: float = 60.0

@export_group("Zoom")
## 无 CameraZone 覆盖时的默认 zoom
@export var default_zoom: Vector2 = Vector2.ONE
## Zoom 切换时的平滑速度
@export_range(0.1, 20.0, 0.1) var zoom_smoothing: float = 3.0

@export_group("Debug")
@export var draw_debug: bool = false


# ============================================================================
# 运行时状态
# ============================================================================

var _zone_stack: Array = []
var _zone_order_counter: int = 0

# 目标状态（来自最高优先级 zone）
var _target_bounds: Rect2 = Rect2()
var _target_has_bounds: bool = false
var _target_lock_to_center: bool = false
var _target_lock_center: Vector2 = Vector2.ZERO
var _target_zoom: Vector2 = Vector2.ONE

# 边界过渡（smoothstep 时间驱动）
var _displayed_bounds: Rect2 = Rect2()
var _bounds_tween_t: float = 1.0
var _bounds_tween_duration: float = 0.0
var _bounds_tween_from: Rect2 = Rect2()

# Zoom 显示值（在 _process 中指数平滑至 _target_zoom）
var _displayed_zoom: Vector2 = Vector2.ONE

# 进入锁定的位置过渡：直接驱动 _smoothed_position，绕过 follow smoothing
var _lock_transition_active: bool = false
var _lock_transition_from: Vector2 = Vector2.ZERO
var _lock_tween_t: float = 1.0
var _lock_tween_duration: float = 0.4

# 跟随
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
	if follow_target == null:
		follow_target = get_tree().get_first_node_in_group("player") as Node2D
	if follow_target:
		_smoothed_position = follow_target.global_position
		global_position = _smoothed_position
		_initialized = true


func _process(delta: float) -> void:
	# 延迟加载场景时 Player 比 Camera 晚 ready，这里重试自动发现
	if not is_instance_valid(follow_target):
		follow_target = get_tree().get_first_node_in_group("player") as Node2D
	if not is_instance_valid(follow_target):
		return

	if not _initialized:
		# 场景加载时若当前应处于锁定状态，直接快照到锁定中心
		_smoothed_position = _target_lock_center if _target_lock_to_center else follow_target.global_position
		global_position = _smoothed_position
		_initialized = true

	_advance_bounds_transition(delta)
	_update_focus_points(delta)

	if _lock_transition_active:
		# 进入隐藏房间：smoothstep 直接插值相机至锁定中心。
		# 旧方案对"期望目标"做混合后再 follow-smooth，相当于两层缓动叠加，
		# 导致运动感非线性（先快后慢/先慢后快）。此处绕过 follow smoothing。
		_lock_tween_t = minf(_lock_tween_t + delta / _lock_tween_duration, 1.0)
		_smoothed_position = _lock_transition_from.lerp(_target_lock_center, _smoothstep01(_lock_tween_t))
		if _lock_tween_t >= 1.0:
			_lock_transition_active = false
	elif _target_lock_to_center:
		# 完全锁定：直接持有中心（防止 zone 变更时 center 漂移）
		_smoothed_position = _target_lock_center
	else:
		# 正常跟随模式；退出锁定后 _smoothed_position 停在锁定中心，
		# exponential lerp 会自然地把相机拉回玩家，不需要额外 tween
		var target_pos := _compute_desired_position(delta)
		var t := 1.0 - exp(-follow_smoothing * delta)
		_smoothed_position = _smoothed_position.lerp(target_pos, t)

	# Zoom 指数平滑
	_displayed_zoom = _displayed_zoom.lerp(_target_zoom, 1.0 - exp(-zoom_smoothing * delta))

	# 硬边界安全网（target 已被软限过，这里几乎不触发）
	# lock 过渡期间跳过：_displayed_bounds 同步在收缩，clamp 会打断 smoothstep 曲线
	if _target_has_bounds and not _lock_transition_active:
		_smoothed_position = _hard_clamp_to_bounds(_smoothed_position, _displayed_bounds, _displayed_zoom)

	global_position = _smoothed_position
	zoom = _displayed_zoom

	if draw_debug:
		queue_redraw()


# ============================================================================
# 公开 API：CameraZone 调用
# ============================================================================

## 进入一个区域时调用。config 字段：priority, bounds, lock_to_center, zoom_override, transition_duration
func push_zone(zone_id: int, config: Dictionary) -> void:
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


## 添加临时聚焦点。weight=1.0 时和玩家各占 50%，blend_in 为淡入时长（秒）。
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


## 更新聚焦点位置（目标移动时每帧调用）。
func update_focus_point(focus_id: int, world_position: Vector2) -> void:
	if _focus_points.has(focus_id):
		_focus_points[focus_id]["position"] = world_position


## 淡出并移除聚焦点。blend_out 为淡出时长（秒）。
func remove_focus_point(focus_id: int, blend_out: float = 0.5) -> void:
	if not _focus_points.has(focus_id):
		return
	_focus_points[focus_id]["weight_target"] = 0.0
	_focus_points[focus_id]["fade_speed"] = 1.0 / maxf(blend_out, 0.0001)


## 立即跳到玩家位置（复活/瞬移用），跳过所有平滑。
func snap_to_target() -> void:
	if not is_instance_valid(follow_target):
		return
	_smoothed_position = follow_target.global_position
	global_position = _smoothed_position
	_lock_transition_active = false
	_lock_tween_t = 1.0
	_bounds_tween_t = 1.0
	_displayed_zoom = _target_zoom
	_displayed_bounds = _target_bounds
	_look_ahead_value = 0.0


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
		_target_zoom = default_zoom
		return

	var top: Dictionary = _zone_stack.back()
	var duration: float = float(top.get("transition_duration", 0.4))
	var bounds: Rect2 = top.get("bounds", Rect2())
	var has_bounds: bool = bounds.size != Vector2.ZERO
	var lock_to_center: bool = bool(top.get("lock_to_center", false))
	var lock_center: Vector2 = bounds.position + bounds.size * 0.5
	var zoom_override: Vector2 = top.get("zoom_override", Vector2.ZERO)

	_begin_bounds_transition(bounds, has_bounds, duration)
	_begin_lock_transition(lock_to_center, lock_center, duration)
	_target_zoom = zoom_override if zoom_override != Vector2.ZERO else default_zoom


func _begin_bounds_transition(new_bounds: Rect2, has_bounds: bool, duration: float) -> void:
	if has_bounds and not _target_has_bounds:
		# 首次进入有边界区域：直接吸附，避免从 Rect2() 大小拉过来
		_displayed_bounds = new_bounds
		_bounds_tween_t = 1.0
	else:
		_bounds_tween_from = _displayed_bounds
		_bounds_tween_duration = max(duration, 0.0001)
		_bounds_tween_t = 0.0
	_target_bounds = new_bounds
	_target_has_bounds = has_bounds


func _begin_lock_transition(lock_to_center: bool, center: Vector2, duration: float) -> void:
	_target_lock_to_center = lock_to_center
	_target_lock_center = center
	if lock_to_center:
		if _initialized:
			# 从当前相机位置直接 smoothstep 到锁定中心，不经过 follow smoothing
			_lock_transition_active = true
			_lock_transition_from = _smoothed_position
			_lock_tween_t = 0.0
			_lock_tween_duration = maxf(duration, 0.0001)
		# 未初始化时跳过过渡，_process 第一帧会直接快照到 lock_center
		_look_ahead_value = 0.0
		_facing_target = 0.0
	else:
		# 退出锁定：_smoothed_position 留在当前位置（通常是 lock_center 附近），
		# follow smoothing 负责将相机平滑地引导回玩家，无需额外 tween
		_lock_transition_active = false
		_look_ahead_value = 0.0


# ============================================================================
# 内部：每帧过渡推进
# ============================================================================

func _advance_bounds_transition(delta: float) -> void:
	if _bounds_tween_t < 1.0:
		_bounds_tween_t = minf(_bounds_tween_t + delta / _bounds_tween_duration, 1.0)
		var s := _smoothstep01(_bounds_tween_t)
		_displayed_bounds = Rect2(
			_bounds_tween_from.position.lerp(_target_bounds.position, s),
			_bounds_tween_from.size.lerp(_target_bounds.size, s)
		)


# ============================================================================
# 内部：每帧位置计算（仅 follow 模式使用）
# ============================================================================

func _compute_desired_position(delta: float) -> Vector2:
	var target_pos: Vector2 = follow_target.global_position

	# 前视偏移
	if look_ahead_enabled:
		var intent := _read_facing_intent()
		_facing_target = intent
		var speed: float = look_ahead_turn_speed if intent != 0.0 else look_ahead_return_speed
		var t := 1.0 - exp(-speed * delta)
		_look_ahead_value = lerpf(_look_ahead_value, _facing_target, t)
		target_pos.x += _look_ahead_value * look_ahead_distance

	# 聚焦点权重混合（加权平均，玩家自身权重恒为 1）
	if not _focus_points.is_empty():
		var total_weight: float = 1.0
		var weighted: Vector2 = target_pos
		for fp in _focus_points.values():
			var w: float = fp["weight_current"]
			if w > 0.0001:
				weighted += fp["position"] * w
				total_weight += w
		target_pos = weighted / total_weight

	# 软边界减速
	if _target_has_bounds:
		target_pos = _soft_clamp_to_bounds(target_pos, _displayed_bounds, _displayed_zoom)

	return target_pos


func _read_facing_intent() -> float:
	if follow_target.has_method("get_camera_facing_intent"):
		return follow_target.get_camera_facing_intent()
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
		if fp["weight_target"] <= 0.0 and fp["weight_current"] < 0.001:
			to_remove.append(id)
	for id in to_remove:
		_focus_points.erase(id)


# ============================================================================
# 内部：边界数学
# ============================================================================

func _get_camera_half_view(zoom_value: Vector2) -> Vector2:
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
	if min_val > max_val:
		return (min_val + max_val) * 0.5
	if softness <= 0.0:
		return clampf(value, min_val, max_val)
	if value <= min_val:
		return min_val
	if value >= max_val:
		return max_val
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
# Debug 可视化
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
