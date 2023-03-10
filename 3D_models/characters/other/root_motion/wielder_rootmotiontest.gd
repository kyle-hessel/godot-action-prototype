extends CharacterBody3D
@onready var anim_tree = $starblade_wielder_rootmotion_test/AnimationTree

func _physics_process(delta):
	var root_motion: Vector3 = anim_tree.get_root_motion_position().rotated(Vector3(0.0, 1.0, 0.0), rotation.y)
	#var rm_rotation = anim_tree.get_root_motion_rotation()
	anim_tree.get_root_motion_position()
	#var rm_accum = anim_tree.get_root_motion_position_accumulator()
	velocity += root_motion * 100
	#set_quaternion(get_quaternion() * rm_rotation) # didn't work
	print(velocity)
	move_and_slide()
	velocity = Vector3()
