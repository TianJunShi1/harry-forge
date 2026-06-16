extends Area2D

@export var damage: int = 1
@export var interval: float = 0.8
@export var size: Vector2 = Vector2(32, 32)

var _timer: float = 0.0
var _inside: bool = false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	queue_redraw()


func _physics_process(delta: float) -> void:
	if not _inside:
		return
	_timer += delta
	if _timer >= interval:
		_timer = 0.0
		var player := get_tree().get_first_node_in_group(&"player") as Player
		if is_instance_valid(player):
			player.take_damage(damage)


func _draw() -> void:
	draw_rect(Rect2(-size * 0.5, size), Color(1, 0.1, 0.1, 0.45))
	draw_rect(Rect2(-size * 0.5, size), Color(1, 0.2, 0.2, 1), false, 1.0)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_inside = true
		_timer = interval  # 入场立即扣第一次


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_inside = false
		_timer = 0.0
