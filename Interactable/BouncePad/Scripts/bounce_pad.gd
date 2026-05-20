class_name BouncePad extends Area2D

@export var bounce_force: float = 500.0
## 触发后的冷却时间，避免单次重叠在多帧内被 body_entered 重复触发
@export var cooldown: float = 0.1

var _cooldown_timer: float = 0.0

@onready var _prompt: PromptHint = $PromptHint


func _ready() -> void:
	# 防御性 connect：即便 .tscn 的信号连接被意外删掉也能工作
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not $ProximityArea.body_entered.is_connected(_on_proximity_entered):
		$ProximityArea.body_entered.connect(_on_proximity_entered)
	if not $ProximityArea.body_exited.is_connected(_on_proximity_exited):
		$ProximityArea.body_exited.connect(_on_proximity_exited)
	_prompt.follow_target = self


func _process(delta: float) -> void:
	if _cooldown_timer > 0.0:
		_cooldown_timer -= delta


func _on_body_entered(body: Node2D) -> void:
	if _cooldown_timer > 0.0:
		return
	if body is Player:
		_cooldown_timer = cooldown
		body.apply_bounce(bounce_force)


func _on_proximity_entered(body: Node2D) -> void:
	if body is Player:
		_prompt.show_hint()


func _on_proximity_exited(body: Node2D) -> void:
	if body is Player:
		_prompt.hide_hint()
