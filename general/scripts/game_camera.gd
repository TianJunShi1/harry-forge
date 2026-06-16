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
## 玩家下落时 y 轴的"追赶"平滑度（仅在 velocity.y > 阈值时生效，沿正常 follow_smoothing 线性过渡到此值，
## 解决跳起来后高速坠落相机跟不上的问题；不影响上升 / 水平 / 静止时的手感）
@export_range(0.1, 30.0, 0.1) var fall_catch_up_smoothing: float = 9.0
## 启动 fall catch-up 的下落速度阈值（像素/秒）。velocity.y 超过此值开始混入 fall_catch_up_smoothing
@export_range(0.0, 600.0, 1.0) var fall_catch_up_velocity_threshold: float = 120.0
## 完全切换到 fall_catch_up_smoothing 所需的"超出阈值"速度跨度（像素/秒），用于线性过渡避免突变
@export_range(1.0, 800.0, 1.0) var fall_catch_up_ramp: float = 200.0

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

@export_group("Framing")
## 摄像机相对玩家的垂直偏移（像素）。负值=画面整体下移，玩家在屏幕下半（看到更多上方）。
## lock 模式下自动失效（房间中心由 zone 决定）。
@export_range(-200.0, 200.0, 1.0) var vertical_offset: float = -32.0
## 是否启用视线偏移（玩家静止按 W/S 时镜头上/下平移）
@export var look_y_enabled: bool = true
## 上/下观察时镜头最大垂直位移（游戏像素）
@export_range(0.0, 300.0, 1.0) var look_y_distance: float = 48.0
## 按键后偏移建立速度（值越小越慢/越有重量感，典型 1~3）
@export_range(0.1, 20.0, 0.1) var look_y_engage_speed: float = 1.5
## 松键后回中速度（建议比 engage 快，让回弹干脆）
@export_range(0.1, 20.0, 0.1) var look_y_return_speed: float = 3.0

@export_group("Dead Zone")
## 死区宽度（像素）。X 轴：目标在此范围内水平移动相机不跟随。0 = 禁用
@export_range(0.0, 200.0, 1.0) var dead_zone_width: float = 0.0
## 死区高度（像素）。Y 轴：目标在此范围内垂直移动相机不跟随。0 = 禁用
@export_range(0.0, 200.0, 1.0) var dead_zone_height: float = 0.0

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
# 常量
# ============================================================================

# 浮点比较 / 时长除零防护通用阈值
const EPSILON : float = 0.0001
# focus point 淡出剔除阈值（独立，因为视觉敏感度低，可以更宽松）
const FOCUS_FADE_OUT_EPSILON : float = 0.001


# ============================================================================
# 运行时状态
# ============================================================================

var _zone_stack: Array = []
var _zone_order_counter: int = 0
# follow_target 失效时是否已挂上 node_added 监听等待玩家加入树
var _player_search_pending: bool = false
# bounds 过渡是否还在跑；过渡结束后置 false 避免每帧重算 lerp
var _bounds_tween_active: bool = false

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

# Zoom 显示值（在 _process 中指数平滑至 _target_zoom，然后写入 Camera2D.zoom）
var displayed_zoom: Vector2 = Vector2.ONE

# 进入锁定的位置过渡：直接驱动 _smoothed_position，绕过 follow smoothing
var _lock_transition_active: bool = false
var _lock_transition_from: Vector2 = Vector2.ZERO
var _lock_tween_t: float = 1.0
var _lock_tween_duration: float = 0.4

# 跟随
var _smoothed_position: Vector2
var _facing_target: float = 0.0
var _look_ahead_value: float = 0.0
var _look_y_value: float = 0.0
var _initialized: bool = false

## canvas-items 架构下相机直接使用浮点位置，亚像素平滑由原生渲染保证，无需 subpixel_offset。

# 临时聚焦点：id -> { position, weight_target, weight_current, fade_speed }
var _focus_points: Dictionary = {}


# ============================================================================
# 生命周期
# ============================================================================

func _ready() -> void:
	position_smoothing_enabled = false
	make_current()
	_target_zoom = default_zoom
	displayed_zoom = default_zoom
	zoom = default_zoom
	if follow_target == null:
		follow_target = get_tree().get_first_node_in_group("player") as Node2D
	if follow_target:
		_smoothed_position = follow_target.global_position + Vector2(0, vertical_offset)
		global_position = _smoothed_position
		_initialized = true
	else:
		_begin_player_search()


## 等待 "player" 组节点加入场景树。第一次失败后挂 node_added 监听，
## 替代旧版本每物理帧 get_first_node_in_group 的 O(n) 退化。
func _begin_player_search() -> void:
	if _player_search_pending:
		return
	_player_search_pending = true
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if not _player_search_pending:
		return
	if node is Node2D and node.is_in_group("player"):
		follow_target = node
		_player_search_pending = false
		get_tree().node_added.disconnect(_on_node_added)


func _physics_process(delta: float) -> void:
	# 跑在 _physics_process 与 Player.move_and_slide 同频（60Hz），消除"渲染帧追物理阶梯函数"
	# 产生的 60Hz 节拍微抖。指数 lerp 1-exp(-k·delta) 是连续时间常数，频率切换不影响收敛轨迹。
	# 玩家失效（被 free / 关卡切换）时挂监听等待重生，不再每帧 O(n) 扫描整棵树
	if not is_instance_valid(follow_target):
		follow_target = null
		_begin_player_search()
		return

	if not _initialized:
		# 场景加载时若当前应处于锁定状态，直接快照到锁定中心
		_smoothed_position = _target_lock_center if _target_lock_to_center else (follow_target.global_position + Vector2(0, vertical_offset))
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
		# 下落追赶：仅当玩家正向下高速运动时，单独提升 y 轴 smoothing；
		# 阈值内或上升时退化为 follow_smoothing，水平 / 静止 / 跳起手感完全不变
		var smoothing_y := _resolve_fall_catch_up_smoothing()
		var ty := t if smoothing_y == follow_smoothing else 1.0 - exp(-smoothing_y * delta)
		_smoothed_position = Vector2(
			lerpf(_smoothed_position.x, target_pos.x, t),
			lerpf(_smoothed_position.y, target_pos.y, ty)
		)

	# 硬边界安全网（target 已被软限过，这里几乎不触发）
	# lock 过渡期间跳过：_displayed_bounds 同步在收缩，clamp 会打断 smoothstep 曲线
	# bounds 过渡期间跳过硬限：_displayed_bounds 每帧收缩，clamp 会把相机钉在中间态产生跳变
	if _target_has_bounds and not _lock_transition_active and _bounds_tween_t >= 1.0:
		_smoothed_position = _hard_clamp_to_bounds(_smoothed_position, _displayed_bounds, displayed_zoom)

	global_position = _smoothed_position


func _process(delta: float) -> void:
	# Zoom 指数平滑跑在 display rate（_process），消除 60Hz 步进感。
	if _initialized:
		var dist := displayed_zoom.distance_to(_target_zoom)
		if dist < EPSILON:
			displayed_zoom = _target_zoom
		else:
			var step := maxf(dist * (1.0 - exp(-zoom_smoothing * delta)), zoom_smoothing * 0.02 * delta)
			displayed_zoom = displayed_zoom.move_toward(_target_zoom, step)
		# canvas-items 架构：直接写回 Camera2D.zoom，实现真实缩放
		zoom = displayed_zoom
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
	var fade_speed := 1.0 / maxf(blend_in, EPSILON)
	if _focus_points.has(focus_id):
		# 重入时归零 weight_current，让"重新淡入"行为可预测；
		# 否则同一 focus 反复 add 会累积权重导致镜头瞬间跳到聚焦目标
		_focus_points[focus_id]["position"] = world_position
		_focus_points[focus_id]["weight_target"] = weight
		_focus_points[focus_id]["weight_current"] = 0.0
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
	_focus_points[focus_id]["fade_speed"] = 1.0 / maxf(blend_out, EPSILON)


## PixelRenderer 在窗口尺寸变化时调用，更新基础缩放并触发 zone 重算。
func set_base_zoom(base: Vector2) -> void:
	default_zoom = base
	_recompute_active_zone()
	# base zoom 变化来自窗口尺寸，不需要动画——立即 snap，避免启动时缓慢缩放漂移
	displayed_zoom = _target_zoom
	zoom = _target_zoom


## 显式指定 follow target（剧情/co-op/boss 镜头切换用）。
## 调用后会断开 node_added 自动发现监听，外部全权负责 follow_target 生命周期。
## snap=true 时立刻瞬移到目标位置，false 时让 follow_smoothing 平滑过渡。
## 传 null 等于"取消跟随"——画面留在当前位置直到下次 assign 或重新进入按组发现路径。
func assign_follow_target(target: Node2D, snap: bool = false) -> void:
	follow_target = target
	# 切到显式来源 → 关掉自动按组发现，避免幽灵监听仍在运行
	if _player_search_pending:
		_player_search_pending = false
		if get_tree().node_added.is_connected(_on_node_added):
			get_tree().node_added.disconnect(_on_node_added)
	if is_instance_valid(target) and snap:
		snap_to_target()


## 立即跳到玩家位置（复活/瞬移用），跳过所有平滑。
func snap_to_target() -> void:
	if not is_instance_valid(follow_target):
		return
	_smoothed_position = follow_target.global_position + Vector2(0, vertical_offset)
	global_position = _smoothed_position
	_lock_transition_active = false
	_lock_tween_t = 1.0
	_bounds_tween_t = 1.0
	displayed_zoom = _target_zoom
	zoom = _target_zoom
	_displayed_bounds = _target_bounds
	_look_ahead_value = 0.0
	_look_y_value = 0.0


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
	# zoom_override 是相对于 default_zoom 的倍数（1.0=不变，2.0=放大 2×）。
	# 乘以 default_zoom 得到在 canvas-items 下写入 Camera2D.zoom 的绝对值。
	_target_zoom = zoom_override * default_zoom if zoom_override != Vector2.ZERO else default_zoom


func _begin_bounds_transition(new_bounds: Rect2, has_bounds: bool, duration: float) -> void:
	if has_bounds and not _target_has_bounds:
		# 首次进入有边界区域：直接吸附，避免从 Rect2() 大小拉过来
		_displayed_bounds = new_bounds
		_bounds_tween_t = 1.0
		_bounds_tween_active = false
	else:
		_bounds_tween_from = _displayed_bounds
		_bounds_tween_duration = maxf(duration, EPSILON)
		_bounds_tween_t = 0.0
		_bounds_tween_active = true
	_target_bounds = new_bounds
	_target_has_bounds = has_bounds


func _begin_lock_transition(lock_to_center: bool, center: Vector2, duration: float) -> void:
	_target_lock_to_center = lock_to_center
	# 锁定中心若超出 bounds（zone 配置问题或 BoundsCenter Marker 摆错），
	# 先夹回 bounds 内，避免 lock 过渡 smoothstep 把相机插值到房间外
	if lock_to_center and _target_has_bounds:
		_target_lock_center = _hard_clamp_to_bounds(center, _target_bounds, _target_zoom)
	else:
		_target_lock_center = center
	if lock_to_center:
		if _initialized:
			# 从当前相机位置直接 smoothstep 到锁定中心，不经过 follow smoothing
			_lock_transition_active = true
			_lock_transition_from = _smoothed_position
			_lock_tween_t = 0.0
			_lock_tween_duration = maxf(duration, EPSILON)
		# 未初始化时跳过过渡，_physics_process 第一帧会直接快照到 lock_center
		_look_ahead_value = 0.0
		_facing_target = 0.0
		# 玩家若按住 S 进入 lock，残留的 look_y 偏移会在退出时第一帧污染目标位置；
		# 进入 lock 时也清零，确保 lock 中心计算与玩家观察意图无关
		_look_y_value = 0.0
	else:
		# 退出锁定：_smoothed_position 留在当前位置（通常是 lock_center 附近），
		# follow smoothing 负责将相机平滑地引导回玩家，无需额外 tween
		_lock_transition_active = false
		_look_ahead_value = 0.0
		_look_y_value = 0.0


# ============================================================================
# 内部：每帧过渡推进
# ============================================================================

func _advance_bounds_transition(delta: float) -> void:
	if not _bounds_tween_active:
		return
	_bounds_tween_t = minf(_bounds_tween_t + delta / _bounds_tween_duration, 1.0)
	var s := _smoothstep01(_bounds_tween_t)
	_displayed_bounds = Rect2(
		_bounds_tween_from.position.lerp(_target_bounds.position, s),
		_bounds_tween_from.size.lerp(_target_bounds.size, s)
	)
	if _bounds_tween_t >= 1.0:
		_bounds_tween_active = false


# ============================================================================
# 内部：每帧位置计算（仅 follow 模式使用）
# ============================================================================

func _compute_desired_position(delta: float) -> Vector2:
	# 冗余防御：_physics_process 入口已经过 is_instance_valid 检查，
	# 但调用栈深，将来若被复用此处再保一道
	if not is_instance_valid(follow_target):
		return _smoothed_position
	var target_pos: Vector2 = follow_target.global_position

	# 垂直构图偏移：与 look-ahead 正交（一个走 X 一个走 Y），互不干扰；
	# 直接叠加到 target_pos，由外层 follow_smoothing 统一平滑，无需独立缓动
	target_pos.y += vertical_offset

	# 视线偏移：玩家静止地面按 W/S 时，镜头向上/下平移预览
	# 注意：只更新 _look_y_value，不在此处叠加到 target_pos——
	# 必须等软边界 clamp 完成后再加，否则 look_y 偏移会被软区阻力抵消，
	# 导致靠近边界时两个方向都无法观察。
	if look_y_enabled:
		var y_intent := _read_look_y_intent()
		var speed := look_y_engage_speed if absf(y_intent) > 0.0 else look_y_return_speed
		_look_y_value = lerpf(_look_y_value, y_intent, 1.0 - exp(-speed * delta))

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
			if w > EPSILON:
				weighted += fp["position"] * w
				total_weight += w
		target_pos = weighted / total_weight

	# 死区：目标点超出以 _smoothed_position 为中心的矩形时，
	# 相机追到死区边缘而非直接追目标中心，保持传统平台跳跃的矩形死区手感。
	# 两者均为 0（默认）时条件不进入，零运行时开销。
	if dead_zone_width > 0.0 or dead_zone_height > 0.0:
		var dead_zone_target := target_pos
		if dead_zone_width > 0.0:
			var half_w := dead_zone_width * 0.5
			var dx := target_pos.x - _smoothed_position.x
			if dx > half_w:
				dead_zone_target.x = target_pos.x - half_w
			elif dx < -half_w:
				dead_zone_target.x = target_pos.x + half_w
			else:
				dead_zone_target.x = _smoothed_position.x
		if dead_zone_height > 0.0:
			var half_h := dead_zone_height * 0.5
			var dy := target_pos.y - _smoothed_position.y
			# 竖向速度超阈值时（跳跃/快速下落）绕过 Y 死区：
			# 死区期间相机向上漂移，落地后玩家回到原点却仍在死区内，
			# 导致相机永久卡在高处；绕过后由 fall_catch_up_smoothing 正常接管。
			var _cb := follow_target as CharacterBody2D
			var vy_large := _cb != null and absf(_cb.velocity.y) >= fall_catch_up_velocity_threshold
			if not vy_large:
				if dy > half_h:
					dead_zone_target.y = target_pos.y - half_h
				elif dy < -half_h:
					dead_zone_target.y = target_pos.y + half_h
				else:
					dead_zone_target.y = _smoothed_position.y
		target_pos = dead_zone_target

	# 软边界减速（基础跟随位置，不含 look_y）
	if _target_has_bounds:
		target_pos = _soft_clamp_to_bounds(target_pos, _displayed_bounds, displayed_zoom)

	# look_y 在软边界之后叠加：朝边界方向由硬边界（_physics_process 末尾）兜底，
	# 朝自由方向则完全不受软区阻力影响，靠近任意边界时仍能往反方向观察。
	if look_y_enabled:
		target_pos.y += _look_y_value * look_y_distance

	return target_pos


## 根据玩家下落速度返回 y 轴 follow smoothing：
##   • velocity.y ≤ threshold（包括上升 / 水平 / 缓慢下落）：返回 follow_smoothing，手感不变
##   • velocity.y ≥ threshold + ramp（高速坠落）：返回 fall_catch_up_smoothing，相机紧追
##   • 之间线性过渡，避免突变
func _resolve_fall_catch_up_smoothing() -> float:
	var _cb2 := follow_target as CharacterBody2D
	if not is_instance_valid(follow_target) or _cb2 == null:
		return follow_smoothing
	var vy: float = _cb2.velocity.y
	if vy <= fall_catch_up_velocity_threshold:
		return follow_smoothing
	var ramp := clampf((vy - fall_catch_up_velocity_threshold) / maxf(fall_catch_up_ramp, EPSILON), 0.0, 1.0)
	return lerpf(follow_smoothing, fall_catch_up_smoothing, ramp)


func _read_look_y_intent() -> float:
	if follow_target.has_method("get_camera_look_y_intent"):
		return follow_target.get_camera_look_y_intent()
	return 0.0


func _read_facing_intent() -> float:
	if follow_target.has_method("get_camera_facing_intent"):
		return follow_target.get_camera_facing_intent()
	var _cb3 := follow_target as CharacterBody2D
	if _cb3 != null:
		var vx: float = _cb3.velocity.x
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
		if fp["weight_target"] <= 0.0 and fp["weight_current"] < FOCUS_FADE_OUT_EPSILON:
			to_remove.append(id)
	for id in to_remove:
		_focus_points.erase(id)


# ============================================================================
# 内部：边界数学
# ============================================================================

func _get_camera_half_view(zoom_value: Vector2) -> Vector2:
	# canvas-items 架构：Camera2D.zoom 是真实缩放，世界可见范围 = 视口尺寸 / zoom。
	# zoom_value 在边界过渡期间平滑变化，确保边界检测与实际可见区域同步。
	var viewport_size := get_viewport_rect().size
	return viewport_size * 0.5 / maxf(zoom_value.x, EPSILON)


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
	if dead_zone_width > 0.0 or dead_zone_height > 0.0:
		var dz_rect := Rect2(
			Vector2(-dead_zone_width, -dead_zone_height) * 0.5,
			Vector2(dead_zone_width, dead_zone_height)
		)
		draw_rect(dz_rect, Color(0.2, 0.8, 1.0, 0.5), false, 1.5)
	for fp in _focus_points.values():
		var local_pos: Vector2 = fp["position"] - global_position
		draw_circle(local_pos, 6.0, Color(0.4, 1.0, 0.4, fp["weight_current"]))
