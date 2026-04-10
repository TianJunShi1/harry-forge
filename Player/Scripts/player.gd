class_name Player extends CharacterBody2D

#region /// State Machine Variables
var current_state : Playerstate
var previous_state : Playerstate
var all_states : Array[Playerstate] = []
#endregion

#region /// Standard Variables
var direction : Vector2 = Vector2.ZERO
var gravity : float = 900
#endregion

@onready var states_node: Node = $states 

# 【新增】获取 Label 节点 (假设你的 Label 节点名字就叫 "Label")
@onready var state_label: Label = $Label 

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
	
	# 【新增】更新 Label 显示当前状态的名字
	if state_label:
		state_label.text = current_state.name

func update_direction() -> void:
	var x_axis = Input.get_axis("left","right")
	var y_axis = Input.get_axis("up","down")
	direction = Vector2(x_axis,y_axis)
