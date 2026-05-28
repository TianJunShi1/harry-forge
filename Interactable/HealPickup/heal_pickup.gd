extends Area2D

@export var heal_amount: int = 1
@export var radius: float = 8.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	queue_redraw()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, Color(0.2, 1, 0.4, 0.5))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, Color(0.3, 1, 0.5, 1), 1.0)
	# 十字
	draw_line(Vector2(-radius * 0.4, 0), Vector2(radius * 0.4, 0), Color(1, 1, 1, 0.9), 1.5)
	draw_line(Vector2(0, -radius * 0.4), Vector2(0, radius * 0.4), Color(1, 1, 1, 0.9), 1.5)


func _on_body_entered(body: Node2D) -> void:
	if not (body is Player):
		return
	var player := body as Player
	if player.current_hp >= player.max_hp:
		return
	player.heal(heal_amount)
	queue_free()
