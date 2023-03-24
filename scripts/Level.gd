extends Node3D


var physics_tick: int = ProjectSettings.get_setting("physics/common/physics_ticks_per_second")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	randomize()
	# relocate this somewhere else later, not in level script. Preferably in a singleton or something.
	Engine.max_fps = physics_tick # maybe don't let this go above physics_tick
	
	match physics_tick:
		30:
			ProjectSettings.set_setting("physics/common/max_physics_steps_per_frame", 4)
		60:
			ProjectSettings.set_setting("physics/common/max_physics_steps_per_frame", 8)
		120:
			ProjectSettings.set_setting("physics/common/max_physics_steps_per_frame", 16)
		144:
			ProjectSettings.set_setting("physics/common/max_physics_steps_per_frame", 20)
		240:
			ProjectSettings.set_setting("physics/common/max_physics_steps_per_frame", 32)
		_:
			ProjectSettings.set_setting("physics/common/max_physics_steps_per_frame", 16)
	#print(physics_tick)
	#print(ProjectSettings.get_setting("physics/common/max_physics_steps_per_frame"))
	
func _physics_process(delta) -> void:
	get_tree().call_group("enemies", "update_nav_target_pos", $Player.global_position)
	#print(delta)
