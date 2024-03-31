extends CharacterBody3D

class_name Player

@export var player_health_max: float = 20.0
@export var player_health_current: float = player_health_max
@export var player_base_damage_stat: float = 3.0
@export var player_damage_stat: float = player_base_damage_stat
@export var ground_combo_damage_multiplier: float = 1.5

var player_speed_current: float = 0.0
@export var player_speed_walk_max: float = 5.0
@export var player_speed_sprint_max: float = player_speed_walk_max * 2.0
@export var player_jump_speed_modifier: float = 0.8
@export var player_double_jump_modifier: float = 1.4
@export var player_walk_accel_rate: float = 4.0
@export var player_sprint_accel_rate: float = 9.0
@export var player_decel_rate: float = 14.0
@export var player_jump_decel_rate: float = 10.0
@export var player_rotation_rate: float = 9.0
@export var target_cam_bias_default: float = 0.3
@export var target_cam_bias_additive: float = 0.2
var target_cam_bias: float = target_cam_bias_default
@export var cam_lerp_rate: float = 5.0
@export var tracking_range: float = 6.0
@export var jump_velocity: float = 7.0
@export var jump_velocity_multiplier: float = 1.25
@export var max_jumps: int = 2
var current_root_motion: Vector3
@export var root_motion_multiplier: float = 4.0

var has_direction: bool = false
var jumps_remaining: int = max_jumps
var is_jumping: bool = false
var attack_combo_stage: int = 0
var continue_attack_chain: bool = false
var air_combo_complete: bool = false
var attack_type: AttackType = AttackType.NONE
var current_oneshot_anim: String
@export var attack_anim_damage_cutoff: float = 0.25
@export var death_front_cutoff: float = 0.75
var hit_received: bool = false
var targeting: bool = false
var tracking: bool = false

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var gravity_multiplier: float = 1.0

@onready var player_mesh: Node3D = $starblade_wielder
@onready var player_cam: Camera3D = $SpringArm3D/PlayerCam
@onready var combat_sweep_area: Area3D = $starblade_wielder/CombatSweepArea
@onready var combat_sweep_shape: CollisionShape3D = $starblade_wielder/CombatSweepArea/CombatSweepShape
@onready var anim_tree: AnimationTree = $starblade_wielder/AnimationTree
@onready var anim_player: AnimationPlayer = $starblade_wielder/AnimationPlayer
@onready var weapon_slot_left: Node3D = $starblade_wielder/Armature/Skeleton3D/LeftHandAttachment/WeaponSlotLeftHand
@onready var vanish_timer: Timer = $starblade_wielder/Armature/Skeleton3D/LeftHandAttachment/VanishTimer
@onready var i_frames: Timer = $InvincibilityTimer
@onready var current_weapon: Node3D = $starblade_wielder/Armature/Skeleton3D/LeftHandAttachment/WeaponSlotLeftHand/WielderSword
@onready var weapon_hitbox: Area3D = $starblade_wielder/Armature/Skeleton3D/LeftHandAttachment/WeaponSlotLeftHand/WielderSword/HitboxArea
@onready var sword_trail: Trail3D = $starblade_wielder/Armature/Skeleton3D/LeftHandAttachment/WeaponSlotLeftHand/WielderSword/SwordTrail3D
@onready var target_icon: Sprite2D = $UI/TargetingIcon

var viewport_width: int = ProjectSettings.get_setting("display/window/size/viewport_width")
var viewport_height: int = ProjectSettings.get_setting("display/window/size/viewport_height")
var viewport_wh: Vector2 = Vector2(viewport_width, viewport_height)

@export var mouse_sensitivity: float = 2.5
@export var joystick_sensitivity: float = 3.0

var overlapping_objects: Array[Node3D]
var targeted_object: Node3D = null
var sweeping_objects: Array[Enemy]
@export var vanish_timer_duration: float = 15.0

# weapon actions dictionary w/ defaults
var weapon_actions: Dictionary = {
	"action1": WeaponAction.ATTACK,
	"action2": WeaponAction.PARRY,
	"action3": WeaponAction.SWING,
	"action4": WeaponAction.ULTIMATE,
}

var current_weapon_action: WeaponAction = WeaponAction.NONE

enum PlayerMovementState {
	IDLE = 0,
	WALK = 1,
	SPRINT = 2,
	ROLL = 3,
	ATTACK = 4,
	PARRY = 5,
	DAMAGED = 6,
	STUN = 7,
	DEAD = 8
}

enum AttackType {
	GROUND = 0,
	AIR = 1,
	PARRY = 2,
	NONE = 3
}

enum WeaponAction {
	ATTACK = 0,
	PARRY = 1,
	SWING = 2,
	ULTIMATE = 3,
	NONE = 4
}

enum HitDirection {
	FRONT = 0,
	BACK = 1,
	RIGHT = 2,
	LEFT = 3,
	MAX = 4
}

enum DamageResult {
	ALIVE = 0,
	DEAD = 1,
	PARRY = 2,
	NONE = 3
}

var movement_state: PlayerMovementState = PlayerMovementState.IDLE
var blending_movement_state: bool = false
var blending_weapon_state: bool = false
var weapon_blend: float = 0.0


func _ready():
	# capture mouse movement for camera navigation
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	current_weapon.visible = false
	weapon_hitbox.monitoring = false
	sword_trail.trail_enabled = false
	
	# viewport-relative scaling for UI elements
	target_icon.scale = Vector2(viewport_width * 0.00005, viewport_width * 0.00005)


# difference from _process: https://godotengine.org/qa/57458/difference-between-_process-_physics_process-have-script
# tl;dr stable delta time
func _physics_process(delta: float) -> void:
	# movement + state blending, jumping & gravity, root motion, etc.
	determine_player_movement_state(delta)
	
	# calls either rotate_player_movement or rotate_player_combat
	determine_player_rotation(delta)
	
	# figure out current target if there is one, so that we know what to lock onto.
	determine_target()
	
	sweep_objects()
	
	# for default targeting or manually targeting enemies / objects. relies on determine_target in _input.
	determine_cam_lock_on(delta)
			
	# camera movement w/ controller (should see if we can only call this if using a controller input this frame?)
	rotate_cam_joypad(delta)
	
	# determine any animation blends, such as from free movement states to weapon movement states.
	set_anim_blend(delta)

	# Collisions
	# processes complex collisions: see https://godotengine.org/qa/44624/kinematicbody3d-move_and_slide-move_and_collide-different
	move_and_slide()
	
	#print(current_weapon_action)
	#print(continue_attack_chain)
	#print(air_combo_complete)
	#print(player_speed_current)
	#print(velocity.length())
	#print(movement_state)
	
	# for visual debug
	$SpringArmVisualizer.position = $SpringArm3D.position
	
	# if attacking or damaged, reset velocity vector at the end of each physics tick to avoid accumulation of velocity.
	if movement_state == PlayerMovementState.ATTACK || movement_state == PlayerMovementState.DAMAGED:
		if attack_type == AttackType.GROUND:
			velocity = Vector3(0, velocity.y, 0)
		elif attack_type == AttackType.AIR:
			velocity = Vector3.ZERO
		elif attack_type == AttackType.PARRY:
			velocity = Vector3.ZERO
		elif attack_type == AttackType.NONE:
			velocity = Vector3.ZERO


func _input(event: InputEvent):
	# camera movement w/ mouse (should see if we can only call this if using a keyboard input this frame?)
	# https://godotforums.org/d/22759-detect-if-input-comes-from-controller-or-keyboard
	rotate_cam_kb_m(event)
	
	# handle what happens when the player presses different weapon actions in combat.
	# using 'event.' instead of 'Input.' for better input event buffering.
	interpret_weapon_action_handles(event)


# determine if player rotates relative to the camera or relative to an enemy or object.
func determine_player_rotation(delta: float) -> void:
	if movement_state != PlayerMovementState.ATTACK && movement_state != PlayerMovementState.DAMAGED:
		# normal directional lerp to match camera rotation
		if has_direction:
			rotate_player_movement(delta)
	else:
		if movement_state == PlayerMovementState.ATTACK:
			# combat directional lerp to face enemy when attacking
			if targeted_object != null && targeting:
				# only rotate to match enemy if not extremely close to them
				rotate_player_combat(delta)
		elif movement_state == PlayerMovementState.DAMAGED:
			pass


func rotate_player_movement(delta: float) -> void:
	# player mesh rotation relative to camera. note: the entire Player never rotates: only the spring arm or the mesh.
	if $starblade_wielder.rotation.y != $SpringArm3D.rotation.y:
		# rotate the player's mesh instead of the entire Player; rotating that will move the camera, too.
		$starblade_wielder.rotation.y = lerp_angle($starblade_wielder.rotation.y, atan2(velocity.x, velocity.z), player_rotation_rate * delta)


func rotate_player_combat(delta: float) -> void:
	# only target if both target and player are in the air or on the ground together.
	if is_on_floor() && targeted_object.is_on_floor() || !is_on_floor() && !targeted_object.is_on_floor():
		face_object_lerp($starblade_wielder, targeted_object.global_position, Vector3.UP, delta)
		# zero out X and Z rotations so that the player can't rotate in odd ways and get stuck there.
		$starblade_wielder.rotation.x = 0.0;
		$starblade_wielder.rotation.z = 0.0;
		# maybe not necessary, but recommended - see https://docs.godotengine.org/en/stable/tutorials/3d/using_transforms.html
		$starblade_wielder.global_transform = $starblade_wielder.global_transform.orthonormalized()


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
		air_combo_complete = false
		
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
	# only try to do anything if alive.
	if movement_state != PlayerMovementState.DEAD:
		# if not attacking or taking damage, move normally
		if movement_state != PlayerMovementState.ATTACK && movement_state != PlayerMovementState.DAMAGED:
			# gravity, then jumping, in that order
			apply_jump_and_gravity(delta)
			# Lateral movement - gets direction vector from inputs, calls funcs to determine speed (or lack thereof) and applies movement.
			calculate_player_lateral_movement(delta)
			
		else:
			# if attacking, calculate movement w/ root motion
			if movement_state == PlayerMovementState.ATTACK:
				if attack_type == AttackType.GROUND:
					handle_root_motion(delta)
				elif attack_type == AttackType.AIR:
					handle_root_motion(delta, root_motion_multiplier * 0.5)
				elif attack_type == AttackType.PARRY:
					handle_root_motion(delta)
				
			# if taking damage, reset attack combo, calculate movement w/ root motion
			elif movement_state == PlayerMovementState.DAMAGED:
				handle_root_motion(delta, root_motion_multiplier * 0.5)
	
	# if dead, handle that.
	else:
		handle_death(delta)


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


		apply_player_lateral_movement(delta, direction)
		
	
	# if there's no input, determine how/if we decelerate.
	else:
		#if (is_jumping == false): # this has significant effect on lateral deceleration while in midair.
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


func apply_player_lateral_movement(delta: float, dir: Vector3) -> void:
	if !is_jumping:
		velocity.x = dir.x * player_speed_current
		velocity.z = dir.z * player_speed_current
	else:
		var player_speed_jump: float = player_speed_current * player_jump_speed_modifier
		velocity.x = dir.x * player_speed_jump
		velocity.z = dir.z * player_speed_jump


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
func handle_root_motion(delta: float, rm_multiplier: float = root_motion_multiplier, lateral_only: bool = false) -> void:
	has_direction = false # ensure no added rotation movement lerping while attacking
	# get the root motion position vector for the current frame, and rotate it to match the player's rotation.
	current_root_motion = anim_tree.get_root_motion_position().rotated(Vector3.UP, $starblade_wielder.rotation.y) / delta
	
	if lateral_only:
		velocity.x += current_root_motion.x * rm_multiplier
		velocity.z += current_root_motion.z * rm_multiplier
	else:
		# apply root motion, and multiply it by an arbitrary value to get a speed that makes sense.
		velocity += current_root_motion * rm_multiplier
	
	# still add gravity if not on floor
	apply_only_gravity(delta)


# advanced target lock handling
func determine_target() -> void:
	if !overlapping_objects.is_empty():
		# toggling targeting on and off
		if Input.is_action_just_pressed("target"):
				# if we have overlapping objects, toggle targeting
				targeting = !targeting
				if targeted_object && object_visibility_check(targeted_object):
					target_icon.visible = !target_icon.visible
				
				# if targeting, find nearest object to target.
				if targeting:
					sort_objects_by_distance()
					
					# extra checks to ensure object is fit for targeting (visibility, mostly)
					targeted_object = objects_visibility_check(overlapping_objects) # returns first closest visible object
					
					# if no object met requirements, set targeting back to false.
					if targeted_object == null:
						targeting = false
						target_icon.visible = false
					else:
						stop_sweep_objects()
				
				# if false, clear.
				else:
					targeted_object = null
					tracking = false
		
		# target toggling/switching, only if already actively in target mode.
		# *** the below implementation for the remainder of this function does have a few edge case bugs remaining, seemingly.
		if targeting && overlapping_objects.size() > 1:	
			
			# move target backwards
			if Input.is_action_just_pressed("toggle_target_left"):
				# sort again so that distance information is always up to date, then fetch our current target's new array position.
				sort_objects_by_distance()
				var obj_index: int = overlapping_objects.find(targeted_object)
				
				var failed: bool = false
				
				# check if next potential candidate is non-existent (out of bounds). If not, do the below check.
				if !(obj_index + 1 > overlapping_objects.size() - 1):
					# determine the next object to target that is further than the one we started with.
					for obj in overlapping_objects:
						# skip array indexes lower (closer) than our initial object, inclusive.
						var current_index: int = overlapping_objects.find(obj)
						if current_index <= obj_index:
							continue
						# extra checks to ensure object is fit for targeting (this is why the for loop is necessary).
						else:
							#print(obj)
							if object_visibility_check(obj) == true:
								# if everything succeeded, retarget to the given object and break out.
								targeted_object = obj
								if targeted_object != null:
									stop_sweep_objects()
								break
							else:
								# if nothing succeeded, just fetch the nearest visible object. if this fails there may not be one.
								targeted_object = objects_visibility_check(overlapping_objects)
								if targeted_object != null:
									stop_sweep_objects()
								break
						
				# if the next candidate was out of bounds, wrap back to the front of the array.
				else:
					# do similar checks to above to find the lowest indexed object that meets requirements.
					for obj in overlapping_objects:
						# simply start at the beginning of the array, since we wrapped around.
						if object_visibility_check(obj) == true:
							# if everything succeeded, retarget to the given object and break out.
							targeted_object = obj
							if targeted_object != null:
								stop_sweep_objects()
							break
						else:
							# if nothing succeeded, just fetch the nearest visible object. if this fails there may not be one.
							targeted_object = objects_visibility_check(overlapping_objects)
							if targeted_object != null:
								stop_sweep_objects()
							break
				
				
			# move target forwards
			if Input.is_action_just_pressed("toggle_target_right"):
				# sort again so that distance information is always up to date.
				sort_objects_by_distance()
				
				# duplicate our original array and reverse it to maintain easy looping, now sorting from furthest to closest.
				var overlapping_objects_reversed: Array[Node3D] = overlapping_objects.duplicate()
				overlapping_objects_reversed.reverse()
				#print(overlapping_objects_reversed)
				
				# fetch our current target's new array position.
				var obj_index: int = overlapping_objects_reversed.find(targeted_object)
				
				# check if next potential candidate is non-existent. If not, do the below check.
				if !(obj_index + 1 > overlapping_objects_reversed.size() - 1):
					# determine the next object to target that is further than the one we started with.
					for obj in overlapping_objects_reversed:
						# skip array indexes lower (farther) than our initial object, inclusive.
						var current_index: int = overlapping_objects_reversed.find(obj)
						if current_index <= obj_index:
							continue
						# extra checks to ensure object is fit for targeting.
						else:
							#print(obj)
							if object_visibility_check(obj) == true:
								# if everything succeeded, retarget to the given object and break out.
								targeted_object = obj
								if targeted_object != null:
									stop_sweep_objects()
								break
							else:
								# if nothing succeeded, just fetch the nearest visible object. if this fails there may not be one.
								targeted_object = objects_visibility_check(overlapping_objects_reversed)
								if targeted_object != null:
									stop_sweep_objects()
								break
				
				# if the next candidate was out of bounds, wrap back to the front of the array.
				else:
					# do similar checks to above to find the lowest indexed object that meets requirements.
					for obj in overlapping_objects_reversed:
						# simply start at the beginning of the array, since we wrapped around.
						if object_visibility_check(obj) == true:
							# if everything succeeded, retarget to the given object and break out.
							targeted_object = obj
							if targeted_object != null:
								stop_sweep_objects()
							break
						else:
							# if nothing succeeded, just fetch the nearest visible object. if this fails there may not be one.
							targeted_object = objects_visibility_check(overlapping_objects_reversed)
							if targeted_object != null:
								stop_sweep_objects()
							break


# returns the first valid candidate for targeting if visiblity checks pass, if there is one.
func objects_visibility_check(obj_array: Array[Node3D]) -> Node3D:
	for object in obj_array:
		var half_height: float = object.collision_shape.shape.height * 0.5
		var target_pos: Vector3 = Vector3(object.position.x, object.position.y + half_height, object.position.z)
		
		# if object is fit for targeting, return said object
		if player_cam.is_position_in_frustum(target_pos):
			return object
			
	# if whole loop completes without a candidate, return null
	return null


# returns whether a given object is in view instead of iterating over all overlapping objects.
func object_visibility_check(object: Node3D) -> bool:
	var half_height: float = object.collision_shape.shape.height * 0.5
	var target_pos: Vector3 = Vector3(object.position.x, object.position.y + half_height, object.position.z)
	
	return player_cam.is_position_in_frustum(target_pos)


func determine_cam_lock_on(delta: float) -> void:
	# if there is something to lock onto, smoothly lock on if the player targets.
	if targeted_object != null:
		if targeting:
			var half_height: float = targeted_object.collision_shape.shape.height * 0.5
			
			# if close enough, make the camera loosely track the enemy if already targeting.
			if targeted_object is Enemy && $starblade_wielder.global_position.distance_to(targeted_object.global_position) < tracking_range:
				
				# calculate the camera's bias to position itself closer to either the player or target when targeting.
				if movement_state == PlayerMovementState.ATTACK:
					if target_cam_bias < target_cam_bias_default + target_cam_bias_additive:
						target_cam_bias += 0.0025
					else:
						target_cam_bias = target_cam_bias_default + target_cam_bias_additive
						
					# camera tracking w/ direct lock-on
					#var look_at_pos: Vector3 = Vector3(targeted_object.global_transform.origin.x, targeted_object.global_transform.origin.y + half_height, targeted_object.global_transform.origin.z)
					#look_at_lerp($SpringArm3D, look_at_pos, Vector3.UP, delta)
				else:
					if target_cam_bias > target_cam_bias_default:
						target_cam_bias -= 0.0025
					else:
						target_cam_bias = target_cam_bias_default
						
				#print(target_cam_bias)
				
				# purposely placed after the above - determine exact tracking position of the camera when targeting.
				var tracking_pos: Vector3 = -($starblade_wielder.global_position - targeted_object.global_position) * target_cam_bias
				
				# loose enemy tracking using the above calculations
				$SpringArm3D.position = lerp($SpringArm3D.position, tracking_pos, cam_lerp_rate * 0.8 * delta)
				
				tracking = true
			else:
				tracking = false
				
			# target icon placement
			var icon_target_pos: Vector3 = Vector3(targeted_object.position.x, targeted_object.position.y + (half_height * 1.25), targeted_object.position.z)
			var enemy_viewport_pos: Vector2 = player_cam.unproject_position(icon_target_pos)
					
			if player_cam.is_position_in_frustum(icon_target_pos):
				target_icon.visible = true
				target_icon.position = enemy_viewport_pos
			else:
				target_icon.visible = false
				
	# if not tracking anything, follow the player. this is a lerp to transition smoothly out of targeting state.
	if !tracking:
		# if the player is jumping, lerp to another target pole for smooth vertical camera movement.
		if not is_on_floor():
			$SpringArm3D.position = lerp($SpringArm3D.position, $SpringArmJumpTarget.position, cam_lerp_rate * delta)
		# otherwise, just track the player.
		else:
			$SpringArm3D.position = lerp($SpringArm3D.position, $SpringArmTarget.position, cam_lerp_rate * delta)


func rotate_cam_kb_m(event: InputEvent) -> void:
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


# translates button presses to appropriate assigned weapon actions using value fetching from the weapon_actions dictionary,
# and sends this off to handle_weapon_action to begin executing the appropriate action.
func interpret_weapon_action_handles(event: InputEvent) -> void:
	if movement_state != PlayerMovementState.DAMAGED && movement_state != PlayerMovementState.DEAD:
		# determine which weapon action to execute based on player assignments
		if event.is_action_pressed("weaponaction1"):
			handle_weapon_action(weapon_actions["action1"])
		
		elif event.is_action_pressed("weaponaction2"):
			handle_weapon_action(weapon_actions["action2"])
		
		elif event.is_action_pressed("weaponaction3"):
			handle_weapon_action(weapon_actions["action3"])
		
		elif event.is_action_pressed("weaponaction4"):
			handle_weapon_action(weapon_actions["action4"])


# funnel inputted weapon action into the appropriate function call.
# code is a little redundant here, but needs to be due to special cases,
# such as chained attack combos in the 'attack' weapon action (default attacks).
func handle_weapon_action(command: WeaponAction) -> void:
	match command:
		WeaponAction.ATTACK:
			if current_weapon_action == WeaponAction.NONE || current_weapon_action == WeaponAction.ATTACK:
				if !air_combo_complete:
					weapon_action_attack()
					current_weapon_action = command
		WeaponAction.PARRY:
			if current_weapon_action == WeaponAction.NONE:
				if is_on_floor():
					weapon_action_parry()
					current_weapon_action = command
		WeaponAction.SWING:
			if current_weapon_action == WeaponAction.NONE:
				weapon_action_swing()
				#current_weapon_action = command
		WeaponAction.ULTIMATE:
			if current_weapon_action == WeaponAction.NONE:
				weapon_action_ultimate()
				#current_weapon_action = command
		_:
			print("Not a valid weapon action.")


func weapon_action_attack() -> void:
	# grounded attacks
	if is_on_floor():
		# only begin first animation if not already in ATTACK state.
		if movement_state != PlayerMovementState.ATTACK:
			movement_state = PlayerMovementState.ATTACK
			combat_sweep_area.monitoring = true
			combat_sweep_shape.disabled = !combat_sweep_area.monitoring
			player_speed_current = 0 # resets accel/decel to avoid immediate jumps after attack end
			
			anim_tree.set("parameters/AttackGroundShot1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			current_oneshot_anim = "AttackGroundShot1"
			attack_type = AttackType.GROUND
			current_weapon.visible = true
			sword_trail.trail_enabled = true
			weapon_hitbox.monitoring = true # enable hit detection on player's current_weapon.
			# swap to holding weapon animations
			weapon_blend = 1 # no blend needed since we launch straight into an attack anim
			attack_combo_stage += 1
		# if already attacking, determine if the attack combo is continued.
		else:
			match attack_combo_stage:
				1:
					var anim_duration: float = anim_tree.get("parameters/AttackGroundShot1/time")
					if anim_duration >= 0.2 && anim_duration <= 0.7:
						attack_type = AttackType.GROUND
						continue_attack_chain = true
						vanish_timer.start(vanish_timer_duration)
				2:
					var anim_duration: float = anim_tree.get("parameters/AttackGroundShot2/time")
					if anim_duration > 0.25 && anim_duration < 0.85:
						attack_type = AttackType.GROUND
						continue_attack_chain = true
						vanish_timer.start(vanish_timer_duration)
	# midair attacks
	else:
		if movement_state != PlayerMovementState.ATTACK:
			movement_state = PlayerMovementState.ATTACK
			combat_sweep_area.monitoring = true
			combat_sweep_shape.disabled = !combat_sweep_area.monitoring
			player_speed_current = 0 # resets accel/decel to avoid immediate jumps after attack end
			
			# early out of double jump anim if it's running: it will break midair attack combos otherwise.
			if (anim_tree.get("parameters/DoubleJumpShot/active") == true):
				anim_tree.set("parameters/DoubleJumpShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
			
			anim_tree.set("parameters/AttackAirShot1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			current_oneshot_anim = "AttackAirShot1"
			attack_type = AttackType.AIR
			current_weapon.visible = true
			sword_trail.trail_enabled = true
			weapon_hitbox.monitoring = true
			# swap to holding weapon animations
			weapon_blend = 1 # no blend needed since we launch straight into an attack anim
			attack_combo_stage += 1
		# if already attacking, determine if the attack combo is continued.
		else:
			match attack_combo_stage:
				1:
					var anim_duration: float = anim_tree.get("parameters/AttackAirShot1/time")
					if anim_duration >= 0.1 && anim_duration <= 0.9:
						attack_type = AttackType.AIR
						continue_attack_chain = true
						vanish_timer.start(vanish_timer_duration)
				2:
					var anim_duration: float = anim_tree.get("parameters/AttackAirShot2/time")
					if anim_duration >= 0.1 && anim_duration <= 0.9:
						attack_type = AttackType.AIR
						continue_attack_chain = true
						vanish_timer.start(vanish_timer_duration)


# start the parry action. A chunk of parry logic is housed in take_damage.
func weapon_action_parry() -> void:
	# switch to attack state. do not check if already in attack state, as earlier current_weapon_action check already guarantees this.
	movement_state = PlayerMovementState.ATTACK
	#combat_sweep_area.monitoring = true
	#combat_sweep_shape.disabled = !combat_sweep_area.monitoring
	
	player_speed_current = 0 # resets accel/decel to avoid immediate jumps after attack end
	
	anim_tree.set("parameters/ParryShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	current_oneshot_anim = "ParryShot"
	attack_type = AttackType.PARRY
	current_weapon.visible = true
	sword_trail.trail_enabled = true
	# swap to holding weapon animations
	weapon_blend = 1 # no blend needed since we launch straight into parry anim
	
	print("parry!")


func weapon_action_swing()-> void:
	print("swing!")


func weapon_action_ultimate() -> void:
	print("ult!")


func handle_death(delta: float) -> void:
	var death_anim_string: String = "parameters/" + current_oneshot_anim + "/time"

	var anim_progress: float = anim_tree.get(death_anim_string)

	# once one shot death animation is about to finish, freeze anim tree time to hold the last frame.
	if anim_progress > death_front_cutoff:
		anim_tree.set("parameters/TimeScale/scale", 0.0)

	apply_only_gravity(delta)
	move_and_slide()


# organize array of overlapping objects by distance, closest to farthest.
func sort_objects_by_distance() -> void:
	# makes use of a custom sorting lambda function to compare distances between points and the player, and sort lowest to highest!
	if overlapping_objects.size() > 1:
		overlapping_objects.sort_custom(func(a, b): return a.global_position.distance_squared_to($starblade_wielder.global_position) < b.global_position.distance_squared_to($starblade_wielder.global_position))


func set_anim_blend(delta: float) -> void:
	if blending_weapon_state:
		if weapon_blend <= 0.05:
			weapon_blend = 0.0
			blending_weapon_state = false
		else:
			weapon_blend = lerpf(weapon_blend, 0.0, 2.0 * delta)
	
	# Set the player's animation tree blending value equal to the player's current speed and weapon blend value (for switching between free animations & weapon animations)
	anim_tree.set("parameters/IdleWalkRun_Jump/IdleWalkRunWeaponBlendspace/blend_position", Vector2(velocity.length(), weapon_blend))


# determine what happens when specific animations end.
func _on_animation_tree_animation_finished(anim_name):
	
	if movement_state == PlayerMovementState.ATTACK:
		# if in attack state, determine which type of weapon action was executed.
		match current_weapon_action:
			WeaponAction.ATTACK:
				# reset hit reg for each nearby object at the end of each attack anim.
				for obj in overlapping_objects:
					obj.hit_received = false
				
				# if combo is continuing, determine which animation to play.
				if continue_attack_chain == true:
					combat_sweep_area.monitoring = true
					combat_sweep_shape.disabled = !combat_sweep_area.monitoring
					
					# attack animation combo chain continuation logic
					if anim_name == "AttackComboGround1":
						attack_combo_stage += 1
						anim_tree.set("parameters/AttackGroundShot2/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
						current_oneshot_anim = "AttackGroundShot2"
						
					elif anim_name == "AttackComboGround2":
						attack_combo_stage += 1
						anim_tree.set("parameters/AttackGroundShot3/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
						current_oneshot_anim = "AttackGroundShot3"
						
					elif anim_name == "extra_anims/AttackComboAir1":
						attack_combo_stage += 1
						anim_tree.set("parameters/AttackAirShot2/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
						current_oneshot_anim = "AttackAirShot2"
						
					elif anim_name == "extra_anims/AttackComboAir2":
						attack_combo_stage += 1
						anim_tree.set("parameters/AttackAirShot3/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
						current_oneshot_anim = "AttackAirShot3"
						air_combo_complete = true
					
				# if combo is ending, reset player state.
				else:
					air_combo_complete = true
					movement_state = PlayerMovementState.IDLE
					current_weapon_action = WeaponAction.NONE
					stop_sweep_objects()
					attack_combo_stage = 0
					attack_type = AttackType.NONE
					weapon_hitbox.monitoring = false # disable hit detection on player's current_weapon.
					
					# start timer again so that there is a buffer between when combat ends and when weapon vanishes
					vanish_timer.start(vanish_timer_duration)
				
				# always set back to false so that future combo animations don't play automatically.
				continue_attack_chain = false
			
			WeaponAction.PARRY:
				if anim_name == "extra_anims/Parry":
					movement_state = PlayerMovementState.IDLE
					current_weapon_action = WeaponAction.NONE
					attack_type = AttackType.NONE
					
					vanish_timer.start(vanish_timer_duration)
					
				elif anim_name == "extra_anims/ParrySuccess":
					movement_state = PlayerMovementState.IDLE
					current_weapon_action = WeaponAction.NONE
					attack_type = AttackType.NONE
					
					vanish_timer.start(vanish_timer_duration)
			WeaponAction.SWING:
				pass
			
			WeaponAction.ULTIMATE:
				pass
			_:
				pass
	
	# when damage animation ends, resume normal movement states
	elif movement_state == PlayerMovementState.DAMAGED:
		if anim_name == "extra_anims/TakeDamageFront" || anim_name == "extra_anims/TakeDamageBack" || anim_name == "extra_anims/TakeDamageLeft" || anim_name == "extra_anims/TakeDamageRight":
			movement_state = PlayerMovementState.IDLE


func _on_overlap_area_body_entered(body: Node3D):
	# if this is the first overlapping object, auto-target it (make this a setting later to decide if this is default behavior).
	if overlapping_objects.is_empty():
		overlapping_objects.push_back(body)
		targeted_object = body
		
		targeting = true
		target_icon.visible = true
	# if we already have other overlapping objects, just add it to the array.
	else:
		overlapping_objects.push_back(body)
	
	#print(overlapping_objects)


func _on_overlap_area_body_exited(body: Node3D):
	# remove any body that leaves.
	body.hit_received = false
	overlapping_objects.erase(body)
	
	# if there's no more overlapping objects, drop targeting.
	if overlapping_objects.is_empty():
		targeting = false
		target_icon.visible = false
		targeted_object = null
	# if there's remaining overlapping objects, find the new nearest target and target it (make this a setting later to decide if this is default behavior).
	else:
		sort_objects_by_distance()
		targeted_object = overlapping_objects[0]
		
	#print(overlapping_objects)


func _on_vanish_timer_timeout() -> void:
	print("vanish")
	# not sure if this fix introduces another issue or not, but trying it out.
	# probably creates an edge case where the sword never vanishes, lol
	if movement_state != PlayerMovementState.ATTACK:
		current_weapon.visible = false
		sword_trail.trail_enabled = false
		blending_weapon_state = true


# hit registration on enemies
func _on_sword_hitbox_area_body_entered(body: Node3D):
	if movement_state == PlayerMovementState.ATTACK:
		# check against weapon action so that certain states that fall under the ATTACK umbrella have different behaviors,
		# and so that others, such as parry, don't trigger damage on enemies at all through the sword's actual hitbox.
		match current_weapon_action:
			WeaponAction.ATTACK:
				if !body.hit_received:
					if body is Enemy:
						# might want to make this vary based on animation.
						var attack_anim_string: String = "parameters/" + current_oneshot_anim + "/time"
						var anim_progress: float = anim_tree.get(attack_anim_string)
						var current_attack_damage_anim_cutoff = attack_anim_damage_cutoff
						
						# make the wind-up longer for the player's last combo animation. will probably need tweaking later.
						if current_oneshot_anim == "AttackGroundShot3":
							current_attack_damage_anim_cutoff = attack_anim_damage_cutoff * 1.2
						
						# only register hit if enemy has no i-frames and if player attack animation has properly ramped up.
						if body.i_frames.is_stopped() && anim_progress > current_attack_damage_anim_cutoff:
							#print(anim_progress)
							#print(current_attack_damage_anim_cutoff)
							# mark that the body has received a hit from this attack anim so that it doesn't receive extra.
							# do this per-object so that attacks can hit multiple enemies at once.
							body.hit_received = true
							
							var damage_result: DamageResult
							# inflict damage on the enemy, let them handle the details.
							if current_oneshot_anim == "AttackGroundShot3" || current_oneshot_anim == "AttackAirShot3":
								#inflict extra damage at end of combos.
								damage_result = body.take_damage(player_damage_stat * ground_combo_damage_multiplier, attack_combo_stage)
							else:
								damage_result = body.take_damage(player_damage_stat, attack_combo_stage)
							
							# if enemy dies from this hit, drop targeting and remove them from overlapping objects.
							# can add EXP gain, etc here later
							if damage_result == DamageResult.DEAD:
								targeted_object = null
								targeting = false
								tracking = false
								target_icon.visible = false
								overlapping_objects.erase(body)
			WeaponAction.SWING:
				pass
			WeaponAction.ULTIMATE:
				pass


func take_damage(amount: float, enemy_forward_vector: Vector3) -> DamageResult:
	# if the player is parrying when they're supposed to receive damage, parry instead of receiving said damage if the below requirements are met.
	if current_weapon_action == WeaponAction.PARRY:
		# don't trigger parry success again if it is ongoing while an enemy attacks; that should be the only reason this check is necessary.
		if current_oneshot_anim != "ParrySuccessShot":
			var parry_anim_string: String = "parameters/" + current_oneshot_anim + "/time"
			var anim_progress: float = anim_tree.get(parry_anim_string)
			
			# only succeed on the parry if it is timed well; the beginning and end of the animation shouldn't be included, but rather the apex of the parry.
			# don't return early if this isn't true, instead let the rest of the function play out and deal damage to the player.
			if anim_progress > 0.3 && anim_progress < 0.7:
			
				anim_tree.set("parameters/ParryShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
				anim_tree.set("parameters/ParrySuccessShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
				
				# start player's i-frames.
				# there is a potential that if InvincibilityTimer is still running when a player parries, the parry won't succeed,
				# seeing that the enemy only calls the player's take_damage function if they don't have any i-frames.
				# due to the length of the parry success animation, though, I don't think this will be likely. just an edge case to keep in mind.
				i_frames.start()
				
				print("parry success!")
				return DamageResult.PARRY
			
			else:
				# maybe have some kind of visual effect here later indicating that the parry failed.
				print("parry failed!")
			
		# if the parry weapon action is ongoing but the parry success animation is playing, return 'none' to avoid stunning enemy repeatedly. 
		# this should be an uncommon edge case due to i-frames, if it's even possible at all.
		else:
			return DamageResult.NONE
		
	
	# take damage if the player isn't parrying or if their parry failed.
	player_health_current -= amount
	player_health_current = clamp(player_health_current, 0.0, player_health_max)
	
	# cancel out any existing oneshot animation on the player if it exists.
	# *** this if check will probably need to be modified.
	if movement_state == PlayerMovementState.ATTACK:
		var player_attack_anim: String = "parameters/" + current_oneshot_anim + "/request"
		anim_tree.set(player_attack_anim, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	
	stop_sweep_objects()
	weapon_hitbox.monitoring = false
	player_speed_current = 0
	attack_combo_stage = 0
	# ensure there isn't still an active weapon action
	current_weapon_action = WeaponAction.NONE
	attack_type = AttackType.NONE
	
	# if player is dead, early out of this function and instead call die after damage is dealt.
	if player_health_current == 0.0:
		die()
		return DamageResult.DEAD
	
	movement_state = PlayerMovementState.DAMAGED
	
	# determine the direction the player was hit from.
	var player_forward_vector: Vector3 = $starblade_wielder.transform.basis.z * -1.0
	var hit_from: HitDirection = find_relative_direction(player_forward_vector, enemy_forward_vector)
	
	# use hit direction and play the respective anim.
	match hit_from:
		HitDirection.FRONT:
			anim_tree.set("parameters/TakeDamageFrontShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			current_oneshot_anim = "TakeDamageFrontShot"
		HitDirection.BACK:
			anim_tree.set("parameters/TakeDamageBackShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			current_oneshot_anim = "TakeDamageBackShot"
		HitDirection.RIGHT:
			anim_tree.set("parameters/TakeDamageRightShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			current_oneshot_anim = "TakeDamageRightShot"
		HitDirection.LEFT:
			anim_tree.set("parameters/TakeDamageLeftShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			current_oneshot_anim = "TakeDamageLeftShot"
		_:
			anim_tree.set("parameters/TakeDamageFrontShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
			current_oneshot_anim = "TakeDamageFrontShot"
	
	print("Player hurt! Health: ", player_health_current)
	
	# start player's i-frames.
	i_frames.start()
	
	return DamageResult.NONE

func die() -> void:
	# disable most collisions so that the enemy can't detect the player and vice versa.
	set_collision_layer_value(3, false)
	set_collision_mask_value(3, false)
	
	movement_state = PlayerMovementState.DEAD
	player_speed_current = 0.0
	attack_combo_stage = 0
	velocity = Vector3.ZERO
	$OverlapArea.monitoring = false
	weapon_hitbox.monitoring = false
	current_weapon.visible = false
	targeting = false
	targeted_object = null
	overlapping_objects.clear()
	
	print("player ded!")
	
	anim_tree.set("parameters/DeathFrontShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	current_oneshot_anim = "DeathFrontShot"

func sweep_objects() -> void:
	for enemy: Enemy in sweeping_objects:
		enemy.swept_away = true
		enemy.velocity += current_root_motion * enemy.root_motion_multiplier * 2.5

func stop_sweep_objects() -> void:
	combat_sweep_area.monitoring = false
	combat_sweep_shape.disabled = !combat_sweep_area.monitoring
	for enemy: Enemy in sweeping_objects:
		enemy.swept_away = false
	sweeping_objects.clear()

func _on_combat_sweep_area_body_entered(body: Node3D):
	if body is Enemy: # can probably remove later since collision layers should already only be seeking enemies
		sweeping_objects.append(body)

func _on_combat_sweep_area_body_exited(body: Node3D):
	if body is Enemy: # can probably remove later since collision layers should already only be seeking enemies
		sweeping_objects.erase(body)
		body.velocity = Vector3.ZERO

#region HELPER FUNCTIONS
func tween_val(object: Node, property: NodePath, final_val: Variant, duration: float, trans_type: Tween.TransitionType = Tween.TRANS_LINEAR, ease_type: Tween.EaseType = Tween.EASE_IN_OUT, parallel: bool = true):
	var tween: Tween = get_tree().create_tween()
	tween.stop()
	tween.set_trans(trans_type)
	tween.set_ease(ease_type)
	tween.set_parallel(parallel)
	tween.tween_property(object, property, final_val, duration)
	tween.play()

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

# returns front, back, left, or right.
func find_relative_direction(from: Vector3, to: Vector3) -> HitDirection:
	var angle_diff: float = rad_to_deg(from.signed_angle_to(to, Vector3.UP))
	#print("angle diff: ", angle_diff)
							
	if angle_diff < 45.0 && angle_diff >= -45.0:
		return HitDirection.BACK
	elif angle_diff < -45.0 && angle_diff >= -135.0:
		return HitDirection.LEFT
	elif angle_diff < 135.0 && angle_diff >= 45.0:
		return HitDirection.RIGHT
	elif angle_diff >= 135.0 || angle_diff < -135.0:
		return HitDirection.FRONT
	else:
		return HitDirection.MAX
#endregion
