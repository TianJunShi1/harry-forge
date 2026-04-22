extends Area2D

# 弹射力度，可以根据不同的物品设置不同的弹力
@export var bounce_force: float = 400.0 

func _on_body_entered(body: Node2D) -> void:
	if body.has_method("apply_bounce"):
		body.apply_bounce(bounce_force)
		
		# 可选：播放喷射蒸汽的动画或音效
		# $AnimatedSprite2D.play("bounce")
