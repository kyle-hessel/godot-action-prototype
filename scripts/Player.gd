extends CharacterBody3D


var player_speed_current: float = 0.0
@export var player_speed_walk_max: float = 6.0
@export var player_speed_sprint_max: float = player_speed_walk_max * 2.0
@export var player_jump_speed_modifier: float = 0.8
@export var player_walk_accel_rate: float = 4.0
@export var player_sprint_accel_rate: float = 7.0
@export var player_decel_rate: float = 14.0
@export var player_jump_decel_rate: float = 10.0
@export var player_rotation_rate: float = 9.0
@export var jump_velocity: float = 7.0
@export var jump_velocity_multiplier: float = 1.25
@export var max_jumps: int = 2
var jumps_remaining: int = max_jumps
var is_jumping: bool = false

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var gravity_multiplier: float = 1.0

@onready var anim_tree: AnimationTree = $starblade_wielder/AnimationTree
@onready var weapon_slot_right: Node3D = $starblade_wielder/Armature/Skeleton3D/RightHandAttachment/WeaponSlotRightHand
@onready var vanish_timer: Timer = $starblade_wielder/Armature/Skeleton3D/RightHandAttachment/VanishTimer
@onready var current_weapon: Node3D = $starblade_wielder/Armature/Skeleton3D/RightHandAttachment/WeaponSlotRightHand/Wielder1_Sword2

@export var mouse_sensitivity: float = 2.5
@export var joystick_sensitivity: float = 4.0

var overlapping_object: Node3D = null
var weapon_drawn: bool = false
@export var vanish_timer_duration: float = 10.0

enum PlayerMovementState {
	IDLE = 0,
	WALK = 1,
	SPRINT = 2,
	ATTACK = 3
}

var movement_state: PlayerMovementState = PlayerMovementState.IDLE
var blending_movement_state: bool = false;


func _ready():
	Engine.max_fps = 144
	
	# capture mouse movement for camera navigation
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# hack fix that prevents the player from facing in the wrong direction if camera isn't moved before very first input. 
	# might be a godot bug? check later in stable version. it's a harmless fix regardless, albeit odd that it works.
	#$SpringArm3D.rotation.y += 0.001

# fluctuating framerate-based delta time
func _process(delta: float) -> void:
	# Camera w/ controller (should see if we can only call this if using a controller input this frame)
	rotate_cam_joypad(delta)

# difference from _process: https://godotengine.org/qa/57458/difference-between-_process-_physics_process-have-script
# tl;dr stable delta time
func _physics_process(delta: float) -> void:
	
	# gravity, then jumping, in that order
	apply_jump_and_gravity(delta)

	# Lateral movement - gets direction vector from inputs, calls funcs to determine speed (or lack thereof) and applies movement.
	calculate_player_lateral_movement(delta)
	
	#print(player_speed_current)
	#print(velocity.length())
	
	# Set the player's animation tree blending value equal to the player's current speed.
	anim_tree.set("parameters/IdleWalkRun_Jump/IdleWalkRunBlendspace/blend_position", velocity.length())

	# Collisions
	# processes complex collisions: see https://godotengine.org/qa/44624/kinematicbody3d-move_and_slide-move_and_collide-different
	move_and_slide()
	
	#print(movement_state)
	
	
func _input(event):
	# Camera w/ mouse (should see if we can only call this if using a keyboard input this frame)
	# https://godotforums.org/d/22759-detect-if-input-comes-from-controller-or-keyboard
	rotate_cam_kb_m(event)
	
	# using 'event.' instead of 'Input.' for better input event buffering.
	handle_weapon_actions(event)
	
	
func apply_jump_and_gravity(delta: float) -> void:
	
	# Apply gravity, reset jumps
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
		
		# check for directional switches in midair
		var inputting_movement: bool = Input.is_action_just_released("forward") || Input.is_action_just_released("backward") || Input.is_action_just_released("left") || Input.is_action_just_released("right")
		
		# start fall animation (same as jump)
		if !is_jumping:
			anim_tree.set("parameters/IdleWalkRun_Jump/conditions/jump_end", false)
			anim_tree.set("parameters/IdleWalkRun_Jump/conditions/fall_start", true)
		
	# hitting the ground
	else:
		if is_jumping:
			is_jumping = false
			jumps_remaining = max_jumps

			# start jump end animation out of jump
			anim_tree.set("parameters/IdleWalkRun_Jump/conditions/jump_start", false)
			anim_tree.set("parameters/IdleWalkRun_Jump/conditions/jump_end", true)
		else:
			# start 'jump' end animation (fall end, in this case) out of fall.
			anim_tree.set("parameters/IdleWalkRun_Jump/conditions/fall_start", false)
			anim_tree.set("parameters/IdleWalkRun_Jump/conditions/jump_end", true)

	# Jumping
	if Input.is_action_just_pressed("jump") && jumps_remaining > 0:
		if is_on_floor():
			jumps_remaining -= 1
			is_jumping = true
			velocity.y = jump_velocity * jump_velocity_multiplier
			
			# early out of double jump animation if hitting the ground early.
			if (anim_tree.get("parameters/DoubleJumpShot/active") == true):
				anim_tree.set("parameters/DoubleJumpShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	
		# stop player from beginning jumping sequence while falling
		else:
			if jumps_remaining < max_jumps:
				jumps_remaining -= 1
				velocity.y = jump_velocity * jump_velocity_multiplier
#				
				# start double jump oneshot
				anim_tree.set("parameters/DoubleJumpShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		
		# start jump animation
		anim_tree.set("parameters/IdleWalkRun_Jump/conditions/jump_end", false)
		anim_tree.set("parameters/IdleWalkRun_Jump/conditions/jump_start", true)
	
func calculate_player_lateral_movement(delta: float) -> void:
	
	# Get the input direction.
	var input_dir := Input.get_vector("left", "right", "forward", "backward")
	
	# set direction to always face forward, relative to where the camera's spring arm is positioned.
	# also, remove any vertical camera data from both x and z axis Vec3's to ensure that camera height doesn't effect speed.
	var direction_x: Vector3 = $SpringArm3D.transform.basis.x
	direction_x.y = 0
	direction_x = direction_x.normalized() * input_dir.x # x-axis input == 3D x axis (left/right)
	
	var direction_z: Vector3 = $SpringArm3D.transform.basis.z
	direction_z.y = 0
	direction_z = direction_z.normalized() * input_dir.y # y-axis input == 3D z axis (forward/back)
	
	# recombine separated direction vectors back into one.
	var direction: Vector3 = direction_x + direction_z
	
	if direction.length() > 1.0:
		direction = direction.normalized()
	
	# if we have input, do something.
	if direction:
		# check if the player is moving laterally. used for air-drag in midair, probably redundant when used in conjunction with cached ground direction.
		var inputting_movement: bool = Input.is_action_pressed("forward") || Input.is_action_pressed("backward") || Input.is_action_pressed("left") || Input.is_action_pressed("right")
		
		if inputting_movement:
			calculate_player_movement_state(delta)

		apply_player_lateral_movement(direction)
		
		# player mesh rotation relative to camera. note: the entire Player never rotates: only the spring arm or the mesh.
		if $starblade_wielder.rotation.y != $SpringArm3D.rotation.y:
			# rotate the player's mesh instead of the entire Player; rotating that will move the camera, too.
			$starblade_wielder.rotation.y = lerp_angle($starblade_wielder.rotation.y, atan2(velocity.x, velocity.z), player_rotation_rate * delta)
		
	# if there's no input, determine how/if we decelerate.
	else:
		#if (is_jumping == false):
		stop_player_movement(delta)


func apply_player_lateral_movement(dir: Vector3, modifier: float = 1.0) -> void:
	if !is_jumping:
		velocity.x = dir.x * player_speed_current * modifier
		velocity.z = dir.z * player_speed_current * modifier
	else:
		var player_speed_jump: float = player_speed_current * player_jump_speed_modifier
		velocity.x = dir.x * player_speed_jump * modifier
		velocity.z = dir.z * player_speed_jump * modifier


func calculate_player_movement_state(delta: float) -> void:
	# determine movement state (sprinting or walking)
	if (Input.is_action_pressed("sprint")):
		movement_state = PlayerMovementState.SPRINT
	
	# deceleration from sprint -> walk
	elif (Input.is_action_just_released("sprint")):
		blending_movement_state = true;
	else:
		if blending_movement_state:
			if player_speed_current > player_speed_walk_max:
				player_speed_current -= (player_decel_rate * delta)
			elif player_speed_current < player_speed_walk_max:
				player_speed_current = player_speed_walk_max
				blending_movement_state = false;
			else:
				blending_movement_state = false;
				
		# always set movement state to walk if moving and not sprinting, or once deceleration from sprint -> walk is complete
		else:
			movement_state = PlayerMovementState.WALK
			
		#print(blending_movement_state)
	
	
	# calculate acceleration
	smooth_accelerate(delta)


# acceleration, based on movement state
func smooth_accelerate(delta: float) -> void:
	# only calculate if on ground
#	if is_jumping == false:
	if (movement_state == PlayerMovementState.WALK):
		if player_speed_current < player_speed_walk_max:
			player_speed_current += (player_walk_accel_rate * delta)
		elif player_speed_current > player_speed_walk_max:
			player_speed_current = player_speed_walk_max
					
	elif (movement_state == PlayerMovementState.SPRINT):
		if player_speed_current < player_speed_sprint_max:
			player_speed_current += (player_sprint_accel_rate * delta)
		elif player_speed_current > player_speed_sprint_max:
			player_speed_current = player_speed_sprint_max


func stop_player_movement(delta: float) -> void:
		# update movement state
		movement_state = PlayerMovementState.IDLE
		blending_movement_state = false;
		
		# deceleration
		player_speed_current = 0
		
		if is_jumping:
			velocity.x = move_toward(velocity.x, 0, player_jump_decel_rate * delta)
			velocity.z = move_toward(velocity.z, 0, player_jump_decel_rate * delta)
		else:
			velocity = velocity.move_toward(Vector3.ZERO, player_decel_rate * delta)

	
func rotate_cam_kb_m(event) -> void:
	# mouse spring arm rotation
	if (event is InputEventMouseMotion):
		# mouse x movement (in 2d monitor space) becomes spring arm rotation in 3D space around the Y axis - left/right rotation.
		$SpringArm3D.rotation.y -= event.relative.x / 1000 * mouse_sensitivity
		# mouse y movement (in 2d monitor space) becomes spring arm rotation in 3D space around the X axis - up/down rotation.
		$SpringArm3D.rotation.x -= event.relative.y / 1000 * mouse_sensitivity
		$SpringArm3D.rotation.x = clamp($SpringArm3D.rotation.x, -1.4, 0.3) # clamp the value to avoid full rotation.
		
		# debug
		#print($SpringArm3D.rotation.x)
		

func rotate_cam_joypad(delta: float) -> void:
	# controller spring arm rotation
	$SpringArm3D.rotation.y -= Input.get_action_strength("camera_left_joystick") * -joystick_sensitivity * delta
	$SpringArm3D.rotation.y -= Input.get_action_strength("camera_right_joystick") * joystick_sensitivity * delta
	
	$SpringArm3D.rotation.x -= Input.get_action_strength("camera_up_joystick") * -joystick_sensitivity * delta
	$SpringArm3D.rotation.x -= Input.get_action_strength("camera_down_joystick") * joystick_sensitivity * delta
	$SpringArm3D.rotation.x = clamp($SpringArm3D.rotation.x, -1.4, 0.3)
	

func handle_weapon_actions(event) -> void:
	if (event.is_action_pressed("attack") && weapon_drawn == false):
		weapon_drawn = !weapon_drawn
		current_weapon.visible = weapon_drawn
		vanish_timer.start(vanish_timer_duration)
	elif (event.is_action_pressed("attack") && weapon_drawn == true):
		vanish_timer.start(vanish_timer_duration)
	
		
#func handle_weapon_updates() -> void:
#	if current_weapon != null:
#		current_weapon.global_transform = weapon_slot_right.global_transform


func _on_overlap_area_area_shape_entered(area_rid: RID, area: Area3D, area_shape_index: int, local_shape_index: int) -> void:
	print(area.get_parent_node_3d())
	
	overlapping_object = area.get_parent_node_3d()
		
	
func _on_overlap_area_area_shape_exited(area_rid: RID, area: Area3D, area_shape_index: int, local_shape_index: int) -> void:
	overlapping_object = null


func _on_vanish_timer_timeout() -> void:
	print("vanish")
	weapon_drawn = !weapon_drawn
	current_weapon.visible = weapon_drawn
