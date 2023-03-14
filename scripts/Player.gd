extends CharacterBody3D

class_name Player

var player_speed_current: float = 0.0
@export var player_speed_walk_max: float = 6.0
@export var player_speed_sprint_max: float = player_speed_walk_max * 2.0
@export var player_jump_speed_modifier: float = 0.8
@export var player_double_jump_modifier: float = 1.4
@export var player_walk_accel_rate: float = 4.0
@export var player_sprint_accel_rate: float = 8.0
@export var player_decel_rate: float = 14.0
@export var player_jump_decel_rate: float = 10.0
@export var player_rotation_rate: float = 9.0
@export var target_cam_bias_default: float = 0.3
@export var target_cam_bias_additive: float = 0.4
var target_cam_bias: float = target_cam_bias_default
@export var cam_lerp_rate: float = 5.0
@export var jump_velocity: float = 7.0
@export var jump_velocity_multiplier: float = 1.25
@export var max_jumps: int = 2
@export var root_motion_multiplier: int = 50000

var has_direction: bool = false
var jumps_remaining: int = max_jumps
var is_jumping: bool = false
var attack_combo_stage: int = 0
var continue_attack_chain: bool = false
var targeting: bool = false

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

@export var gravity_multiplier: float = 1.0

@onready var player_cam: Camera3D = $SpringArm3D/PlayerCam
@onready var anim_tree: AnimationTree = $starblade_wielder/AnimationTree
@onready var anim_player: AnimationPlayer = $starblade_wielder/AnimationPlayer
@onready var weapon_slot_left: Node3D = $starblade_wielder/Armature/Skeleton3D/LeftHandAttachment/WeaponSlotLeftHand
@onready var vanish_timer: Timer = $starblade_wielder/Armature/Skeleton3D/LeftHandAttachment/VanishTimer
@onready var current_weapon: Node3D = $starblade_wielder/Armature/Skeleton3D/LeftHandAttachment/WeaponSlotLeftHand/Wielder1_Sword2
@onready var target_icon: TextureRect = $UI/TargetingIcon

@export var mouse_sensitivity: float = 2.5
@export var joystick_sensitivity: float = 3.0

var overlapping_object: Node3D = null
@export var vanish_timer_duration: float = 15.0

enum PlayerMovementState {
	IDLE = 0,
	WALK = 1,
	SPRINT = 2,
	ROLL = 3,
	ATTACK = 4
}

var movement_state: PlayerMovementState = PlayerMovementState.IDLE
var blending_movement_state: bool = false;


func _ready():
	# capture mouse movement for camera navigation
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	current_weapon.visible = false
	


# fluctuating framerate-based delta time
func _process(delta: float) -> void:
	#print(Engine.get_frames_per_second())
	#print(spring_arm_default_pos.position)
	pass


# difference from _process: https://godotengine.org/qa/57458/difference-between-_process-_physics_process-have-script
# tl;dr stable delta time
func _physics_process(delta: float) -> void:
	# movement + state blending, jumping & gravity, root motion, etc.
	determine_player_movement_state(delta)
	
	# calls either rotate_player_movement or rotate_player_combat
	determine_player_rotation(delta)
	
	# for default targeting or targeting enemies / objects
	determine_cam_lock_on(delta)
			
	# camera movement w/ controller (should see if we can only call this if using a controller input this frame?)
	rotate_cam_joypad(delta)
	
	# Set the player's animation tree blending value equal to the player's current speed.
	anim_tree.set("parameters/IdleWalkRun_Jump/IdleWalkRunBlendspace/blend_position", velocity.length())

	# Collisions
	# processes complex collisions: see https://godotengine.org/qa/44624/kinematicbody3d-move_and_slide-move_and_collide-different
	move_and_slide()
	
	# for visual debug
	$SpringArmVisualizer.position = $SpringArm3D.position
	
	# if attacking, reset velocity vector at the end of each physics tick to avoid accumulation of velocity.
	# this might need modification if root motion is used outside of combat later
	if movement_state == PlayerMovementState.ATTACK:
		velocity = Vector3(0, velocity.y, 0)
	
	#print(player_speed_current)
	#print(velocity.length())
	#print(movement_state)


func _input(event):
	# camera movement w/ mouse (should see if we can only call this if using a keyboard input this frame?)
	# https://godotforums.org/d/22759-detect-if-input-comes-from-controller-or-keyboard
	rotate_cam_kb_m(event)
	
	# handle what happens when the player attacks.
	# using 'event.' instead of 'Input.' for better input event buffering.
	handle_weapon_actions(event)

# determine if player rotates relative to the camera or relative to an enemy or object.
func determine_player_rotation(delta: float) -> void:
	if movement_state != PlayerMovementState.ATTACK:
		# normal directional lerp to match camera rotation
		if has_direction:
			rotate_player_movement(delta)
	else:
		# combat directional lerp to face enemy when attacking
		if overlapping_object != null && targeting:
			# only rotate to match enemy if not extremely close to them
			if $starblade_wielder.global_position.distance_to(overlapping_object.global_position) > 1.0:
				rotate_player_combat(delta)


func rotate_player_movement(delta: float) -> void:
	# player mesh rotation relative to camera. note: the entire Player never rotates: only the spring arm or the mesh.
	if $starblade_wielder.rotation.y != $SpringArm3D.rotation.y:
		# rotate the player's mesh instead of the entire Player; rotating that will move the camera, too.
		$starblade_wielder.rotation.y = lerp_angle($starblade_wielder.rotation.y, atan2(velocity.x, velocity.z), player_rotation_rate * delta)


func rotate_player_combat(delta: float) -> void:
	face_object_lerp($starblade_wielder, overlapping_object.position, Vector3.UP, delta)
	# zero out X and Z rotations so that the player can't rotate in odd ways and get stuck there.
	$starblade_wielder.rotation.x = 0.0;
	$starblade_wielder.rotation.z = 0.0;


func apply_jump_and_gravity(delta: float) -> void:
	# Apply gravity, reset jumps
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta
		
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
				velocity.y = jump_velocity * jump_velocity_multiplier * player_double_jump_modifier
#				
				# start double jump oneshot
				anim_tree.set("parameters/DoubleJumpShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		
		# start jump animation
		anim_tree.set("parameters/IdleWalkRun_Jump/conditions/jump_end", false)
		anim_tree.set("parameters/IdleWalkRun_Jump/conditions/jump_start", true)


func apply_only_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta


func determine_player_movement_state(delta: float) -> void:
	# if not attacking, move normally
	if movement_state != PlayerMovementState.ATTACK:
		# gravity, then jumping, in that order
		apply_jump_and_gravity(delta)
		# Lateral movement - gets direction vector from inputs, calls funcs to determine speed (or lack thereof) and applies movement.
		calculate_player_lateral_movement(delta)
		
	# if attacking, calculate movement w/ root motion
	else:
		player_speed_current = 0 # resets accel/decel to avoid immediate jumps after attack end
		handle_root_motion(delta)


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
	has_direction = true if direction != Vector3() else false # this is gdscript's ternary expr.
	
	if direction.length() > 1.0:
		direction = direction.normalized()
	
	# if we have input, do something.
	if direction:
		# check if the player is moving laterally. used for air-drag in midair, probably redundant when used in conjunction with cached ground direction.
		var inputting_movement: bool = Input.is_action_pressed("forward") || Input.is_action_pressed("backward") || Input.is_action_pressed("left") || Input.is_action_pressed("right")
		
		if inputting_movement:
			calculate_player_movement_state(delta)


		apply_player_lateral_movement(direction)
		
	
	# if there's no input, determine how/if we decelerate.
	else:
		#if (is_jumping == false):
		stop_player_movement(delta)


func calculate_player_movement_state(delta: float) -> void:
	# determine movement state (sprinting or walking)
	if Input.is_action_pressed("sprint"):
		movement_state = PlayerMovementState.SPRINT
	
	# deceleration from sprint -> walk
	elif Input.is_action_just_released("sprint"):
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


func apply_player_lateral_movement(dir: Vector3, modifier: float = 1.0) -> void:
	if !is_jumping:
		velocity.x = dir.x * player_speed_current * modifier
		velocity.z = dir.z * player_speed_current * modifier
	else:
		var player_speed_jump: float = player_speed_current * player_jump_speed_modifier
		velocity.x = dir.x * player_speed_jump * modifier
		velocity.z = dir.z * player_speed_jump * modifier


func stop_player_movement(delta: float) -> void:
		# update movement state
		movement_state = PlayerMovementState.IDLE
			
		blending_movement_state = false;
		
		# deceleration
		player_speed_current = 0
		
		if is_jumping:
			var velocity_vertical_cached = velocity.y
			#velocity.x = move_toward(velocity.x, 0, player_jump_decel_rate * delta)
			#velocity.z = move_toward(velocity.z, 0, player_jump_decel_rate * delta)
			velocity = velocity.move_toward(Vector3.ZERO, player_decel_rate * delta)
			velocity.y = velocity_vertical_cached
		else:
			velocity = velocity.move_toward(Vector3.ZERO, player_decel_rate * delta)


# determine how to move when applying root motion.
func handle_root_motion(delta: float) -> void:
	has_direction = false # ensure no added rotation movement lerping while attacking
	var up_vector: Vector3 = Vector3(0.0, 1.0, 0.0)
	# get the root motion position vector for the current frame, and rotate it to match the player's rotation.
	var root_motion: Vector3 = anim_tree.get_root_motion_position().rotated(up_vector, $starblade_wielder.rotation.y)
	
	# apply root motion, and multiply it by an arbitrary value to get a speed that makes sense.
	velocity += root_motion * root_motion_multiplier * delta
	
	# still add gravity if not on floor
	apply_only_gravity(delta)


func determine_cam_lock_on(delta: float) -> void:
	
	# if there is something to lock onto, smoothly lock on if the player targets.
	if overlapping_object != null:
		if Input.is_action_just_pressed("target"):
			targeting = !targeting
			target_icon.visible = !target_icon.visible
		
		if targeting:
			if overlapping_object is Enemy:
				var half_height: float = overlapping_object.collision_shape.shape.height * 0.5
				
				# calculate the camera's bias to position itself closer to either the player or target when targeting.
				if movement_state == PlayerMovementState.ATTACK:
					if target_cam_bias < target_cam_bias_default + target_cam_bias_additive:
						target_cam_bias += 0.0025
					else:
						target_cam_bias = target_cam_bias_default + target_cam_bias_additive
						
					# camera tracking w/ direct lock-on
					#var look_at_pos: Vector3 = Vector3(overlapping_object.global_transform.origin.x, overlapping_object.global_transform.origin.y + half_height, overlapping_object.global_transform.origin.z)
					#look_at_lerp($SpringArm3D, look_at_pos, Vector3.UP, delta)
				else:
					if target_cam_bias > target_cam_bias_default:
						target_cam_bias -= 0.0025
					else:
						target_cam_bias = target_cam_bias_default
						
				#print(target_cam_bias)
				
				# purposely placed after the above - determine exact tracking position of the camera when targeting.
				var tracking_pos: Vector3 = -($starblade_wielder.global_position - overlapping_object.global_position) * target_cam_bias
				
				# loose enemy tracking using the above calculations
				$SpringArm3D.position = lerp($SpringArm3D.position, tracking_pos, cam_lerp_rate * delta)
				
				# target icon placement
				var viewport_width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
				var viewport_height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
				var enemy_viewport_pos: Vector2 = player_cam.unproject_position(overlapping_object.global_transform.origin)
				var horizontal_offset: float = 4.5
				
				var target_viewport_x: float = enemy_viewport_pos.x - horizontal_offset * viewport_height * 0.005
				var target_viewport_y: float = enemy_viewport_pos.y - (half_height * viewport_height * 0.15)
				
				target_icon.position = Vector2(target_viewport_x, target_viewport_y)
				
	# if not targeting anything, follow the player. this is only a lerp to transition smoothly out of targeting state.
	if !targeting:
		# if the player is jumping, lerp to another target pole for smooth vertical camera movement.
		if not is_on_floor():
			$SpringArm3D.position = lerp($SpringArm3D.position, $SpringArmJumpTarget.position, cam_lerp_rate * delta)
		# otherwise, just track the player.
		else:
			$SpringArm3D.position = lerp($SpringArm3D.position, $SpringArmTarget.position, cam_lerp_rate * delta)


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
	if event.is_action_pressed("attack"):
		# grounded attacks
		if is_on_floor():
			# only begin first animation if not already in ATTACK state.
			if movement_state != PlayerMovementState.ATTACK:
				movement_state = PlayerMovementState.ATTACK
				anim_tree.set("parameters/AttackGroundShot1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
				current_weapon.visible = true
				attack_combo_stage += 1
			# if already attacking, determine if the attack combo is continued.
			else:
				match attack_combo_stage:
					1:
						var anim_duration: float = anim_tree.get("parameters/AttackGroundShot1/time")
						if anim_duration >= 0.2 && anim_duration <= 0.6:
							continue_attack_chain = true
							vanish_timer.start(vanish_timer_duration)
					2:
						var anim_duration: float = anim_tree.get("parameters/AttackGroundShot2/time")
						if anim_duration > 0.15 && anim_duration < 0.55:
							continue_attack_chain = true
							vanish_timer.start(vanish_timer_duration)
		# midair attacks
		else:
			if movement_state != PlayerMovementState.ATTACK:
#				movement_state = PlayerMovementState.ATTACK
#				anim_tree.set("parameters/AttackMidairShot1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
#				current_weapon.visible = true
#				attack_combo_stage += 1
				pass
			else:
				match attack_combo_stage:
					1:
						pass
					2:
						pass
	

# determine what happens when specific animations end.
func _on_animation_tree_animation_finished(anim_name):
	# attack animation combo chain continuation logic
	if movement_state == PlayerMovementState.ATTACK:
		
		# if combo is continuing, determine which animation to play.
		if continue_attack_chain == true:
			
			if anim_name == "AttackComboGround1":
				attack_combo_stage += 1
				anim_tree.set("parameters/AttackGroundShot2/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
				
			elif anim_name == "AttackComboGround2":
				attack_combo_stage += 1
				anim_tree.set("parameters/AttackGroundShot3/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			
		# if combo is ending, reset player state.
		else:
			movement_state = PlayerMovementState.IDLE
			attack_combo_stage = 0
			vanish_timer.start(vanish_timer_duration)
		
		# always set back to false so that future combo animations don't play automatically.
		continue_attack_chain = false


func _on_overlap_area_body_shape_entered(body_rid, body, body_shape_index, local_shape_index):
	#print(body)
	overlapping_object = body
	
	# auto-targeting when in range of first nearby enemy
	if !targeting:
		targeting = true
		$UI/TargetingIcon.visible = true


func _on_overlap_area_body_shape_exited(body_rid, body, body_shape_index, local_shape_index):
	overlapping_object = null
	
	# temporary
	targeting = false
	target_icon.visible = false


func _on_overlap_area_area_shape_entered(area_rid: RID, area: Area3D, area_shape_index: int, local_shape_index: int) -> void:
	#print(area.get_parent_node_3d())
	#overlapping_object = area.get_parent_node_3d()
	pass


func _on_overlap_area_area_shape_exited(area_rid: RID, area: Area3D, area_shape_index: int, local_shape_index: int) -> void:
	#overlapping_object = null
	pass


func _on_vanish_timer_timeout() -> void:
	print("vanish")
	current_weapon.visible = false


### HELPER FUNCTIONS
# generic, reimplemented from engine source
func looking_at_gd(target: Vector3, up: Vector3) -> Basis:
	var v_z: Vector3 = -target.normalized()
	var v_x: Vector3 = up.cross(v_z)
	
	v_x.normalized()
	var v_y: Vector3 = v_z.cross(v_x)
	
	var v_basis: Basis = Basis(v_x, v_y, v_z)
	return v_basis
	
# for meshes, such as player (minor modification of looking_at)
func facing_object(target: Vector3, up: Vector3)-> Basis:
	var v_z: Vector3 = target.normalized()
	var v_x: Vector3 = up.cross(v_z)
	
	v_x.normalized()
	var v_y: Vector3 = v_z.cross(v_x)
	
	var v_basis: Basis = Basis(v_x, v_y, v_z)
	return v_basis
	
# generic, reimplemented from engine source
func look_at_from_pos_gd(obj: Node3D, pos: Vector3, target: Vector3, up: Vector3) -> void:
	var lookat: Transform3D = Transform3D(looking_at_gd(target - pos, up), pos)
	var original_scale: Vector3 = obj.scale
	obj.global_transform = lookat
	obj.scale = original_scale
	
# generic, reimplemented from engine source
func look_at_gd(obj: Node3D, target: Vector3, up: Vector3) -> void:
	var origin: Vector3 = obj.global_transform.origin
	look_at_from_pos_gd(obj, origin, target, up)
	
# for camera (adds lerp to default look_at_from_position)
func look_at_from_pos_lerp(obj: Node3D, pos: Vector3, target: Vector3, up: Vector3, delta: float) -> void:
	var lookat: Transform3D = Transform3D(looking_at_gd(target - pos, up), pos)
	var original_scale: Vector3 = obj.scale
	#obj.global_transform = lerp(obj.global_transform, lookat, player_rotation_rate * delta)
	obj.global_transform = obj.global_transform.interpolate_with(lookat, cam_lerp_rate * delta)
	#obj.global_transform = lookat
	obj.scale = original_scale
	
# for meshes, such as player (minor modification of looking_at_from_position)
func facing_object_from_pos_lerp(obj: Node3D, pos: Vector3, target: Vector3, up: Vector3, delta: float) -> void:
	var lookat: Transform3D = Transform3D(facing_object(target - pos, up), pos)
	var original_scale: Vector3 = obj.scale
	#obj.global_transform = lerp(obj.global_transform, lookat, player_rotation_rate * delta)
	obj.global_transform = obj.global_transform.interpolate_with(lookat, player_rotation_rate * delta)
	#obj.global_transform = lookat
	obj.scale = original_scale

# for camera (adds lerp to default look_at)
func look_at_lerp(obj: Node3D, target: Vector3, up: Vector3, delta: float) -> void:
	var origin: Vector3 = obj.global_transform.origin
	look_at_from_pos_lerp(obj, origin, target, up, delta)
	
# for meshes, such as player (minor modification of look_at)
func face_object_lerp(obj: Node3D, target: Vector3, up: Vector3, delta: float) -> void:
	var origin: Vector3 = obj.global_transform.origin
	facing_object_from_pos_lerp(obj, origin, target, up, delta)

