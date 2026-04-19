@icon("res://icon/state.svg")
class_name PlayerstateCrouch extends Playerstate

# --- 节点与状态引用 ---
@onready var idle_state: PlayerstateIdle = $"../Idle"
@onready var jump_state: Playerstate = $"../Jump" # 【恢复保留】跳跃状态引用
@onready var fall_state: Playerstate = $"../Fall" # 下落状态引用
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D"
@onready var one_way_platform_ray_cast: RayCast2D = $"../../OneWayPlatformRayCast"

# 下蹲时的摩擦力
var friction: float = 1000.0 


#region /// 核心状态生命周期
func init() -> void:
	pass

func enter() -> void:
	if anim:
		anim.play("crouch")

func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
func handle_input(_event : InputEvent) -> Playerstate:
	# 【保留功能】：在平地上蹲伏时，依然可以通过按跳跃键直接起跳
	if _event.is_action_pressed("ui_accept") and player.is_on_floor():
		return jump_state
	return null

func process(_delta: float) -> Playerstate:
	return null

func physics_process(_delta: float) -> Playerstate:
	# 【新增功能】：进入下蹲状态后，如果脚下检测到是单向平台，直接下落
	if one_way_platform_ray_cast.is_colliding():
		player.position.y += 1.0 
		return fall_state
		
	# 如果松开 S 键（或者方向不再向下），返回待机状态
	if player.direction.y <= 0:
		return idle_state
		
	# 平地上的摩擦力滑行逻辑（依然保留）
	player.velocity.x = move_toward(player.velocity.x, 0, friction * _delta)
	
	return null
#endregion
