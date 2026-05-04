class_name BouncePad extends Area2D

@export var bounce_force: float = 500.0

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.apply_bounce(bounce_force)
