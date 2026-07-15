@icon("res://icon/state.svg")
class_name PlayerstateJump extends Playerstate

@onready var fall_state: PlayerstateFall = %Fall
@onready var wall_slide_state: PlayerstateWallSlide = %WallSlide

# 普通跳跃上升曲线。先集中在 Jump 状态中，避免影响弹跳板和墙跳。
@export_group("Jump Feel")
@export var jump_hold_duration: float = 0.10
@export_range(0.1, 1.0, 0.05) var jump_hold_gravity_multiplier: float = 0.40
@export var apex_velocity_threshold: float = 65.0
@export_range(0.1, 1.0, 0.05) var apex_gravity_multiplier: float = 0.50
@export_range(0.1, 1.0, 0.05) var jump_cut_multiplier: float = 0.45
@export var jump_horizontal_boost: float = 18.0

var jump_hold_timer: float = 0.0
var is_bouncing: bool = false
var is_wall_jump: bool = false


func init() -> void:
	# 弹跳板触发时由 Player 发 signal，本状态接管切换。
	if not player.bounce_requested.is_connected(_on_bounce_requested):
		player.bounce_requested.connect(_on_bounce_requested)


func _on_bounce_requested() -> void:
	is_bouncing = true
	player.call_deferred("change_state", self)


func enter() -> void:
	player.coyote_timer = 0.0
	is_wall_jump = player.wall_normal != Vector2.ZERO and player.wall_jump_lock_timer > 0.0

	if is_wall_jump:
		# 墙跳暂时保持原有曲线，之后单独调节墙跳手感。
		player.velocity.y = player.jump_velocity
		player.velocity.x = player.wall_normal.x * player.wall_jump_h_speed
		if player.anim:
			player.anim.flip_h = player.wall_normal.x < 0
		player.wall_normal = Vector2.ZERO
		jump_hold_timer = 0.0
	else:
		player.wall_normal = Vector2.ZERO
		if not is_bouncing:
			player.velocity.y = player.jump_velocity
			jump_hold_timer = jump_hold_duration

			# 跑跳瞬间增加少量水平推进，强化地面移动到起跳的连续性。
			if player.has_horizontal_input():
				player.velocity.x += player.direction.x * jump_horizontal_boost
		else:
			jump_hold_timer = 0.0

	if player.anim:
		player.anim.play("jump")


func exit() -> void:
	is_bouncing = false
	is_wall_jump = false
	jump_hold_timer = 0.0


func handle_input(_event : InputEvent) -> Playerstate:
	return null


func process(_delta: float) -> Playerstate:
	# 锁定期内保持登墙跳设定的朝向，不被输入方向覆盖。
	if player.wall_jump_lock_timer <= 0.0:
		player.update_facing()
	return null


func physics_process(delta: float) -> Playerstate:
	# 登墙跳锁定期内不覆盖横向速度，让推力弧线自然衰减。
	if player.wall_jump_lock_timer <= 0.0:
		var speed_factor := 1.0
		if player.wall_last_jump_normal != Vector2.ZERO \
				and not is_zero_approx(player.direction.x) \
				and signf(player.direction.x) != signf(player.wall_last_jump_normal.x):
			speed_factor = player.wall_return_speed_factor
		var target := player.direction.x * player.air_speed * speed_factor
		player.velocity.x = move_toward(player.velocity.x, target, player.air_acceleration * delta)

	# Player 在进入状态前已经施加了一次普通重力；这里补偿成所需倍率。
	# 弹跳板和墙跳不使用普通跳跃的按住增高与顶点滞空。
	if not is_bouncing and not is_wall_jump and player.velocity.y < 0.0:
		var gravity_multiplier := 1.0
		if absf(player.velocity.y) <= apex_velocity_threshold:
			gravity_multiplier = apex_gravity_multiplier
		elif jump_hold_timer > 0.0 and Input.is_action_pressed("jump"):
			gravity_multiplier = jump_hold_gravity_multiplier

		player.velocity.y += player.gravity * (gravity_multiplier - 1.0) * delta
		jump_hold_timer = maxf(jump_hold_timer - delta, 0.0)

	if not is_bouncing and Input.is_action_just_released("jump") and player.velocity.y < 0.0:
		player.velocity.y *= jump_cut_multiplier
		jump_hold_timer = 0.0

	if player.velocity.y >= 0.0:
		return fall_state

	return null
