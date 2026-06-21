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
		player.consume_wall_jump_stamina()
		return jump_state
	return null

func process(_delta: float) -> Playerstate:
	player.update_facing()
	return null

func physics_process(delta: float) -> Playerstate:
	# 释放 grab 键 → WallSlide，不继续消耗体力
	if not Input.is_action_pressed("grab"):
		return wall_slide_state

	# 离墙 → Fall
	if not player.is_on_wall():
		return fall_state

	# 攀爬移动：上爬高消耗，悬挂低消耗，下移不消耗
	player.velocity.x = 0.0
	var stamina_drain := player.wall_stamina_hold_drain
	if player.direction.y < 0.0:
		player.velocity.y = -player.wall_climb_speed
		stamina_drain = player.wall_stamina_climb_drain
	elif player.direction.y > 0.0:
		player.velocity.y = player.wall_climb_drop_speed
		stamina_drain = 0.0
	else:
		player.velocity.y = 0.0

	player.spend_wall_stamina(stamina_drain * delta)

	# 体力耗尽 → WallSlide，而不是直接进入自由落体
	if not player.can_grab_wall():
		return wall_slide_state

	return null
