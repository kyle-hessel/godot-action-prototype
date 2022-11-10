extends CharacterBody3D


var player_speed_current: float = 0.0
@export var player_speed_walk_max: float = 5.0
@export var player_speed_run_max: float = player_speed_walk_max * 1.5
@export var player_walk_accel_rate: float = 4
@export var player_run_accel_rate: float = 6
@export var player_decel_rate: float = 1.2
@export var player_rotation_rate: float = 9.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 2.5
@export var joystick_sensitivity: float = 0.05

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	
	# capture mouse movement for camera navigation
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED



func _physics_process(delta: float) -> void:
	
	### MOVEMENT ###
	
	# Apply gravity when in midair.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Get the input direction.
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	# set direction to always face forward, relative to where the camera's spring arm is positioned.
	var direction: Vector3 = ($SpringArm3D.transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		
		# player mesh rotation relative to camera. note: the entire player never rotates: only the spring arm or the mesh.
		if $PlayerMeshCapsule.rotation.y != $SpringArm3D.rotation.y:
			# rotate the player's mesh instead of the entire Player; rotating that will move the camera, too.
			$PlayerMeshCapsule.rotation.y = move_toward($PlayerMeshCapsule.rotation.y, $SpringArm3D.rotation.y, player_rotation_rate * delta)
		
		#acceleration
		if player_speed_current < player_speed_walk_max:
			player_speed_current += (player_walk_accel_rate * delta)
		elif player_speed_current > player_speed_walk_max:
			player_speed_current = player_speed_walk_max
		
		# apply movement
		velocity.x = direction.x * player_speed_current
		velocity.z = direction.z * player_speed_current
	else:
		
		# deceleration
		player_speed_current = 0
		
		velocity.x = move_toward(velocity.x, 0, player_speed_walk_max * player_decel_rate * delta)
		velocity.z = move_toward(velocity.z, 0, player_speed_walk_max * player_decel_rate * delta)
		
	# debug
	#print(player_speed_current)
	
	
	### CAMERA ###
		
	# controller spring arm rotation
	$SpringArm3D.rotate_y(Input.get_action_strength("player_turn_left_joystick") * joystick_sensitivity)
	$SpringArm3D.rotate_y(Input.get_action_strength("player_turn_right_joystick") * -joystick_sensitivity)

	# processes collisions: see https://godotengine.org/qa/44624/kinematicbody3d-move_and_slide-move_and_collide-different
	@warning_ignore(return_value_discarded) # makes debugger shut up
	move_and_slide()
	
func _input(event):
	
	### CAMERA ###
	
	# mouse spring arm rotation
	if (event is InputEventMouseMotion):
		# mouse x movement (in 2d monitor space) becomes spring arm rotation in 3D space around the Y axis - left/right rotation.
		$SpringArm3D.rotation.y -= event.relative.x / 1000 * mouse_sensitivity
		# mouse y movement (in 2d monitor space) becomes spring arm rotation in 3D space around the X axis - up/down rotation.
		$SpringArm3D.rotation.x -= event.relative.y / 1000 * mouse_sensitivity
		$SpringArm3D.rotation.x = clamp($SpringArm3D.rotation.x, -1.4, 0.3) # clamp the value to avoid full rotation.
		
		# debug
		print($SpringArm3D.rotation.x)




