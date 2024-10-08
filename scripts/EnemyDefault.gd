extends Enemy

class_name EnemyDefault

#region Variable declarations
@export var enemy_health_max: float = 20.0
@export var enemy_health_current: float = enemy_health_max
@export var enemy_normal_damage_stat: float = 3.0
@export var enemy_special_damage_stat: float = enemy_normal_damage_stat * 2.0

@export var enemy_speed: float = 5.0
@export var enemy_decel_rate: float = 0.5
@export var enemy_rotation_rate: float = 7.0
@export var root_motion_multiplier: float = 1.5
var guard_player_distance: float = 32.0
var rng := RandomNumberGenerator.new()
var guard_time_rand: float
@onready var i_frames_in_sec: float = 0.5
@export var wait_time_floor: float = 1.25
@export var wait_time_ceiling: float = 2.0
var current_oneshot_anim: String
@export var attack_anim_damage_cutoff: float = 0.25
@export var takedamage1_rootmotion_cutoff: float = 0.15
@export var takedamage2_rootmotion_cutoff: float = 0.485
@export var death_anim1_cutoff: float = 0.965
var hit_received: bool = false
var swept_away: bool = false
var delta_cache: float
var void_amount: float = 1.0
var void_amount_max: float = 5.0
var void_increment: float = 1.0

@export var enemy_mesh: MeshInstance3D
@onready var anim_tree: AnimationTree = $AnimationTree
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var combat_cast: ShapeCast3D = $EnemyMesh/CombatCast3D # for attacking
@onready var nearby_cast: RayCast3D = $EnemyMesh/NearbyCast3D # for seeing when players are very close
@onready var hit_particles: GPUParticles3D = $EnemyMesh/HitParticles3D
@onready var i_frames: Timer = $InvincibilityTimer

var nearby_allies: Array[Node3D]
var nearby_players: Array[Node3D]
var targeted_player: Node3D = null

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var gravity_multiplier_default: float = 1.0
var gravity_multiplier: float = gravity_multiplier_default

enum EnemyMovementState {
	IDLE = 0,
	ROAMING = 1,
	TRACK = 2,
	GUARD = 3,
	ATTACK = 4,
	DAMAGED = 5,
	STUN = 6,
	FLEE = 7,
	DEAD = 8
}

enum EnemyType {
	SMALL = 0,
	MEDIUM = 1,
	LARGE = 2,
	FLYING = 3
}

enum DamageResult {
	ALIVE = 0,
	DEAD = 1,
	PARRY = 2,
	NONE = 3
}

var movement_state: EnemyMovementState = EnemyMovementState.IDLE
@export var enemy_type: EnemyType # set per enemy type in editor
#endregion

#region Main functions
func _ready() -> void:
	enemy_mesh.get_surface_override_material(0).get_next_pass().set_shader_parameter("VoidAmount", void_amount)
	enemy_mesh.get_surface_override_material(1).get_next_pass().set_shader_parameter("VoidAmount", void_amount)
	
	rng.randomize()
	combat_cast.enabled = false
	combat_cast.add_exception($".") #'Exclude Parent' doesn't seem to work since combat_cast isn't a direct child of EnemyStarfiend, but instead its mesh.
	nearby_cast.add_exception($".")
	
#region Sample State setup.
	# a sample State setup that creates two StateActions using functions in this class, adds them to the State, and adds the State to us, starting the state machine.
	# TODO: Turn this into an easier to use API.
	#var action_print_str: StateAction = StateAction.new(sample_action, ["Ayooooo.", " Bruh"])
	#var action_increment_int: StateAction = StateAction.new(sample_tick_action, [1], true)
	#var actions_arr: Array[StateAction] = [action_print_str, action_increment_int]
	#var test_state: State = State.new(movement_state, actions_arr, test_to_dummy_rule, test_to_dummy_trans)
	#
	#var action_death: StateAction = StateAction.new(death_action)
	#var death_state: State = State.new(EnemyMovementState.DEAD, [action_death], death_rule, death_trans)
	#
	#var action_dummy: StateAction = StateAction.new(dummy_action)
	#var dummy_state: State = State.new(EnemyMovementState.STUN, [action_dummy], dummy_breakout_rule, dummy_breakout_trans)
	#var dummy_sm: StateMachine = StateMachine.new([dummy_state], dummy_sm_to_death_rule, dummy_sm_to_death_trans)
	#
	#var test_state_machine: StateMachine = StateMachine.new([test_state, dummy_sm, death_state])
	#add_child(test_state_machine) # begins execution

# a sample action that prints two strings put together.
func sample_action(args: Array) -> void:
	var str: String = args[0]
	var str2: String = args[1]
	print(str + str2)

# a sample action that increments a number every (physics) tick until it reaches a certain value.
var start: int = 5
func sample_tick_action(args: Array, owning_action: StateAction) -> void:
	start += args[0]
	print(start)
	
	if start > 10:
		start = 5
		owning_action.emit_signal("action_complete")

func test_to_dummy_rule() -> bool:
	print("Test to Dummy rule!")
	return true

func test_to_dummy_trans() -> int:
	print("Test to Dummy trans!")
	return 1 # keep in mind these are still just using raw array positions for now - the order States are added to a StateMachine.

func dummy_action(args: Array) -> void:
	print("dummy!!!!")

func dummy_breakout_rule() -> bool:
	print("Dummy breakout rule!")
	return true

func dummy_breakout_trans() -> int:
	print("Dummy breakout trans - exit StateMachine!")
	return StateBase.ReservedTransitions.BREAKOUT

func dummy_sm_to_death_rule() -> bool:
	print("Dummy SM to Death rule!")
	return true

func dummy_sm_to_death_trans() -> int:
	print("Dummy SM to Death trans!")
	return 2

func death_rule() -> bool:
	print("Death to end rule!")
	return true

func death_trans() -> int:
	print("Death to halt.")
	return StateBase.ReservedTransitions.STOP

func death_action(args: Array) -> void:
	print("death!!!")

#endregion

# clear materials just as node is deleted to avoid debugger errors. see: https://github.com/godotengine/godot/issues/67144
func _exit_tree():
	enemy_mesh.set("surface_material_override/0", null)
	enemy_mesh.set("surface_material_override/1", null)

func _physics_process(delta: float) -> void:
	#print(velocity.length())
	#print(is_on_floor())
	apply_only_gravity(delta)
	move_and_slide()
	
	## if dead, stay dead.
	#if movement_state == EnemyMovementState.DEAD:
		#handle_dead_state(delta)
	## if not dead, do something.
	#else:
		#anim_tree.set("parameters/IdleRunBlendspace/blend_position", velocity.length())
		## if there is a player, do something
		#if targeted_player != null:
			## if we are tracking, follow the player.
			#if movement_state == EnemyMovementState.TRACK:
				#delta_cache = delta
				## for whatever reason none of this logic works if abstracted into another function.
				#if !$GuardTimer.is_stopped():
					#$GuardTimer.stop()
				#
				##execute_nav(delta)
				#
				## face the player smoothly
				#rotate_enemy_tracking(delta)
			#
			## if guarding, periodically check what the player is doing.
			#elif movement_state == EnemyMovementState.GUARD:
				#handle_guard_state(delta)
			#
			#elif movement_state == EnemyMovementState.ATTACK:
				#handle_attack_state(delta)
			#
			## this state only being called when there is a targeted player could cause issues at distance if such a scenario occurs.
			#elif movement_state == EnemyMovementState.DAMAGED:
				#handle_damaged_state(delta)
			#
			##print(movement_state)
		## if there's no player, just be still. (add roaming here later)
		#else:
			#movement_state = EnemyMovementState.IDLE
			#apply_only_gravity(delta)
			#
			#if is_on_floor():
				#velocity = Vector3.ZERO
			#else:
				#velocity = Vector3(0.0, velocity.y, 0.0)
			
			#move_and_slide()
			
		# reset velocity at the end if the enemy is being swept by the player since that uses root motion.
		# just don't worry about gravity problems for now
	if swept_away:
		velocity = Vector3.ZERO
#endregion

#region Movement functions
func apply_only_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta

# navigates to a player, relying on target_pos (updated from update_nav_target_pos)
func execute_nav(delta: float, avoidance: bool = true) -> void:
	var new_velocity: Vector3
	# only navigate if the target can be reached.
	if nav_agent.is_target_reachable():
		var current_location: Vector3 = global_position
		var next_location: Vector3 = nav_agent.get_next_path_position()
		# get the direction to the next point, and multiply that by an arbitrary speed to get a new velocity (vector) w/ direction + magnitude.
		new_velocity = (next_location - current_location).normalized() * enemy_speed
	else:
		new_velocity = Vector3(0.0, velocity.y, 0.0)
	
	if avoidance:
		# converts our newly calculated velocity to a 'safe velocity' that factors in other nearby agents, etc.
		# see _on_navigation_agent_3d_velocity_computed.
		nav_agent.velocity = new_velocity
	else:
		#velocity = new_velocity
		apply_only_gravity(delta)
		move_and_slide()
	
	#print(nav_agent.is_target_reachable())

# called by the level itself, as of now Level.gd. For TRACK mode only.
func update_nav_target_pos(target_pos: Vector3) -> void:
	# if tracking, move towards the player's position.
	if movement_state == EnemyMovementState.TRACK:
		nav_agent.set_target_position(target_pos)

# determine how to move when applying root motion.
func handle_root_motion(delta: float, rm_multiplier: float = root_motion_multiplier, lateral_only: bool = false) -> void:
	var up_vector: Vector3 = Vector3(0.0, 1.0, 0.0)
	# get the root motion position vector for the current frame, and rotate it to match the player's rotation.
	var root_motion: Vector3 = anim_tree.get_root_motion_position().rotated(up_vector, $EnemyMesh.rotation.y) / delta
	
	if lateral_only:
		velocity.x += root_motion.x * rm_multiplier
		velocity.z += root_motion.z * rm_multiplier
	else:
		# apply root motion, and multiply it by an arbitrary value to get a speed that makes sense.
		velocity += root_motion * rm_multiplier
	
	# still add gravity if not on floor
	apply_only_gravity(delta)


# when enemy gets within a set distance to the target (player), switch to guard state.
func _on_navigation_agent_3d_target_reached():
	if movement_state == EnemyMovementState.TRACK:
		print("reached!")
		movement_state = EnemyMovementState.GUARD
		$NavigationAgent3D.avoidance_enabled = true
		# change this to decel
		velocity = Vector3.ZERO


# final velocity when in track mode.
func _on_navigation_agent_3d_velocity_computed(safe_velocity):
	if is_on_floor():
		# smoother velocity with move_toward, helps with corners, etc
		velocity = velocity.move_toward(safe_velocity, enemy_decel_rate)
		apply_only_gravity(delta_cache)
		move_and_slide()
#endregion

#region Combat functions
# starts guard timer, randomizing its exact wait time.
func start_guard_timer() -> void:
	rng.randomize()
	guard_time_rand = rng.randf_range(wait_time_floor, wait_time_ceiling)
	$GuardTimer.wait_time = guard_time_rand
	$GuardTimer.start()

func begin_attack() -> void:
	movement_state = EnemyMovementState.ATTACK
	combat_cast.enabled = true
	anim_tree.set("parameters/AttackShot1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	current_oneshot_anim = "AttackShot1"
	$GuardTimer.stop()

func handle_attack_state(delta: float) -> void:
	# in attack state, drive velocity with root motion from anim.
	handle_root_motion(delta, root_motion_multiplier * 3.0)
	move_and_slide()
	
	# reset velocity at end of each tick (after move_and_slide) so that it does not accumulate when using root motion.
	velocity = Vector3.ZERO
			
	if movement_state == EnemyMovementState.ATTACK:
		# damage player, WIP
		if combat_cast.is_colliding():
			#print(combat_cast.collision_result)
			#print(combat_cast.get_collision_count())
			
			# leaving this a for loop for now, in case of potential multiplayer later.
			# if not, replace with - if combat_cast.collision_result[0]["collider"]:
			# also change combat_cast.max_results to a lower value if SP only, at 4 right now.
			for col in combat_cast.collision_result:
				
				if !col["collider"].hit_received:
					var attack_anim_string: String = "parameters/" + current_oneshot_anim + "/time"
					var anim_progress: float = anim_tree.get(attack_anim_string)
						
					# only register hit if player has no i-frames and if enemy attack animation has properly ramped up.
					if col["collider"].i_frames.is_stopped() && anim_progress > attack_anim_damage_cutoff:
						# mark that the body has received a hit from this attack anim so that it doesn't receive extra.
						# do this per-object so that attacks can hit multiple enemies at once.
						col["collider"].hit_received = true
						
						# inflict damage on the player, let them handle the details.
						var damage_result: DamageResult = col["collider"].take_damage(enemy_normal_damage_stat, $EnemyMesh.transform.basis.z * -1.0)
						
						if damage_result == DamageResult.DEAD:
							nearby_players.erase(col["collider"])
							if !nearby_players.is_empty():
								targeted_player = nearby_players[0]
							else:
								targeted_player = null
							
						elif damage_result == DamageResult.PARRY:
							print("Fuck!!")

func handle_guard_state(delta: float) -> void:
	if $GuardTimer.is_stopped():
		start_guard_timer()
			
	# face the player smoothly
	rotate_enemy_tracking(delta)
	apply_only_gravity(delta)
	move_and_slide()

func _on_guard_timer_timeout():
	if targeted_player != null && movement_state != EnemyMovementState.DEAD:
		# if the player gets too far away, resume tracking.
		var to_player: Vector3 = targeted_player.global_position - $EnemyMesh.global_position
		if to_player.length_squared() > guard_player_distance:
			movement_state = EnemyMovementState.TRACK
		# if the player is in range, attack!
		else:
			begin_attack()

func handle_damaged_state(delta: float) -> void:
	if !$GuardTimer.is_stopped():
		$GuardTimer.stop()
	
	var reset_velocity: bool = true
	var anim_string: String = "parameters/" + current_oneshot_anim + "/time"
	var anim_progress: float = anim_tree.get(anim_string)
	
	# precise handling of velocity based on animation states/progression.
	if current_oneshot_anim == "TakeDamageShot1":
		# apply only gravity when the enemy is a little ways into this anim and not on the ground. otherwise, full root motion.
		# this is tuned specifically for TakeDamage2.
		if anim_progress > takedamage1_rootmotion_cutoff && !is_on_floor():
			apply_only_gravity(delta)
			reset_velocity = false
		else:
			handle_root_motion(delta, root_motion_multiplier * 0.9)
			
	elif current_oneshot_anim == "TakeDamageShot2":
		# apply only gravity when the enemy is near the end of this anim and not on the ground. otherwise, full root motion.
		# this is tuned specifically for TakeDamage2.
		if anim_progress > takedamage2_rootmotion_cutoff && !is_on_floor():
			apply_only_gravity(delta)
			reset_velocity = false
		else:
			# enemy's own root motion
			handle_root_motion(delta, root_motion_multiplier * 0.9)
	
	move_and_slide()
	
	if reset_velocity:
		# reset velocity at end of each tick (after move_and_slide) so that it does not accumulate when using root motion.
		velocity = Vector3.ZERO

func rotate_enemy_tracking(delta: float) -> void:
	face_object_lerp($EnemyMesh, targeted_player.position, Vector3.UP, delta)
	# zero out X and Z rotations so that the enemy can't rotate in odd ways.
	$EnemyMesh.rotation.x = 0.0
	$EnemyMesh.rotation.z = 0.0

func take_damage(amount: float, player_combo_stage: int) -> DamageResult:
	# take damage.
	enemy_health_current -= amount
	enemy_health_current = clamp(enemy_health_current, 0.0, enemy_health_max)
	
	# cancel out any existing oneshot animation on the enemy if it exists.
	# *** this if check will probably need to be modified.
	if movement_state == EnemyMovementState.ATTACK:
		var enemy_attack_anim: String = "parameters/" + current_oneshot_anim + "/request"
		anim_tree.set(enemy_attack_anim, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	
	velocity = Vector3.ZERO
	hit_particles.emitting = true # only have to set once, due to particles being a one-shot.
	
	# if enemy is dead, early out of this function and instead call die after damage is dealt.
	if enemy_health_current == 0.0:
		die()
		return DamageResult.DEAD
		
	# switch enemy state to damaged.
	movement_state = EnemyMovementState.DAMAGED
	
	# determine which hit animation enemy plays. move damage into this as well later so that it varies.
	if player_combo_stage > 2:
		anim_tree.set("parameters/TakeDamageShot2/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		current_oneshot_anim = "TakeDamageShot2"
	else:
		anim_tree.set("parameters/TakeDamageShot1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
		current_oneshot_anim = "TakeDamageShot1"
	
	print("Enemy hurt! health: ", enemy_health_current)
	
	# begin enemy's i-frames.
	i_frames.wait_time = i_frames_in_sec
	i_frames.start()
	
	return DamageResult.ALIVE

func take_parry() -> void:
	pass
#endregion

#region Death functions
func handle_dead_state(delta: float) -> void:
	# death particle/shader effects
	if void_amount < void_amount_max:
		void_amount += void_increment * delta
	else:
		void_amount = void_amount_max
			
		if $DeleteTimer.is_stopped():
			$DeleteTimer.start()
			
	if void_amount > void_amount_max * 0.25 && void_amount < void_amount_max - 0.1:
		hit_particles.emitting = true
	
	enemy_mesh.get_surface_override_material(1).get_next_pass().set_shader_parameter("VoidAmount", void_amount)
	enemy_mesh.get_surface_override_material(0).get_next_pass().set_shader_parameter("VoidAmount", void_amount)
		
	var attack_anim_string: String = "parameters/" + current_oneshot_anim + "/time"
	var anim_progress: float = anim_tree.get(attack_anim_string)
	
	
	if anim_progress > death_anim1_cutoff * 0.5 && is_on_floor():
		# slow gravity further so that the enemy slowly sinks through the floor.
		gravity_multiplier = gravity_multiplier_default * 0.002
		
	# once one shot death animation is about to finish, freeze anim tree time to hold the last frame.
	if anim_progress > death_anim1_cutoff:
		# turn off ground collisions for sinking through floor.
		set_collision_mask_value(1, false)
		anim_tree.set("parameters/TimeScale/scale", 0.0)
		
	# move hit particles down towards feet.
	hit_particles.global_position = hit_particles.global_position.move_toward(global_position, 1.0 * delta)
		
	# just add gravity in case of dying in midair
	handle_root_motion(delta, root_motion_multiplier * 1.5)
	
	# all below could prolly be optimized
	apply_only_gravity(delta)
	move_and_slide()
		
	if is_on_floor():
		velocity = Vector3.ZERO
	else:
		velocity = Vector3(0.0, velocity.y, 0.0)

# despawn this enemy once dead.
func _on_delete_timer_timeout():
	$OverlapArea.set_collision_layer_value(3, false)
	$OverlapArea.set_collision_mask_value(3, false)
	
	nearby_players.clear() # unsure if necessary
	nearby_allies.clear() # unsure if necessary
	
	print("goobye!")
	call_deferred("queue_free")

func die() -> void:
	$CollisionDisableTimer.timeout.connect(func():
		set_collision_layer_value(2, false)
		set_collision_mask_value(3, false)
	)
	
	# disable most collisions so that the enemy can't detect the player and vice versa.
	#set_collision_layer_value(2, false)
	#set_collision_mask_value(3, false)
	$CollisionDisableTimer.start()
	
	movement_state = EnemyMovementState.DEAD
	velocity = Vector3.ZERO
	swept_away = false
	targeted_player = null # unsure if necessary
	#nearby_cast.enabled = false
	combat_cast.enabled = false
	gravity_multiplier *= 0.25
	hit_particles.amount = 50
	print("enemy ded!")
	
	anim_tree.set("parameters/DieShot1/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	current_oneshot_anim = "DieShot1"
#endregion

#region Animation functions
func _on_animation_tree_animation_finished(anim_name):
	# if finishing attack animation, resume TRACK state.
	if movement_state == EnemyMovementState.ATTACK:
		# reset hit reg for each nearby player at the end of each attack anim. if empty, I believe nothing will happen rather than a crash.
		for player in nearby_players:
			player.hit_received = false
		
		if anim_name == "EnemyAttack1":
			if nearby_players.is_empty():
				movement_state = EnemyMovementState.IDLE
			else:
				movement_state = EnemyMovementState.TRACK
			combat_cast.enabled = false
	
	# if ending taking damage, resume track or guard state if we have a player still, and idle if not.
	elif movement_state == EnemyMovementState.DAMAGED:
		if targeted_player != null:
			if anim_name == "TakeDamage1" || anim_name == "TakeDamage2":
				swept_away = false
				
				var to_player: Vector3 = targeted_player.global_position - $EnemyMesh.global_position
				if to_player.length_squared() > guard_player_distance:
					movement_state = EnemyMovementState.TRACK
				else:
					movement_state = EnemyMovementState.GUARD
		else:
			movement_state = EnemyMovementState.IDLE
#endregion

#region Overlap functions
func _on_overlap_area_body_entered(body: Node3D):
	if body is Player:
		if nearby_players.is_empty():
			nearby_players.push_back(body)
			targeted_player = body
		else:
			nearby_players.push_back(body)
		
		# if idling or roaming when a player comes into periphery, track them.
		if movement_state == EnemyMovementState.IDLE || movement_state == EnemyMovementState.ROAMING:
			movement_state = EnemyMovementState.TRACK
			
	elif body is Enemy:
		# don't be aware of self, of course. necessary because of collision layer junk.
		if !(body == $"."):
			nearby_allies.push_back(body)
			combat_cast.add_exception(body)
			nearby_cast.add_exception(body)
			#print(nearby_allies)


func _on_overlap_area_body_exited(body: Node3D):
	if body is Player:
		body.hit_received = false
		nearby_players.erase(body)
		
		if nearby_players.is_empty():
			targeted_player = null
		
	elif body is Enemy:
		nearby_allies.erase(body)
		combat_cast.remove_exception(body)
		nearby_cast.remove_exception(body)
#endregion

#region Helper functions
func tween_val(object: Node, property: NodePath, final_val: Variant, duration: float, trans_type: Tween.TransitionType = Tween.TRANS_LINEAR, ease_type: Tween.EaseType = Tween.EASE_IN_OUT, parallel: bool = true):
	var tween: Tween = get_tree().create_tween()
	tween.stop()
	tween.set_trans(trans_type)
	tween.set_ease(ease_type)
	tween.set_parallel(parallel)
	tween.tween_property(object, property, final_val, duration)
	tween.play()

# finds a randomized position in a given circumference around a target. does not check if said position is valid on terrain.
func find_random_pos_around_target(radius: float = 3.0, target_pos: Vector3 = targeted_player.global_position) -> Vector3:
	rng.randomize()
	var random_angle: float = rng.randf_range(-180.0, 180.0)
	return target_pos + target_pos.normalized().rotated(Vector3.UP, deg_to_rad(random_angle)) * radius

# for meshes, such as player (minor modification of looking_at)
func facing_object(target: Vector3, up: Vector3)-> Basis:
	var v_z: Vector3 = target.normalized()
	var v_x: Vector3 = up.cross(v_z)
	
	v_x.normalized()
	var v_y: Vector3 = v_z.cross(v_x)
	
	var v_basis: Basis = Basis(v_x, v_y, v_z)
	return v_basis

# for meshes, such as player (minor modification of looking_at_from_position)
func facing_object_from_pos_lerp(obj: Node3D, pos: Vector3, target: Vector3, up: Vector3, delta: float) -> void:
	var lookat: Transform3D = Transform3D(facing_object(target - pos, up), pos)
	var original_scale: Vector3 = obj.scale
	#obj.global_transform = lerp(obj.global_transform, lookat, player_rotation_rate * delta)
	obj.global_transform = obj.global_transform.interpolate_with(lookat, enemy_rotation_rate * delta)
	#obj.global_transform = lookat
	obj.scale = original_scale

# for meshes, such as player (minor modification of look_at)
func face_object_lerp(obj: Node3D, target: Vector3, up: Vector3, delta: float) -> void:
	var origin: Vector3 = obj.global_transform.origin
	facing_object_from_pos_lerp(obj, origin, target, up, delta)

# returns front, back, left, or right.
func find_relative_direction(from: Vector3, to: Vector3) -> String:
	var angle_diff: float = rad_to_deg(from.signed_angle_to(to, Vector3.UP))
	#print("angle diff: ", angle_diff)
	
	if angle_diff < 45.0 && angle_diff >= -45.0:
		return "back"
	elif angle_diff < -45.0 && angle_diff >= -135.0:
		return "left"
	elif angle_diff < 135.0 && angle_diff >= 45.0:
		return "right"
	elif angle_diff >= 135.0 || angle_diff < -135.0:
		return "front"
	else:
		return "?"

# this is probably mislabeled somewhat lol
func find_relative_direction_eightway(from: Vector3, to: Vector3) -> String:
	var angle_diff: float = rad_to_deg(from.signed_angle_to(to, Vector3.UP))
	
	if angle_diff < 45.0 && angle_diff >= 0.0:
		return "back-left"
	elif angle_diff < 0.0 && angle_diff >= -45.0:
		return "back-right"
	elif angle_diff < -45.0 && angle_diff >= -90.0:
		return "left-left"
	elif angle_diff < -90.0 && angle_diff >= -135.0:
		return "left-right"
	elif angle_diff < 135.0 && angle_diff >= 90.0:
		return "right-left"
	elif angle_diff < 90.0 && angle_diff >= 45.0:
		return "right-right"
	elif angle_diff >= 135.0 && angle_diff <= 180.0:
		return "front-left"
	elif angle_diff < -135.0 && angle_diff >= -180.0:
		return "front-right"
	else:
		return "?"
#endregion
