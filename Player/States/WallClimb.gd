@icon("res://icon/state.svg")
class_name PlayerstateWallClimb extends Playerstate

@onready var fall_state: PlayerstateFall = %Fall
@onready var jump_state: PlayerstateJump = %Jump
@onready var wall_slide_state: PlayerstateWallSlide = %WallSlide

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
	player.update_facing()
	return null

func physics_process(delta: float) -> Playerstate:
	player.wall_grab_timer -= delta

	# 体力耗尽 → WallSlide
	if player.wall_grab_timer <= 0.0:
		player.wall_grab_timer = 0.0
		return fall_state

	# 释放 grab 键 → WallSlide
	if not Input.is_action_pressed("grab"):
		return wall_slide_state

	# 离墙 → Fall
	if not player.is_on_wall():
		return fall_state

	# 攀爬移动：上/下键控制，不按则悬挂
	player.velocity.x = 0.0
	if player.direction.y < 0.0:
		player.velocity.y = -player.wall_climb_speed
	elif player.direction.y > 0.0:
		player.velocity.y = player.wall_climb_drop_speed
	else:
		player.velocity.y = 0.0

	return null
