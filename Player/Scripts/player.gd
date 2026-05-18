class_name Player extends CharacterBody2D

#region /// ⚙️ State Machine Variables
var current_state : Playerstate
var all_states : Array[Playerstate] = []
@export var initial_state : Playerstate
#endregion

#region /// 🏃 Movement & Input
var direction : Vector2 = Vector2.ZERO
const INPUT_DEADZONE : float = 0.1
# request_drop_through 时给 velocity.y 的最小下沉速度，防止脚还卡在平台上不掉
const DROP_THROUGH_MIN_VELOCITY : float = 30.0

@export var air_speed : float = 160.0
@export var jump_velocity : float = -380.0

@export var gravity : float = 900.0
@export var fall_gravity_multiplier : float = 1.8
@export var max_fall_speed : float = 600.0

var coyote_timer : float = 0.0
@export var coyote_duration : float = 0.15

const ONE_WAY_PLATFORM_LAYER : int = 3
@export var drop_through_duration : float = 0.18
var drop_through_timer : float = 0.0
#endregion

## 当玩家被弹跳板抛起时发出。Jump 状态监听此 signal 以避免被普通跳跃逻辑覆盖速度。
signal bounce_requested

#region /// 🎨 Animation
@onready var anim : AnimatedSprite2D = $AnimatedSprite2D
#endregion

@onready var states_node: Node = $states
@onready var state_label: Label = $Label


func _enter_tree() -> void:
	# _enter_tree 先于 _ready 执行，确保同场景的 GameCamera._ready() 调用
	# get_first_node_in_group("player") 时玩家已在组内，摄像机可立即找到目标。
	add_to_group("player")


func _ready() -> void:
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
	velocity.y = minf(velocity.y, max_fall_speed)

	if current_state:
		change_state(current_state.physics_process(delta))

	move_and_slide()

	if drop_through_timer > 0.0:
		drop_through_timer -= delta
		if drop_through_timer <= 0.0:
			reset_drop_through()

	if is_on_floor():
		coyote_timer = coyote_duration
	else:
		coyote_timer = maxf(coyote_timer - delta, 0.0)


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


## GameCamera2D 调用此方法获取视线上下意图。
## 仅在地面静止时有效；-1=向上看，0=不偏移，1=向下看。
func get_camera_look_y_intent() -> float:
	if is_on_floor() and not has_horizontal_input():
		return direction.y
	return 0.0


# ==========================================
# 🪜 单向平台穿透
# ==========================================
func request_drop_through() -> void:
	if drop_through_timer > 0.0:
		return
	set_collision_mask_value(ONE_WAY_PLATFORM_LAYER, false)
	drop_through_timer = drop_through_duration
	velocity.y = maxf(velocity.y, DROP_THROUGH_MIN_VELOCITY)


## 立刻结束 drop_through：恢复单向平台碰撞、清零 timer。
## 弹跳、死亡复活、强制传送都应调用本方法，避免遗留 collision_mask 让玩家穿地。
func reset_drop_through() -> void:
	if drop_through_timer > 0.0 or not get_collision_mask_value(ONE_WAY_PLATFORM_LAYER):
		set_collision_mask_value(ONE_WAY_PLATFORM_LAYER, true)
	drop_through_timer = 0.0


## 弹跳板触发；Jump 状态通过 bounce_requested signal 接管状态切换，
## 避免 Player 反向耦合具体状态类。
func apply_bounce(force: float) -> void:
	# 防止 drop_through 期间被弹起后还穿透单向平台
	reset_drop_through()
	velocity.y = -force
	bounce_requested.emit()
