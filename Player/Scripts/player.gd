class_name Player extends CharacterBody2D

#region /// State Machine Variables
var current_state : Playerstate
var previous_state : Playerstate
var all_states : Array[Playerstate] = []
#endregion

#region /// Standard Variables
var direction : Vector2 = Vector2.ZERO

# --- 重力与手感调整参数 ---
var gravity : float = 900.0
var fall_gravity_multiplier : float = 1.8 # 下落时的重力倍数（1.8表示下落重力是上升的1.8倍）
var max_fall_speed : float = 700.0        # 最大下落速度（终端速度），防止速度过快穿透地板
#endregion

@onready var states_node: Node = $states 
@onready var state_label: Label = $Label 

func _ready() -> void:
	initialize_states()

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		change_state(current_state.handle_input(event))

func _physics_process(delta: float) -> void:
	# 【核心修改区：不对称重力】
	if velocity.y > 0:
		# 正在下落：施加经过倍数放大的重力，让角色迅速坠落
		velocity.y += gravity * fall_gravity_multiplier * delta
	else:
		# 正在上升（跳跃阶段）：施加正常的基础重力，让角色在空中停留更久
		velocity.y += gravity * delta
		
	# 限制最大下落速度，防止角色像炮弹一样砸穿地板碰撞体
	velocity.y = min(velocity.y, max_fall_speed)

	# 执行状态机的更新
	if current_state:
		change_state(current_state.physics_process(delta))
		
	move_and_slide()
	
func _process(delta: float) -> void:
	update_direction()
	if current_state:
		change_state(current_state.process(delta))

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
	
# 暴露给外部环境调用的方法：施加弹跳
func apply_bounce(force: float) -> void:
	# 1. 赋予弹射速度
	velocity.y = -force
	
	# 2. 找到跳跃状态，打上“弹飞”标记，并切换过去
	# 注意这里加入了 state.is_bouncing = true
	for state in all_states:
		if state is PlayerstateJump:
			state.is_bouncing = true 
			change_state(state)
			break
