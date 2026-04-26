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

@export_group("Camera / Vertical")
@export var vertical_deadzone_up: float = 10.0        # 向上软区大小（小跳更不容易触发）
@export var vertical_deadzone_down: float = 10.0      # 向下软区大小
@export var grounded_recenter_speed: float = 1.0      # 落地后锚点归位速度（越大越快回中）
@export var camera_follow_speed_y: float = 3.0        # 垂直摄影机整体跟随速度
@export var max_vertical_auto_offset: float = 52.0    # 自动垂直偏移的最大值（防止大落差时镜头飞太远）

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

# 摄像机边界系统（栈结构，支持嵌套区域和退出恢复）
# 每个元素是 {priority: int, rect: Rect2}
# 永远取优先级最高的那个生效，退出区域时移除对应条目
var _camera_bounds_stack: Array = []
var _camera_bounds_rect: Rect2 = Rect2()
var _has_camera_bounds: bool = false
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

	# -----------------------------
	# 1. 水平前视（带死区、空中保持、落地延迟回中）
	# -----------------------------
	if abs(velocity.x) > horizontal_deadzone_speed:
		_facing_x_target = sign(velocity.x)
		_grounded_return_timer = 0.0
	elif not is_on_floor():
		# 空中时保留最后一次有效朝向，不回中
		_grounded_return_timer = 0.0
	else:
		# 地面且速度不够时，先计时再回中
		_grounded_return_timer += delta
		if _grounded_return_timer >= grounded_return_delay:
			_facing_x_target = 0.0

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
	# 3. 手动抬头/低头（先算目标值，但先不混进自动跟随）
	# -----------------------------
	# 这样靠近边界时，不会因为整体 clamp 而把“另一个方向”的手动查看也一起吃掉
	var manual_vertical_offset := 0.0
	if is_on_floor() and _vertical_look_timer >= vertical_look_delay:
		if direction.y < -0.5:
			manual_vertical_offset = manual_look_up
		elif direction.y > 0.5:
			manual_vertical_offset = manual_look_down

	# -----------------------------
	# 3.5. 明显下落时额外给下方视野（Fall Look Assist）
	# -----------------------------
	var target_fall_look := 0.0
	if not is_on_floor() and velocity.y > fall_look_speed_threshold:
		var fall_ratio := inverse_lerp(fall_look_speed_threshold, max_fall_speed, velocity.y)
		target_fall_look = lerpf(0.0, fall_look_max_offset, fall_ratio)

	_fall_look_offset = _smooth_value(_fall_look_offset, target_fall_look, fall_look_blend_speed, delta)

	# 这里只让“自动跟随 + 下落辅助”参与主相机平滑
	# 手动 look 放到边界限制之后再加
	var target_vertical_offset := auto_vertical_offset + _fall_look_offset

	# -----------------------------
	# 4. 水平 / 垂直分轴平滑
	# -----------------------------
	_camera_offset_x = _smooth_value(_camera_offset_x, target_horizontal_offset, camera_follow_speed_x, delta)
	_camera_offset_y = _smooth_value(_camera_offset_y, target_vertical_offset, camera_follow_speed_y, delta)

	var final_position := base_camera_position + Vector2(_camera_offset_x, _camera_offset_y)

	# 先准备“剩余空间”数据，给手动上下看使用
	var local_min := Vector2(-INF, -INF)
	var local_max := Vector2(INF, INF)

	# -----------------------------
	# 5. 先限制自动相机位置到边界内
	# -----------------------------
	if _has_camera_bounds:
		# zoom 算进去，保证边界和实际可见范围一致
		var half_screen := get_viewport_rect().size * camera.zoom * 0.5
		local_min = _camera_bounds_rect.position - global_position + half_screen
		local_max = _camera_bounds_rect.end - global_position - half_screen

		# 区域比屏幕还小时，local_min > local_max，改为居中显示而不是 clamp 出错
		if local_min.x > local_max.x:
			final_position.x = (local_min.x + local_max.x) * 0.5
		else:
			final_position.x = clampf(final_position.x, local_min.x, local_max.x)

		if local_min.y > local_max.y:
			final_position.y = (local_min.y + local_max.y) * 0.5
		else:
			final_position.y = clampf(final_position.y, local_min.y, local_max.y)

	# -----------------------------
	# 6. 手动抬头/低头在“剩余空间”里附加
	# -----------------------------
	# 这样靠近上边界时，抬头会被限制，但只要下方还有空间，低头仍然能生效
	# 手动上下看也做平滑，避免一帧切过去
	_manual_look_offset = _smooth_value(_manual_look_offset, manual_vertical_offset, manual_look_blend_speed, delta)

	if _manual_look_offset != 0.0:
		var final_manual_offset := _manual_look_offset

		if _has_camera_bounds:
			var available_up := local_min.y - final_position.y
			var available_down := local_max.y - final_position.y
			final_manual_offset = clampf(final_manual_offset, available_up, available_down)

		final_position.y += final_manual_offset

	camera_target.position = final_position

func _smooth_value(current: float, target: float, speed: float, delta: float) -> float:
	# 帧率无关的指数平滑核心函数
	if speed <= 0.0:
		return target
	var weight := 1.0 - exp(-speed * delta)
	return lerpf(current, target, weight)

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
func push_camera_bounds(rect: Rect2, priority: int = 0) -> void:
	# 进入区域时压栈，按优先级排序，最高优先级在最后
	_camera_bounds_stack.append({"priority": priority, "rect": rect})
	_camera_bounds_stack.sort_custom(func(a, b): return a["priority"] < b["priority"])
	_update_active_bounds()

func pop_camera_bounds(priority: int = 0) -> void:
	# 退出区域时移除对应优先级的条目
	for i in range(_camera_bounds_stack.size() - 1, -1, -1):
		if _camera_bounds_stack[i]["priority"] == priority:
			_camera_bounds_stack.remove_at(i)
			break
	_update_active_bounds()

func _update_active_bounds() -> void:
	# 取栈顶（优先级最高）的边界生效
	if _camera_bounds_stack.is_empty():
		_has_camera_bounds = false
	else:
		_camera_bounds_rect = _camera_bounds_stack.back()["rect"]
		_has_camera_bounds = true

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
