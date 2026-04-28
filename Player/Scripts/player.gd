class_name Player extends CharacterBody2D

#region /// ⚙️ State Machine Variables (状态机变量)
var current_state : Playerstate
var previous_state : Playerstate
var all_states : Array[Playerstate] = []
@export var initial_state : Playerstate  # 明确指定初始状态，不再依赖节点顺序
#endregion

#region /// 🏃 Standard Variables (基础移动与输入)
var direction : Vector2 = Vector2.ZERO
const INPUT_DEADZONE : float = 0.1  # 统一输入死区阈值，防止手柄漂移

# 共享移动参数（供各状态读取，避免重复定义）
var air_speed : float = 160.0       # 空中水平速度，统一供 Jump/Fall 使用
var jump_velocity : float = -380.0  # 跳跃初速度，统一供 Jump 及未来二段跳等状态使用

# 重力与手感调整参数
var gravity : float = 900.0
var fall_gravity_multiplier : float = 1.8  # 下落时的重力倍数（放大重力加速坠落）
var max_fall_speed : float = 600.0         # 最大下落速度（防止穿透平台）

# 土狼时间（在地面时持续重置计时器，离地后自然倒数）
var coyote_timer : float = 0.0      # 土狼时间倒计时，大于 0 表示仍在土狼时间窗口内
var coyote_duration : float = 0.15  # 土狼时间窗口长度（秒）

# 单向平台穿透
# ONE_WAY_PLATFORM_LAYER 对应 Godot 物理层第 3 层（TileSet 里显示的"物理层 1"）
# 如果你的单向平台层改变了，只需修改这个常量
const ONE_WAY_PLATFORM_LAYER : int = 3
@export var drop_through_duration : float = 0.18  # 关闭碰撞的持续时间（秒）
var drop_through_timer : float = 0.0
#endregion

#region /// 🎨 Animation Variables (动画节点，统一由 Player 持有)
@onready var anim : AnimatedSprite2D = $AnimatedSprite2D  # 各状态通过 player.anim 访问
#endregion

#region /// 🎬 Camera Variables (摄影机系统)
# 注意：
# 这份脚本已经完整接管镜头平滑，
# 请确保 Camera2D 自带的 position_smoothing_enabled 是关闭的。

@export_group("Camera / Horizontal")
@export var look_ahead_distance_x: float = 20.0       # 水平前视距离
@export var horizontal_deadzone_speed: float = 110.0  # 速度超过此值才触发方向记忆
@export var horizontal_turn_speed: float = 3.0        # 转向时前视切换速度（越大越快）
@export var horizontal_return_speed: float = 0.9      # 停下后回中速度（越小越慢）
@export var camera_follow_speed_x: float = 4.0        # 水平摄影机整体跟随速度
@export var bounds_softness_x: float = 0.0            # 靠近左右边界时的软着陆范围（普通区域建议 0，避免回弹）
@export var edge_lookahead_fade_distance: float = 140.0 # 靠近左右边界时，水平前视逐渐衰减的距离

@export_group("Camera / Vertical")
@export var vertical_deadzone_up: float = 10.0        # 向上软区大小（小跳更不容易触发）
@export var vertical_deadzone_down: float = 10.0      # 向下软区大小
@export var grounded_recenter_speed: float = 1.0      # 落地后锚点归位速度（越大越快回中）
@export var camera_follow_speed_y: float = 3.0        # 垂直摄影机整体跟随速度
@export var max_vertical_auto_offset: float = 52.0    # 自动垂直偏移的最大值（防止大落差时镜头飞太远）
@export var bounds_softness_y: float = 0.0            # 靠近上下边界时的软着陆范围（普通区域建议 0，避免回弹）

@export_group("Camera / Manual Look")
@export var manual_look_up: float = -30.0             # 手动抬头偏移量（负数向上）
@export var manual_look_down: float = 30.0            # 手动低头偏移量（正数向下）
@export var vertical_look_delay: float = 0.30         # 按住多久才触发手动抬头/低头（秒）
@export var manual_look_blend_speed: float = 5.0      # 手动抬头/低头平滑速度

@export_group("Camera / Air & Fall Assist")
@export var grounded_return_delay: float = 0.12       # 落地后延迟多久才允许水平回中
@export var fall_look_speed_threshold: float = 220.0  # 明显下落时才额外往下看
@export var fall_look_max_offset: float = 26.0        # 高速下落时额外往下看的最大距离
@export var fall_look_blend_speed: float = 4.5        # 下落额外下看的进入/退出速度

@export_group("Camera / Room Lock")
@export var room_lock_blend_speed: float = 2.4        # 隐藏房间固定镜头的混合速度（越小越慢越柔）

@onready var camera_target: Marker2D = $CameraTarget
@onready var camera: Camera2D = $CameraTarget/Camera2D  # 用于边界计算时读取 zoom

var base_camera_position: Vector2       # 记录编辑器里 Marker2D 的初始位置

# 水平方向状态
var _look_ahead_sign: float = 0.0       # 当前水平前视的平滑值（-1 到 1）
var _facing_x_target: float = 0.0      # 水平前视的目标值
var _grounded_return_timer: float = 0.0 # 地面停留多久后才允许水平回中

# 垂直方向状态
var _vertical_look_timer: float = 0.0   # 手动上下看的蓄力计时器
var _camera_anchor_world_y: float = 0.0 # 垂直软区锚点（世界坐标）
var _fall_look_offset: float = 0.0      # 当前"额外下看"偏移
var _manual_look_offset: float = 0.0    # 当前"手动上下看"平滑偏移

# 最终叠加到 CameraTarget 本地位置上的平滑偏移
var _camera_offset_x: float = 0.0
var _camera_offset_y: float = 0.0

# 隐藏房间固定镜头状态
var _room_lock_weight: float = 0.0                 # 0 = 正常跟随，1 = 固定到房间中心
var _active_bounds_lock_to_center: bool = false    # 当前生效边界是否要求固定房间镜头
var _active_bounds_center: Vector2 = Vector2.ZERO  # 当前生效边界的世界中心

# 摄像机边界系统（栈结构，按 source_id 管理，支持嵌套区域和退出恢复）
# 每个元素是 {source_id: int, priority: int, rect: Rect2, duration: float, order: int, lock_to_center: bool}
var _camera_bounds_stack: Array = []
var _camera_bounds_rect: Rect2 = Rect2()
var _camera_bounds_display_rect: Rect2 = Rect2()
var _has_camera_bounds: bool = false
var _camera_bounds_tween: Tween
var _camera_bounds_order_counter: int = 0
#endregion

@onready var states_node: Node = $states
@onready var state_label: Label = $Label

func _ready() -> void:
	# 记录运行游戏那一刻，你在编辑器里设定的 Marker2D 位置（实现所见即所得）
	if camera_target:
		base_camera_position = camera_target.position

	# 垂直软区锚点使用世界坐标初始化
	_camera_anchor_world_y = global_position.y

	initialize_states()

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		change_state(current_state.handle_input(event))

func _physics_process(delta: float) -> void:
	# update_direction 在物理帧开头，保证本帧输入和物理逻辑同步
	update_direction()

	# 不对称重力：下落比上升更快，增强平台游戏手感
	if velocity.y > 0.0:
		velocity.y += gravity * fall_gravity_multiplier * delta
	else:
		velocity.y += gravity * delta

	# 限制终端速度
	velocity.y = min(velocity.y, max_fall_speed)

	# 执行状态机的物理更新
	if current_state:
		change_state(current_state.physics_process(delta))

	move_and_slide()

	# 单向平台穿透计时：时间到了恢复碰撞
	if drop_through_timer > 0.0:
		drop_through_timer -= delta
		if drop_through_timer <= 0.0:
			set_collision_mask_value(ONE_WAY_PLATFORM_LAYER, true)

	# 土狼时间：在地面时持续重置，离地后倒数
	if is_on_floor():
		coyote_timer = coyote_duration
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)

	_update_vertical_look_timer(delta)
	_update_camera(delta)

func _process(delta: float) -> void:
	if current_state:
		change_state(current_state.process(delta))

# ==========================================
# 🎬 摄影机核心逻辑
# ==========================================
func _update_vertical_look_timer(delta: float) -> void:
	# 只有在地面、几乎静止时，才允许蓄力手动抬头/低头
	# 这样跑动和跳跃过程中不会误触发上下看
	if is_on_floor() and abs(velocity.x) < 10.0 and abs(velocity.y) < 5.0:
		if abs(direction.y) > 0.5:
			_vertical_look_timer += delta
		else:
			_vertical_look_timer = 0.0
	else:
		_vertical_look_timer = 0.0

func _update_camera(delta: float) -> void:
	if not camera_target:
		return

	var player_y := global_position.y

	# 隐藏房间固定镜头不是瞬间切换，而是平滑提高权重
	var room_lock_target: float = 1.0 if _active_bounds_lock_to_center else 0.0
	_room_lock_weight = _smooth_value(_room_lock_weight, room_lock_target, room_lock_blend_speed, delta)
	var player_camera_weight: float = 1.0 - _room_lock_weight

	# -----------------------------
	# 1. 水平前视（带死区、空中保持、落地延迟回中）
	# -----------------------------
	var has_horizontal_intent: bool = absf(direction.x) >= INPUT_DEADZONE

	if is_on_floor():
		# 地面时优先看“输入意图”，而不是实际速度
		# 这样顶着地图边缘/墙体时，镜头不会因为 velocity.x 被撞成 0 就回中
		if has_horizontal_intent:
			_facing_x_target = sign(direction.x)
			_grounded_return_timer = 0.0
		else:
			# 真正松开输入后，才开始延迟回中
			_grounded_return_timer += delta
			if _grounded_return_timer >= grounded_return_delay:
				_facing_x_target = 0.0
	else:
		# 空中保持最后一次有效朝向
		_grounded_return_timer = 0.0

	var facing_speed := horizontal_turn_speed if _facing_x_target != 0.0 else horizontal_return_speed
	_look_ahead_sign = _smooth_value(_look_ahead_sign, _facing_x_target, facing_speed, delta)
	var target_horizontal_offset := _look_ahead_sign * look_ahead_distance_x

	# -----------------------------
	# 2. 垂直软区（Soft Zone）
	# -----------------------------
	if is_on_floor():
		_camera_anchor_world_y = _smooth_value(
			_camera_anchor_world_y,
			player_y,
			grounded_recenter_speed,
			delta
		)
	else:
		if player_y < _camera_anchor_world_y - vertical_deadzone_up:
			_camera_anchor_world_y = player_y + vertical_deadzone_up
		elif player_y > _camera_anchor_world_y + vertical_deadzone_down:
			_camera_anchor_world_y = player_y - vertical_deadzone_down

	var auto_vertical_offset := clampf(
		player_y - _camera_anchor_world_y,
		-max_vertical_auto_offset,
		max_vertical_auto_offset
	)

	# -----------------------------
	# 3. 手动抬头/低头（先算目标值，不先混进自动跟随）
	# -----------------------------
	# 放到边界限制之后再附加，确保靠近边界时不会把另一个方向也锁死
	var manual_vertical_target := 0.0
	if is_on_floor() and _vertical_look_timer >= vertical_look_delay:
		if direction.y < -0.5:
			manual_vertical_target = manual_look_up
		elif direction.y > 0.5:
			manual_vertical_target = manual_look_down

	# -----------------------------
	# 3.5. 明显下落时额外给下方视野（Fall Look Assist）
	# -----------------------------
	var target_fall_look := 0.0
	if not is_on_floor() and velocity.y > fall_look_speed_threshold:
		var fall_ratio := inverse_lerp(fall_look_speed_threshold, max_fall_speed, velocity.y)
		target_fall_look = lerpf(0.0, fall_look_max_offset, fall_ratio)

	_fall_look_offset = _smooth_value(_fall_look_offset, target_fall_look, fall_look_blend_speed, delta)

	# 只让"自动跟随 + 下落辅助"参与主相机平滑，手动 look 放到边界限制之后再加
	var target_vertical_offset := auto_vertical_offset + _fall_look_offset

	# 隐藏房间固定镜头模式下，玩家驱动镜头逐渐淡出，而不是一帧关闭
	target_horizontal_offset *= player_camera_weight
	target_vertical_offset *= player_camera_weight
	manual_vertical_target *= player_camera_weight

	# -----------------------------
	# 4. 先准备边界范围
	# -----------------------------
	var local_min := Vector2(-INF, -INF)
	var local_max := Vector2(INF, INF)

	if _has_camera_bounds:
		var half_screen := get_viewport_rect().size * camera.zoom * 0.5
		local_min = _camera_bounds_display_rect.position - global_position + half_screen
		local_max = _camera_bounds_display_rect.end - global_position - half_screen

	# 靠近边界时，水平前视逐渐减弱，避免“前视继续推 + 边界硬拦”的弹力感
	if _has_camera_bounds:
		target_horizontal_offset *= _get_edge_lookahead_weight(target_horizontal_offset, local_min, local_max)

	# -----------------------------
	# 5. 先算“受边界限制后的目标位置”
	# -----------------------------
	var desired_position := base_camera_position + Vector2(target_horizontal_offset, target_vertical_offset)

	if _has_camera_bounds:
		desired_position.x = _soft_limit(desired_position.x, local_min.x, local_max.x, bounds_softness_x)
		desired_position.y = _soft_limit(desired_position.y, local_min.y, local_max.y, bounds_softness_y)

	# -----------------------------
	# 6. 再让相机平滑追这个“已经被限制过的目标”
	# -----------------------------
	_camera_offset_x = _smooth_value(
		_camera_offset_x,
		desired_position.x - base_camera_position.x,
		camera_follow_speed_x,
		delta
	)

	_camera_offset_y = _smooth_value(
		_camera_offset_y,
		desired_position.y - base_camera_position.y,
		camera_follow_speed_y,
		delta
	)

	var final_position := base_camera_position + Vector2(_camera_offset_x, _camera_offset_y)

	# -----------------------------
	# 7. 手动抬头/低头在剩余空间里附加
	# -----------------------------
	# 靠近上边界时抬头受限，但只要下方还有空间，低头仍然能生效，反之亦然
	_manual_look_offset = _smooth_value(_manual_look_offset, manual_vertical_target, manual_look_blend_speed, delta)

	if _manual_look_offset != 0.0:
		var final_manual := _manual_look_offset
		if _has_camera_bounds:
			var available_up   := local_min.y - final_position.y
			var available_down := local_max.y - final_position.y
			final_manual = clampf(final_manual, available_up, available_down)
		final_position.y += final_manual

	# -----------------------------
	# 8. 隐藏房间固定镜头平滑混合
	# -----------------------------
	# 这里不是直接锁死，而是把正常玩家镜头慢慢混合到房间中心
	# camera.position 也要减掉，保证真正的 Camera2D 视觉中心对齐房间中心
	if _room_lock_weight > 0.001 and _has_camera_bounds:
		var room_center_position := _active_bounds_center - global_position - camera.position
		final_position = final_position.lerp(room_center_position, _room_lock_weight)

	camera_target.position = final_position

func _smooth_value(current: float, target: float, speed: float, delta: float) -> float:
	# 帧率无关的指数平滑核心函数
	if speed <= 0.0:
		return target
	var weight := 1.0 - exp(-speed * delta)
	return lerpf(current, target, weight)

func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _get_edge_lookahead_weight(offset_x: float, local_min: Vector2, local_max: Vector2) -> float:
	# 没有水平前视、没有有效边界，或者不需要衰减时，保持原效果
	if edge_lookahead_fade_distance <= 0.0 or absf(offset_x) < 0.01:
		return 1.0

	# 房间比屏幕还小时，不再额外给水平前视，避免小空间里左右拉扯
	if local_min.x > local_max.x:
		return 0.0

	var distance_to_edge: float = 0.0
	if offset_x > 0.0:
		distance_to_edge = local_max.x - base_camera_position.x
	else:
		distance_to_edge = base_camera_position.x - local_min.x

	return _smoothstep01(distance_to_edge / edge_lookahead_fade_distance)

func _soft_limit(value: float, min_val: float, max_val: float, softness: float) -> float:
	# 区域比屏幕小，直接居中
	if min_val > max_val:
		return (min_val + max_val) * 0.5

	# 不需要软边界时，退化成普通 clamp
	if softness <= 0.0:
		return clampf(value, min_val, max_val)

	# 超出边界，直接夹住
	if value <= min_val:
		return min_val
	if value >= max_val:
		return max_val

	# 靠近左/上边界时，渐进减速
	if value < min_val + softness:
		var t := clampf((value - min_val) / softness, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t) # smoothstep
		return lerpf(min_val, value, t)

	# 靠近右/下边界时，渐进减速
	if value > max_val - softness:
		var t := clampf((max_val - value) / softness, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t) # smoothstep
		return lerpf(max_val, value, t)

	return value

# ==========================================
# ⚙️ 状态机与辅助逻辑
# ==========================================
func initialize_states() -> void:
	all_states.clear()

	for c in states_node.get_children():
		if c is Playerstate:
			all_states.append(c)
			c.player = self
			c.init()

	if all_states.is_empty():
		push_warning("Player 找不到任何状态！请检查 $states 节点。")
		return

	if initial_state:
		change_state(initial_state)
	else:
		push_warning("Player 未指定 initial_state！将使用第一个状态作为后备。")
		change_state(all_states[0])

func change_state(new_state : Playerstate) -> void:
	if new_state == null or new_state == current_state:
		return

	if current_state:
		current_state.exit()
		previous_state = current_state

	current_state = new_state
	current_state.enter()

	if state_label:
		state_label.text = current_state.name

func update_direction() -> void:
	var x_axis := Input.get_axis("left", "right")
	var y_axis := Input.get_axis("up", "down")

	if abs(x_axis) < INPUT_DEADZONE:
		x_axis = 0.0
	if abs(y_axis) < INPUT_DEADZONE:
		y_axis = 0.0

	direction = Vector2(x_axis, y_axis)

# ==========================================
# 🎨 动画与输入辅助
# ==========================================
func update_facing() -> void:
	if direction.x < 0.0:
		anim.flip_h = true
	elif direction.x > 0.0:
		anim.flip_h = false

func has_horizontal_input() -> bool:
	return abs(direction.x) >= INPUT_DEADZONE

# ==========================================
# 🎥 摄影机边界系统
# ==========================================
func push_camera_bounds(source_id: int, rect: Rect2, priority: int = 0, duration: float = 0.40, lock_to_center: bool = false) -> void:
	# 先移除同一个区域的旧条目（防止重复压栈）
	for i in range(_camera_bounds_stack.size() - 1, -1, -1):
		if _camera_bounds_stack[i]["source_id"] == source_id:
			_camera_bounds_stack.remove_at(i)

	# 记录进入顺序：同优先级时，最后进入的区域生效
	_camera_bounds_order_counter += 1

	# 压入新条目并排序
	_camera_bounds_stack.append({
		"source_id": source_id,
		"priority": priority,
		"rect": rect,
		"duration": duration,
		"order": _camera_bounds_order_counter,
		"lock_to_center": lock_to_center
	})

	_camera_bounds_stack.sort_custom(func(a, b):
		if a["priority"] == b["priority"]:
			return a["order"] < b["order"]
		return a["priority"] < b["priority"]
	)

	_update_active_bounds()

func pop_camera_bounds(source_id: int) -> void:
	# 按区域唯一 id 移除，不会误删同优先级的其他区域
	for i in range(_camera_bounds_stack.size() - 1, -1, -1):
		if _camera_bounds_stack[i]["source_id"] == source_id:
			_camera_bounds_stack.remove_at(i)
			break
	_update_active_bounds()

func _update_active_bounds() -> void:
	# 取栈顶（优先级最高；同优先级时最后进入）的边界生效
	if _camera_bounds_stack.is_empty():
		_has_camera_bounds = false
		_active_bounds_lock_to_center = false
		_active_bounds_center = Vector2.ZERO
		return

	var active_bounds = _camera_bounds_stack.back()
	var new_rect: Rect2 = active_bounds["rect"]
	var duration: float = active_bounds["duration"]

	_has_camera_bounds = true
	_camera_bounds_rect = new_rect
	_active_bounds_center = new_rect.position + new_rect.size * 0.5
	_active_bounds_lock_to_center = active_bounds["lock_to_center"]

	# 第一次直接赋值，避免开场从零矩形 Tween 过来
	if _camera_bounds_display_rect == Rect2():
		_camera_bounds_display_rect = new_rect
		return

	# 有旧 tween 就杀掉
	if _camera_bounds_tween:
		_camera_bounds_tween.kill()

	_camera_bounds_tween = create_tween()
	_camera_bounds_tween.set_parallel(true)
	_camera_bounds_tween.set_trans(Tween.TRANS_SINE)
	_camera_bounds_tween.set_ease(Tween.EASE_IN_OUT)

	_camera_bounds_tween.tween_method(_set_camera_bounds_rect_position, _camera_bounds_display_rect.position, new_rect.position, duration)
	_camera_bounds_tween.tween_method(_set_camera_bounds_rect_size, _camera_bounds_display_rect.size, new_rect.size, duration)

func _set_camera_bounds_rect_position(value: Vector2) -> void:
	_camera_bounds_display_rect.position = value

func _set_camera_bounds_rect_size(value: Vector2) -> void:
	_camera_bounds_display_rect.size = value

# ==========================================
# 🪜 单向平台穿透
# ==========================================
func request_drop_through() -> void:
	# 已经在穿透过程中时，不重复触发，防止 timer 被每帧刷新
	if drop_through_timer > 0.0:
		return
	set_collision_mask_value(ONE_WAY_PLATFORM_LAYER, false)
	drop_through_timer = drop_through_duration
	velocity.y = max(velocity.y, 30.0)

func apply_bounce(force: float) -> void:
	velocity.y = -force
	for state in all_states:
		if state is PlayerstateJump:
			state.is_bouncing = true
			change_state(state)
			break
