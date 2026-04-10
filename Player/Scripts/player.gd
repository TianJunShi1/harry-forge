class_name Player extends CharacterBody2D

#region /// State Machine Variables
# 当前状态与上一个状态
var current_state : Playerstate
var previous_state : Playerstate

# 保存所有状态的引用
var all_states : Array[Playerstate] = []
#endregion

#region /// Standard Variables
var direction : Vector2 = Vector2.ZERO
var gravity : float = 900
#endregion

@onready var states_node: Node = $states # 假设你的状态子节点都放在名为 "states" 的 Node 下

func _ready() -> void:
	initialize_states()

func _unhandled_input(event: InputEvent) -> void:
	if current_state:
		change_state(current_state.handle_input(event))

func _physics_process(delta: float) -> void:
	velocity.y += gravity * delta
	if current_state:
		change_state(current_state.physics_process(delta))
	move_and_slide()
	
func _process(delta: float) -> void:
	update_direction()
	if current_state:
		change_state(current_state.process(delta))

# 初始化状态机
func initialize_states() -> void:
	all_states.clear()
	
	for c in states_node.get_children():
		if c is Playerstate:
			all_states.append(c)
			c.player = self # 将 Player 自身的引用传递给 State
			c.init()        # 执行状态的初始化逻辑
			
	if all_states.is_empty():
		push_warning("Player 找不到任何状态！请检查 $states 节点。")
		return
		
	# 默认进入列表中的第一个状态
	change_state(all_states[0])

# 执行状态切换
func change_state(new_state : Playerstate) -> void:
	# 如果没有新状态，或者新状态就是当前状态，则忽略
	if new_state == null or new_state == current_state:
		return
	
	if current_state:
		current_state.exit()
		previous_state = current_state
		
	current_state = new_state
	current_state.enter()

# 更新输入方向
func update_direction() -> void:
	direction = Input.get_vector("left", "right", "up", "down")
