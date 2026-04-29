class_name Player extends CharacterBody2D

#region /// ⚙️ State Machine Variables
var current_state : Playerstate
var all_states : Array[Playerstate] = []
@export var initial_state : Playerstate
#endregion

#region /// 🏃 Movement & Input
var direction : Vector2 = Vector2.ZERO
const INPUT_DEADZONE : float = 0.1

var air_speed : float = 160.0
var jump_velocity : float = -380.0

var gravity : float = 900.0
var fall_gravity_multiplier : float = 1.8
var max_fall_speed : float = 600.0

var coyote_timer : float = 0.0
var coyote_duration : float = 0.15

const ONE_WAY_PLATFORM_LAYER : int = 3
@export var drop_through_duration : float = 0.18
var drop_through_timer : float = 0.0
#endregion

#region /// 🎨 Animation
@onready var anim : AnimatedSprite2D = $AnimatedSprite2D
#endregion

@onready var states_node: Node = $states
@onready var state_label: Label = $Label


func _ready() -> void:
	add_to_group("player")
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


func _process(delta: float) -> void:
	if current_state:
		change_state(current_state.process(delta))


# ==========================================
# ⚙️ 状态机
# ==========================================
func initialize_states() -> void:
	all_states.clear()

	for c in states_node.get_children():
		if c is Playerstate:
			all_states.append(c)
			c.player = self
			c.init()

	if all_states.is_empty():
		push_error("Player 找不到任何状态！请检查 $states 节点。")
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


## GameCamera2D 调用此方法获取前视意图。
## 返回 -1(左)、0(停止)、1(右)。
func get_camera_facing_intent() -> float:
	return direction.x


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
			call_deferred("change_state", state)
			return
