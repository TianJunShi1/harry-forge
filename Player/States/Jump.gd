@icon("res://icon/state.svg")
class_name PlayerstateJump extends Playerstate

@onready var fall_state: Playerstate = %Fall 
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D" 

var jump_velocity: float = -380.0
var air_speed: float = 160.0

# 【新增：是否处于弹跳板弹飞状态的标记】
var is_bouncing: bool = false 

#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	# 【核心修改】只有在“不是弹跳”的时候，才赋予普通跳跃的速度！
	# 防止弹跳板给的超大速度在这里被强行重置为 -400
	if not is_bouncing:
		player.velocity.y = jump_velocity
		
	if anim:
		anim.play("jump")

func exit() -> void:
	# 退出跳跃状态时，务必将标记重置，不影响下一次正常起跳
	is_bouncing = false
#endregion

#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	return null

func process(_delta: float) -> Playerstate:
	if player.direction.x < 0:
		anim.flip_h = true
	elif player.direction.x > 0:
		anim.flip_h = false
	return null

func physics_process(_delta: float) -> Playerstate:
	player.velocity.x = player.direction.x * air_speed
	
	# 【核心修改】如果是被弹跳板弹飞的，就无视玩家是否松开按键，禁止触发小跳减速！
	if not is_bouncing and Input.is_action_just_released("ui_accept") and player.velocity.y < 0:
		player.velocity.y *= 0.5 
		
	if player.velocity.y >= 0:
		return fall_state
		
	return null
#endregion
