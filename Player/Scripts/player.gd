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
# 在地面时持续重置计时器，离地后自然倒数，Fall 状态直接检查剩余时间
var coyote_timer : float = 0.0        # 土狼时间倒计时，大于 0 表示仍在土狼时间窗口内
var coyote_duration : float = 0.15    # 土狼时间窗口长度（秒）
#endregion

#region /// 🎨 Animation Variables (动画节点，统一由 Player 持有)
@onready var anim : AnimatedSprite2D = $AnimatedSprite2D  # 【新增】统一动画引用，各状态通过 player.anim 访问
#endregion

#region /// 🎬 Camera Variables (摄影机预视系统)
@export_group("Camera Look Ahead")
@export var look_ahead_distance_x: float = 50.0      # 水平看多远
@export var horizontal_deadzone_speed: float = 90.0   # 水平死区阈值（速度大于此值才允许镜头掉头）
@export var horizontal_return_speed: float = 2.0      # 【新增】停下后镜头回中的速度（越小越慢）
@export var manual_look_up: float = -20.0             # 手动抬头时的独立偏移量（负数向上）
@export var manual_look_down: float = 20.0            # 手动低头时的独立偏移量（正数向下）
@export var camera_smooth_speed: float = 1.0          # 镜头整体跟随速度（lerp 权重基数）
@export var vertical_smooth_speed: float = 3.0        # 垂直方向单独平滑速度，减缓跳跃时上下浮动
@export var vertical_deadzone: float = 40.0           # 【新增】垂直软区大小（像素）。角色在此范围内时镜头不追
@export var vertical_look_delay: float = 0.3          # 按住多久才开始抬头/低头

@onready var camera_target: Marker2D = $CameraTarget
var base_camera_position: Vector2       # 记录编辑器里 Marker2D 的初始位置
var _last_facing_x: float = 0.0        # 【修改】初始值改为 0，停止时回中而非默认偏右
var _facing_x_target: float = 0.0     # 【新增】水平朝向的目标值，用 lerp 平滑过渡而非瞬切
var _vertical_look_timer: float = 0.0  # 垂直预视的蓄力计时器
var _current_vertical_offset: float = 0.0  # 当前垂直偏移的平滑中间值
var _camera_anchor_y: float = 0.0     # 【新增】垂直软区的锚点，只有超出软区才更新
#endregion

@onready var states_node: Node = $states 
@onready var state_label: Label = $Label 

func _ready() -> void:
	# 记录运行游戏那一刻，你在编辑器里设定的 Marker2D 位置（实现所见即所得）
	if camera_target:
		base_camera_position = camera_target.position
	
	# 锚点用世界坐标初始化，和后续 player_y 保持同一坐标系
	_camera_anchor_y = global_position.y
	
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
	
	# 【修改】move_and_slide 之后更新土狼计时器
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
	
	# -----------------------------------------------
	# 1. 水平预视（带死区、朝向记忆、停下回中）
	# -----------------------------------------------
	# 【逻辑说明】
	# 原来：速度超阈值就记录朝向，然后永远保持那个方向的偏置
	# 现在：速度超阈值时，把"目标朝向"设为当前方向（1或-1）
	#       速度低于阈值时，目标朝向归零（回中）
	#       用 lerp 平滑过渡，避免镜头瞬间切换
	# 为什么这样做：停下来时镜头慢慢回中，给玩家更自然的构图感
	# 追逐场景里一直跑，目标朝向始终是运动方向，前视效果完整保留
	if abs(velocity.x) > horizontal_deadzone_speed:
		_facing_x_target = sign(velocity.x)
	else:
		# 速度低于阈值，目标回中（0 = 居中，不偏任何一侧）
		_facing_x_target = 0.0
	
	# 用 lerp 平滑过渡朝向值，避免镜头"啪"地跳到另一侧
	var t_facing := minf(horizontal_return_speed * delta, 1.0)
	_last_facing_x = lerp(_last_facing_x, _facing_x_target, t_facing)
	target_offset.x += _last_facing_x * look_ahead_distance_x

	# -----------------------------------------------
	# 2. 垂直软区（Soft Zone）
	# -----------------------------------------------
	# 【修正】统一使用世界坐标
	# player_y 和 _camera_anchor_y 都是世界坐标，差值 vertical_drift 就是像素偏移
	# 可以安全叠加到 target_offset.y 上，坐标系完全一致
	var player_y := global_position.y
	
	if player_y < _camera_anchor_y - vertical_deadzone:
		# 角色跑到软区上方，锚点跟上去
		_camera_anchor_y = player_y + vertical_deadzone
	elif player_y > _camera_anchor_y + vertical_deadzone:
		# 角色跑到软区下方，锚点跟下去
		_camera_anchor_y = player_y - vertical_deadzone
	
	# drift = 角色当前位置超出锚点的量，软区内时为 0，超出时等于超出的像素数
	var vertical_drift := player_y - _camera_anchor_y
	
	# 3. 手动抬头/低头（在软区基础上叠加，保持现有功能）
	var target_vertical_offset: float = vertical_drift
	if is_on_floor():
		if _vertical_look_timer >= vertical_look_delay:
			if direction.y < -0.5:
				target_vertical_offset += manual_look_up
			elif direction.y > 0.5:
				target_vertical_offset += manual_look_down
	
	# 4. 垂直方向平滑插值，避免锚点跳动时镜头硬切
	var t_vertical := minf(vertical_smooth_speed * delta, 1.0)
	_current_vertical_offset = lerp(_current_vertical_offset, target_vertical_offset, t_vertical)
	target_offset.y += _current_vertical_offset
		
	# 5. 避免目标没有变化时产生无意义的计算
	if camera_target.position.is_equal_approx(target_offset):
		return
		
	# 6. 整体平滑跟随
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
