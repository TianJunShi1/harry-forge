class_name Player extends CharacterBody2D

#region /// ⚙️ State Machine Variables (状态机变量)
var current_state : Playerstate
var previous_state : Playerstate
var all_states : Array[Playerstate] = []
@export var initial_state : Playerstate  # 【修改】明确指定初始状态，不再依赖节点顺序
#endregion

#region /// 🏃 Standard Variables (基础移动与输入)
var direction : Vector2 = Vector2.ZERO
const INPUT_DEADZONE : float = 0.1  # 【新增】统一输入死区阈值，防止手柄漂移

# --- 共享移动参数（供各状态读取，避免重复定义）---
var air_speed : float = 160.0      # 【新增】空中水平速度，统一供 Jump/Fall 使用
var jump_velocity : float = -380.0 # 【新增】跳跃初速度，统一供 Jump 及未来二段跳等状态使用

# --- 重力与手感调整参数 ---
var gravity : float = 900.0
var fall_gravity_multiplier : float = 1.8 # 下落时的重力倍数（放大重力加速坠落）
var max_fall_speed : float = 600.0        # 最大下落速度（防止穿透平台）

# --- 土狼时间 ---
# 【修改】用计时器替代布尔标记，更稳定可靠
# was_on_floor 布尔值在"走出边缘的瞬间"可能已经是 false，导致土狼跳失效
# 改为在地面时持续重置计时器，离地后自然倒数，Fall 状态直接检查剩余时间
var was_on_floor : bool = false       # 保留供其他状态参考，但土狼时间本身改用 coyote_timer
var coyote_timer : float = 0.0        # 土狼时间倒计时，大于 0 表示仍在土狼时间窗口内
var coyote_duration : float = 0.15    # 土狼时间窗口长度（秒）
#endregion

#region /// 🎨 Animation Variables (动画节点，统一由 Player 持有)
@onready var anim : AnimatedSprite2D = $AnimatedSprite2D  # 【新增】统一动画引用，各状态通过 player.anim 访问
#endregion

#region /// 🎬 Camera Variables (摄影机预视系统)
@export_group("Camera Look Ahead")
@export var look_ahead_distance_x: float = 45.0     # 水平看多远
@export var horizontal_deadzone_speed: float = 100.0 # 水平死区阈值（速度大于此值才允许镜头掉头）
@export var look_ahead_up: float = -80.0             # 跳跃或抬头时往上看多少（负数向上）
@export var look_ahead_down: float = 80.0            # 下落或下蹲时往下看多少（正数向下）
@export var camera_smooth_speed: float = 8.0         # 【修改】镜头跟随速度（替换原 Tween，改用 lerp 单一平滑）
@export var vertical_look_delay: float = 0.3         # 按住多久才开始抬头/低头 (例如 0.3秒)

@onready var camera_target: Marker2D = $CameraTarget
var base_camera_position: Vector2 # 记录编辑器里 Marker2D 的初始位置
var _last_facing_x: float = 1.0   # 记录角色最后的朝向（1向右，-1向左），用于防止镜头松手回弹
var _vertical_look_timer: float = 0.0 # 垂直预视的蓄力计时器
#endregion

@onready var states_node: Node = $states 
@onready var state_label: Label = $Label 

func _ready() -> void:
	# 记录运行游戏那一刻，你在编辑器里设定的 Marker2D 位置（实现所见即所得）
	if camera_target:
		base_camera_position = camera_target.position
		
	initialize_states()

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		change_state(current_state.handle_input(event))

func _physics_process(delta: float) -> void:
	# 【修改】update_direction 移到物理帧开头，保证本帧输入和物理逻辑同步
	update_direction()
	
	# 【核心修改区：不对称重力】
	if velocity.y > 0:
		# 正在下落
		velocity.y += gravity * fall_gravity_multiplier * delta
	else:
		# 正在上升
		velocity.y += gravity * delta
		
	# 限制终端速度
	velocity.y = min(velocity.y, max_fall_speed)

	# 执行状态机的物理更新
	if current_state:
		change_state(current_state.physics_process(delta))
		
	move_and_slide()
	
	# 【修改】move_and_slide 之后更新辅助标记和土狼计时器
	was_on_floor = is_on_floor()
	if is_on_floor():
		# 在地面时持续重置，保证土狼时间窗口从"离地那一刻"才开始倒数
		coyote_timer = coyote_duration
	else:
		# 离地后倒数，归零后土狼时间失效
		coyote_timer = max(coyote_timer - delta, 0.0)
	
	# 🎬 在物理移动完成后，更新摄影机逻辑
	_update_vertical_look_timer(delta) # 处理按住按键的计时逻辑
	_update_camera_look_ahead(delta)
	
func _process(delta: float) -> void:
	# 【修改】update_direction 已移到 _physics_process，这里只保留渲染帧状态更新
	if current_state:
		change_state(current_state.process(delta))

# ==========================================
# 🎬 摄影机计时核心逻辑
# ==========================================
func _update_vertical_look_timer(delta: float) -> void:
	# 只有在地面且没有产生较大水平移动时，才允许蓄力看上下
	if is_on_floor() and abs(velocity.x) < 10.0:
		if abs(direction.y) > 0.5:
			_vertical_look_timer += delta
		else:
			_vertical_look_timer = 0.0
	else:
		_vertical_look_timer = 0.0

# ==========================================
# 🎬 摄影机预视核心逻辑
# ==========================================
func _update_camera_look_ahead(delta: float) -> void:
	if not camera_target:
		return
		
	# 以记录的基准位置为起点
	var target_offset = base_camera_position
	
	# 1. 水平预视 (带有死区与记忆)
	if abs(velocity.x) > horizontal_deadzone_speed:
		_last_facing_x = sign(velocity.x)
	target_offset.x += _last_facing_x * look_ahead_distance_x
		
	# 2. 垂直预视 (根据物理速度与输入方向)
	if velocity.y < -10.0:
		# 正在上升（跳跃中）
		target_offset.y += look_ahead_up
	elif velocity.y > 10.0:
		# 正在下落
		target_offset.y += look_ahead_down
	elif is_on_floor():
		# 在地面上时，支持手动抬头和低头
		if _vertical_look_timer >= vertical_look_delay:
			if direction.y < -0.5:
				# 按下 W/向上键
				target_offset.y += look_ahead_up
			elif direction.y > 0.5:
				# 按下 S/向下键
				target_offset.y += look_ahead_down
		
	# 3. 避免目标没有变化时产生无意义的计算
	if camera_target.position.is_equal_approx(target_offset):
		return
		
	# 4. 【修改】用 lerp 单一平滑替换原来的 Tween 方案
	# 原 Tween 方案每帧 kill/create，与 Camera2D 自带 smoothing 叠加会造成双重平滑
	# 现在只保留这一套 lerp，请确认 Camera2D 的 position_smoothing_enabled 已关闭
	# 【修改】clamp 权重上限为 1.0，防止掉帧时插值系数超过 1 导致镜头过冲
	var t := minf(camera_smooth_speed * delta, 1.0)
	camera_target.position = camera_target.position.lerp(target_offset, t)

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
	
	# 【修改】改为读取 initial_state 显式指定的初始状态
	# 请在编辑器 Inspector 里把 Initial State 指定为 %Idle
	# 不再依赖子节点顺序，避免拖动节点后初始状态静默改变
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
	
	# 【修改】应用死区裁切，防止手柄摇杆漂移导致意外输入
	if abs(x_axis) < INPUT_DEADZONE:
		x_axis = 0.0
	if abs(y_axis) < INPUT_DEADZONE:
		y_axis = 0.0
		
	direction = Vector2(x_axis, y_axis)

# ==========================================
# 🎨 动画辅助逻辑
# ==========================================
func update_facing() -> void:
	# 【新增】统一朝向翻转逻辑，各状态调用 player.update_facing() 即可
	# 不再在每个状态里重复写 anim.flip_h 判断
	if direction.x < 0:
		anim.flip_h = true
	elif direction.x > 0:
		anim.flip_h = false

func has_horizontal_input() -> bool:
	# 【新增】封装水平输入判断，状态脚本不需要直接接触 INPUT_DEADZONE 常量
	# 以后调整死区只改这一处即可
	return abs(direction.x) >= INPUT_DEADZONE

func apply_bounce(force: float) -> void:
	velocity.y = -force
	for state in all_states:
		if state is PlayerstateJump:
			state.is_bouncing = true 
			change_state(state)
			break
