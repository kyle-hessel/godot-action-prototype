extends CharacterBody3D

class_name Enemy

@onready var collision_shape : CollisionShape3D = $CollisionShape3D

func _physics_process(delta: float) -> void:
	#move_and_slide()
	pass
