@icon("res://icon/state.svg")
class_name PlayerstateCrouch extends Playerstate

# --- 节点与状态引用 ---
@onready var idle_state: PlayerstateIdle = %Idle
@onready var anim: AnimatedSprite2D = $"../../AnimatedSprite2D"


#region /// 核心状态生命周期
## 当这个状态第一次被收集并初始化时执行（只执行一次）
func init() -> void:
	pass

## 当进入这个状态时执行
func enter() -> void:
	if anim:
		anim.play("crouch")

## 当退出这个状态时执行
func exit() -> void:
	pass
#endregion


#region /// 帧更新与输入处理
## 处理输入事件
func handle_input(_event : InputEvent) -> Playerstate:
	return null

## 渲染帧更新
func process(_delta: float) -> Playerstate:
	return null

## 物理帧更新
func physics_process(_delta: float) -> Playerstate:
	# 1. 如果玩家松开了下蹲键（S键，即 y 轴方向不再向下），回到待机状态
	if player.direction.y <= 0:
		return idle_state
		
	# 2. 目前不添加任何移动功能，确保角色蹲下时水平速度为 0
	player.velocity.x = move_toward(player.velocity.x, 0, 1000 * _delta)
	
	return null
#endregion
