class_name Player extends CharacterBody2D

#region /// ⚙️ State Machine Variables (状态机变量)
var current_state : Playerstate
var previous_state : Playerstate
var all_states : Array[Playerstate] = []
#endregion

#region /// 🏃 Standard Variables (基础移动与输入)
var direction : Vector2 = Vector2.ZERO

# --- 重力与手感调整参数 ---
var gravity : float = 900.0
var fall_gravity_multiplier : float = 1.8 # 下落时的重力倍数（放大重力加速坠落）
var max_fall_speed : float = 600.0        # 最大下落速度（防止穿透平台）
#endregion

#region /// 🎬 Camera Variables (摄影机预视系统)
@export_group("Camera Look Ahead")
@export var look_ahead_distance_x: float = 45.0    # 水平看多远
@export var horizontal_deadzone_speed: float = 100.0 # 水平死区阈值（速度大于此值才允许镜头掉头）
@export var look_ahead_up: float = -80.0           # 跳跃或抬头时往上看多少（负数向上）
@export var look_ahead_down: float = 80.0          # 下落或下蹲时往下看多少（正数向下）
@export var camera_tween_duration: float = 1     # 镜头移动的平滑时间
@export var vertical_look_delay: float = 0.3       # 【新增】按住多久才开始抬头/低头 (例如 0.5秒)

@onready var camera_target: Marker2D = $CameraTarget
var _camera_tween: Tween 
var base_camera_position: Vector2 # 记录编辑器里 Marker2D 的初始位置
var _last_facing_x: float = 1.0   # 记录角色最后的朝向（1向右，-1向左），用于防止镜头松手回弹
var _vertical_look_timer: float = 0.0 # 【新增】垂直预视的蓄力计时器
#endregion

@onready var states_node: Node = $states 
@onready var state_label: Label = $Label 

func _ready() -> void:
	# 记录运行游戏那一刻，你在编辑器里设定的 Marker2D位置 (实现所见即所得)
	if camera_target:
		base_camera_position = camera_target.position
		
	initialize_states()

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		change_state(current_state.handle_input(event))

func _physics_process(delta: float) -> void:
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
	
	# 🎬 在物理移动完成后，更新摄影机逻辑
	_update_vertical_look_timer(delta) # 【新增】处理按住按键的计时逻辑
	_update_camera_look_ahead()
	
func _process(delta: float) -> void:
	update_direction()
	if current_state:
		change_state(current_state.process(delta))

# ==========================================
# 🎬 摄影机计时核心逻辑 【新增函数】
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
func _update_camera_look_ahead() -> void:
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
		# 在地面上时，支持手动抬头和低头 【此处新增计时器判断】
		if _vertical_look_timer >= vertical_look_delay:
			if direction.y < -0.5:
				# 按下 W/向上键
				target_offset.y += look_ahead_up
			elif direction.y > 0.5:
				# 按下 S/向下键
				target_offset.y += look_ahead_down
		
	# 3. 避免重复生成相同的动画以节省性能
	if camera_target.position == target_offset:
		return
		
	# 4. 执行平滑过渡 Tween
	if _camera_tween and _camera_tween.is_valid():
		_camera_tween.kill() # 打断旧的补间动画
		
	_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_camera_tween.tween_property(camera_target, "position", target_offset, camera_tween_duration)

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
	var x_axis = Input.get_axis("left","right")
	var y_axis = Input.get_axis("up","down")
	direction = Vector2(x_axis,y_axis)
	
func apply_bounce(force: float) -> void:
	velocity.y = -force
	for state in all_states:
		if state is PlayerstateJump:
			state.is_bouncing = true 
			change_state(state)
			break
