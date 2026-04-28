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
const ONE_WAY_PLATFORM_LAYER : int = 3
@export var drop_through_duration : float = 0.18
var drop_through_timer : float = 0.0
#endregion

#region /// 🎨 Animation Variables (动画节点，统一由 Player 持有)
@onready var anim : AnimatedSprite2D = $AnimatedSprite2D
#endregion

#region /// 🎬 Camera Variables (摄影机系统)
# 请确保 Camera2D 自带的 position_smoothing_enabled 是关闭的。

@export_group("Camera / Horizontal")
@export var look_ahead_distance_x: float = 20.0
@export var horizontal_deadzone_speed: float = 110.0
@export var horizontal_turn_speed: float = 3.0
@export var horizontal_return_speed: float = 0.9
@export var camera_follow_speed_x: float = 4.0
@export var bounds_softness_x: float = 0.0       # 0 = 硬边界无回弹，> 0 = 靠近边界时软减速
@export var edge_lookahead_fade_distance: float = 350.0

@export_group("Camera / Vertical")
@export var vertical_deadzone_up: float = 10.0
@export var vertical_deadzone_down: float = 10.0
@export var grounded_recenter_speed: float = 1.0
@export var camera_follow_speed_y: float = 3.0
@export var max_vertical_auto_offset: float = 52.0
@export var bounds_softness_y: float = 0.0       # 0 = 硬边界无回弹，> 0 = 靠近边界时软减速

@export_group("Camera / Manual Look")
@export var manual_look_up: float = -30.0
@export var manual_look_down: float = 30.0
@export var vertical_look_delay: float = 0.30
@export var manual_look_blend_speed: float = 5.0

@export_group("Camera / Air & Fall Assist")
@export var grounded_return_delay: float = 0.12
@export var fall_look_speed_threshold: float = 220.0
@export var fall_look_max_offset: float = 26.0
@export var fall_look_blend_speed: float = 4.5

@export_group("Camera / Room Lock")
@export var room_lock_blend_speed: float = 2.4

@onready var camera_target: Marker2D = $CameraTarget
@onready var camera: Camera2D = $CameraTarget/Camera2D

var base_camera_position: Vector2

# 水平方向状态
var _look_ahead_sign: float = 0.0
var _facing_x_target: float = 0.0
var _grounded_return_timer: float = 0.0

# 垂直方向状态
var _vertical_look_timer: float = 0.0
var _camera_anchor_world_y: float = 0.0
var _fall_look_offset: float = 0.0
var _manual_look_offset: float = 0.0

# 平滑偏移
var _camera_offset_x: float = 0.0
var _camera_offset_y: float = 0.0

# 隐藏房间固定镜头
var _room_lock_weight: float = 0.0
var _active_bounds_lock_to_center: bool = false
var _active_bounds_center: Vector2 = Vector2.ZERO

# 摄像机边界系统
var _camera_bounds_stack: Array = []
var _camera_bounds_rect: Rect2 = Rect2()
var _camera_bounds_display_rect: Rect2 = Rect2()
var _has_camera_bounds: bool = false
var _bounds_initialized: bool = false  # 【修复】独立标记，替代不可靠的 == Rect2() 判断
var _camera_bounds_tween: Tween
var _camera_bounds_order_counter: int = 0
#endregion

@onready var states_node: Node = $states
@onready var state_label: Label = $Label

func _ready() -> void:
	if camera_target:
		base_camera_position = camera_target.position
	_camera_anchor_world_y = global_position.y
	initialize_states()

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		change_state(current_state.handle_input(event))

func _physics_process(delta: float) -> void:
	update_direction()

	if velocity.y > 0.0:
		velocity.y += gravity * fall_gravity_multiplier * delta
	else:
		velocity.y += gravity * delta
	velocity.y = min(velocity.y, max_fall_speed)

	if current_state:
		change_state(current_state.physics_process(delta))

	move_and_slide()

	if drop_through_timer > 0.0:
		drop_through_timer -= delta
		if drop_through_timer <= 0.0:
			set_collision_mask_value(ONE_WAY_PLATFORM_LAYER, true)

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
	if is_on_floor() and absf(velocity.x) < 10.0 and absf(velocity.y) < 5.0:
		if absf(direction.y) > 0.5:
			_vertical_look_timer += delta
		else:
			_vertical_look_timer = 0.0
	else:
		_vertical_look_timer = 0.0

func _update_camera(delta: float) -> void:
	if not camera_target:
		return

	var player_y := global_position.y

	# 隐藏房间权重平滑
	var room_lock_target: float = 1.0 if _active_bounds_lock_to_center else 0.0
	_room_lock_weight = _smooth_value(_room_lock_weight, room_lock_target, room_lock_blend_speed, delta)
	var player_camera_weight: float = 1.0 - _room_lock_weight

	# -----------------------------
	# 1. 水平前视
	# -----------------------------
	if is_on_floor():
		if absf(direction.x) >= INPUT_DEADZONE:
			_facing_x_target = sign(direction.x)
			_grounded_return_timer = 0.0
		else:
			_grounded_return_timer += delta
			if _grounded_return_timer >= grounded_return_delay:
				_facing_x_target = 0.0
	else:
		_grounded_return_timer = 0.0

	var facing_speed := horizontal_turn_speed if _facing_x_target != 0.0 else horizontal_return_speed
	_look_ahead_sign = _smooth_value(_look_ahead_sign, _facing_x_target, facing_speed, delta)
	var target_horizontal_offset := _look_ahead_sign * look_ahead_distance_x

	# -----------------------------
	# 2. 垂直软区
	# -----------------------------
	if is_on_floor():
		_camera_anchor_world_y = _smooth_value(_camera_anchor_world_y, player_y, grounded_recenter_speed, delta)
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
	# 3. 手动抬头/低头
	# -----------------------------
	var manual_vertical_target := 0.0
	if is_on_floor() and _vertical_look_timer >= vertical_look_delay:
		if direction.y < -0.5:
			manual_vertical_target = manual_look_up
		elif direction.y > 0.5:
			manual_vertical_target = manual_look_down

	# -----------------------------
	# 3.5. 下落视野辅助
	# -----------------------------
	var target_fall_look := 0.0
	if not is_on_floor() and velocity.y > fall_look_speed_threshold:
		var fall_ratio := inverse_lerp(fall_look_speed_threshold, max_fall_speed, velocity.y)
		target_fall_look = lerpf(0.0, fall_look_max_offset, fall_ratio)
	_fall_look_offset = _smooth_value(_fall_look_offset, target_fall_look, fall_look_blend_speed, delta)

	var target_vertical_offset := auto_vertical_offset + _fall_look_offset

	# 隐藏房间模式下玩家驱动镜头逐渐淡出
	target_horizontal_offset *= player_camera_weight
	target_vertical_offset *= player_camera_weight
	manual_vertical_target *= player_camera_weight

	# -----------------------------
	# 4. 边界范围（本地坐标）
	# -----------------------------
	var local_min := Vector2(-INF, -INF)
	var local_max := Vector2(INF, INF)

	if _has_camera_bounds:
		var half_screen := get_viewport_rect().size * camera.zoom * 0.5
		local_min = _camera_bounds_display_rect.position - global_position + half_screen
		local_max = _camera_bounds_display_rect.end - global_position - half_screen

	# 靠近边界时水平前视衰减，避免前视和边界互相拉扯
	if _has_camera_bounds:
		target_horizontal_offset *= _get_edge_lookahead_weight(target_horizontal_offset, local_min, local_max)

	# -----------------------------
	# 5. 受边界限制后的目标位置
	# -----------------------------
	var desired_x := base_camera_position.x + target_horizontal_offset
	var desired_y := base_camera_position.y + target_vertical_offset

	if _has_camera_bounds:
		desired_x = _soft_limit(desired_x, local_min.x, local_max.x, bounds_softness_x)
		desired_y = _soft_limit(desired_y, local_min.y, local_max.y, bounds_softness_y)

	# -----------------------------
	# 6. 平滑追目标，并在到达边界后硬夹最终位置
	# -----------------------------
	_camera_offset_x = _smooth_value(_camera_offset_x, desired_x - base_camera_position.x, camera_follow_speed_x, delta)
	_camera_offset_y = _smooth_value(_camera_offset_y, desired_y - base_camera_position.y, camera_follow_speed_y, delta)

	var final_position := base_camera_position + Vector2(_camera_offset_x, _camera_offset_y)

	# 【修复回弹】平滑追踪后，夹住最终 CameraTarget 位置，而不是直接夹 offset
	# local_min/local_max 是 final_position 的允许范围，offset 只是相对 base_camera_position 的偏移
	# 夹住 final_position 后，再反推 offset，能防止内部状态继续带着越界值
	if _has_camera_bounds:
		if local_min.x <= local_max.x:
			final_position.x = clampf(final_position.x, local_min.x, local_max.x)
		else:
			final_position.x = (local_min.x + local_max.x) * 0.5

		if local_min.y <= local_max.y:
			final_position.y = clampf(final_position.y, local_min.y, local_max.y)
		else:
			final_position.y = (local_min.y + local_max.y) * 0.5

		_camera_offset_x = final_position.x - base_camera_position.x
		_camera_offset_y = final_position.y - base_camera_position.y

	# -----------------------------
	# 7. 手动抬头/低头在剩余空间附加
	# -----------------------------
	_manual_look_offset = _smooth_value(_manual_look_offset, manual_vertical_target, manual_look_blend_speed, delta)

	if _manual_look_offset != 0.0:
		var final_manual := _manual_look_offset
		if _has_camera_bounds:
			var available_up   := local_min.y - final_position.y
			var available_down := local_max.y - final_position.y
			final_manual = clampf(final_manual, available_up, available_down)
		final_position.y += final_manual

	# -----------------------------
	# 8. 隐藏房间固定镜头混合
	# -----------------------------
	if _room_lock_weight > 0.001 and _has_camera_bounds:
		# 【修改】使用当前正在 Tween 的 display_rect 中心，而不是最终目标 rect 中心
		# 这样房间锁定目标会跟随边界过渡一起移动，不会先慢后突然加速冲向最终中心
		var display_center := _camera_bounds_display_rect.position + _camera_bounds_display_rect.size * 0.5
		var room_center_local := display_center - global_position - camera.position
		final_position = final_position.lerp(room_center_local, _room_lock_weight)

		# 【修复退出隐藏房间怪异】同步内部 offset 状态到当前真实画面位置
		# 避免退出 room lock 时，从进入房间前的旧 offset 接回来
		_camera_offset_x = final_position.x - base_camera_position.x
		_camera_offset_y = final_position.y - base_camera_position.y

	camera_target.position = final_position

func _smooth_value(current: float, target: float, speed: float, delta: float) -> float:
	if speed <= 0.0:
		return target
	var weight := 1.0 - exp(-speed * delta)
	return lerpf(current, target, weight)

func _smoothstep01(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _get_edge_lookahead_weight(offset_x: float, local_min: Vector2, local_max: Vector2) -> float:
	if edge_lookahead_fade_distance <= 0.0 or absf(offset_x) < 0.01:
		return 1.0
	if local_min.x > local_max.x:
		return 0.0
	var distance_to_edge: float = 0.0
	if offset_x > 0.0:
		distance_to_edge = local_max.x - base_camera_position.x
	else:
		distance_to_edge = base_camera_position.x - local_min.x
	return _smoothstep01(distance_to_edge / edge_lookahead_fade_distance)

func _soft_limit(value: float, min_val: float, max_val: float, softness: float) -> float:
	if min_val > max_val:
		return (min_val + max_val) * 0.5
	if softness <= 0.0:
		return clampf(value, min_val, max_val)
	if value <= min_val:
		return min_val
	if value >= max_val:
		return max_val
	if value < min_val + softness:
		var t := clampf((value - min_val) / softness, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
		return lerpf(min_val, value, t)
	if value > max_val - softness:
		var t := clampf((max_val - value) / softness, 0.0, 1.0)
		t = t * t * (3.0 - 2.0 * t)
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

	if absf(x_axis) < INPUT_DEADZONE:
		x_axis = 0.0
	if absf(y_axis) < INPUT_DEADZONE:
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
	return absf(direction.x) >= INPUT_DEADZONE

# ==========================================
# 🎥 摄影机边界系统
# ==========================================
func push_camera_bounds(source_id: int, rect: Rect2, priority: int = 0, duration: float = 0.40, lock_to_center: bool = false) -> void:
	for i in range(_camera_bounds_stack.size() - 1, -1, -1):
		if _camera_bounds_stack[i]["source_id"] == source_id:
			_camera_bounds_stack.remove_at(i)

	_camera_bounds_order_counter += 1
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
	for i in range(_camera_bounds_stack.size() - 1, -1, -1):
		if _camera_bounds_stack[i]["source_id"] == source_id:
			_camera_bounds_stack.remove_at(i)
			break
	_update_active_bounds()

func _update_active_bounds() -> void:
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

	# 【修复】用独立布尔标记判断第一次，避免 == Rect2() 浮点比较不可靠
	# 第一次直接赋值，不走 Tween，防止开场从 Rect2() 过渡到实际边界
	if not _bounds_initialized:
		_bounds_initialized = true
		_camera_bounds_display_rect = new_rect
		return

	# 从当前 display_rect 的实时值开始 Tween（可能是上次过渡的中间值）
	var from_position := _camera_bounds_display_rect.position
	var from_size := _camera_bounds_display_rect.size

	if _camera_bounds_tween and _camera_bounds_tween.is_valid():
		_camera_bounds_tween.kill()

	_camera_bounds_tween = create_tween()
	_camera_bounds_tween.set_parallel(true)
	_camera_bounds_tween.set_trans(Tween.TRANS_SINE)
	_camera_bounds_tween.set_ease(Tween.EASE_IN_OUT)
	_camera_bounds_tween.tween_method(_set_camera_bounds_rect_position, from_position, new_rect.position, duration)
	_camera_bounds_tween.tween_method(_set_camera_bounds_rect_size, from_size, new_rect.size, duration)

func _set_camera_bounds_rect_position(value: Vector2) -> void:
	_camera_bounds_display_rect.position = value

func _set_camera_bounds_rect_size(value: Vector2) -> void:
	_camera_bounds_display_rect.size = value

# ==========================================
# 🪜 单向平台穿透
# ==========================================
func request_drop_through() -> void:
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
