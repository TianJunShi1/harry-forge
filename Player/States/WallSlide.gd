@icon("res://icon/state.svg")
class_name PlayerstateWallSlide extends Playerstate

@onready var fall_state: PlayerstateFall = %Fall
@onready var jump_state: PlayerstateJump = %Jump
@onready var wall_climb_state: PlayerstateWallClimb = %WallClimb

func init() -> void:
	pass

func enter() -> void:
	player.wall_normal = player.get_wall_normal()
	if player.anim:
		player.anim.play("fall")

func exit() -> void:
	pass

func handle_input(event: InputEvent) -> Playerstate:
	if event.is_action_pressed("jump"):
		player.wall_last_jump_normal = player.wall_normal
		player.wall_jump_lock_timer = player.wall_jump_lock_duration
		return jump_state
	return null

func process(_delta: float) -> Playerstate:
	# 面向逃离方向（与 wall_normal 同侧），而非输入方向（输入朝墙）
	if player.anim:
		player.anim.flip_h = player.wall_normal.x < 0
	return null

func physics_process(_delta: float) -> Playerstate:
	# 贴墙下滑：覆盖重力，以固定速度向下
	player.velocity.x = 0.0
	player.velocity.y = player.wall_slide_speed

	# 离墙 → Fall
	if not player.is_on_wall():
		return fall_state

	# 按离墙方向 → Fall
	if not is_zero_approx(player.direction.x) and signf(player.direction.x) == signf(player.wall_normal.x):
		return fall_state

	# 按 grab 键且有体力 → WallClimb
	if Input.is_action_pressed("grab") and player.wall_grab_timer > 0.0:
		return wall_climb_state

	return null
