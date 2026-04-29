class_name BouncePad extends Area2D

@export var bounce_force: float = 500.0

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("apply_bounce"):
		body.apply_bounce(bounce_force)
