extends CharacterBody3D
@onready var anim_tree = $starblade_wielder_rootmotion_test/AnimationTree

func _physics_process(delta):
	var root_motion = anim_tree.get_root_motion_position()
	var rm_accum = anim_tree.get_root_motion_position_accumulator()
	#velocity = rm_accum
	velocity += root_motion * 1000
	print(velocity)
	move_and_slide()
	velocity = Vector3()
