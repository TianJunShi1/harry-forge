class_name NpcSample extends Node2D

## wait 动画随机触发间隔范围（秒）
@export var idle_variation_interval: Vector2 = Vector2(6.0, 14.0)

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _zone: Area2D = $DetectionZone

var _player: Player = null
var _is_talking: bool = false
var _variation_timer: float = 0.0


func _ready() -> void:
	_zone.body_entered.connect(_on_body_entered)
	_zone.body_exited.connect(_on_body_exited)
	# animation_looped：循环动画每完成一次循环时触发（loop=true 时有效）
	_anim.animation_looped.connect(_on_animation_looped)
	_anim.play(&"idle")
	_reset_variation_timer()


func _process(delta: float) -> void:
	if _player != null:
		_anim.flip_h = _player.global_position.x < global_position.x
		if Input.is_action_just_pressed(&"action"):
			_is_talking = not _is_talking
			_anim.play(&"talk" if _is_talking else &"idle")
			if not _is_talking:
				_reset_variation_timer()

	# wait 变化动画仅在 idle 状态下计时触发
	if _anim.animation == &"idle":
		_variation_timer -= delta
		if _variation_timer <= 0.0:
			_anim.play(&"wait")


func _on_animation_looped() -> void:
	# wait 播完一次完整循环后回到 idle
	if _anim.animation == &"wait":
		_anim.play(&"idle")
		_reset_variation_timer()


func _on_body_entered(body: Node2D) -> void:
	if body is not Player:
		return
	_player = body as Player


func _on_body_exited(body: Node2D) -> void:
	if body is not Player:
		return
	_player = null
	if _is_talking:
		_is_talking = false
		_anim.play(&"idle")
		_reset_variation_timer()


func _reset_variation_timer() -> void:
	_variation_timer = randf_range(idle_variation_interval.x, idle_variation_interval.y)
