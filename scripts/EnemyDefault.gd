extends Enemy

class_name EnemyDefault

@export var enemy_health_max: float = 20.0
@export var enemy_health_current: float = enemy_health_max
@export var enemy_normal_damage_stat: float = 3.0
@export var enemy_special_damage_stat: float = enemy_normal_damage_stat * 2.0

@export var enemy_speed: float = 5.0
@export var enemy_decel_rate: float = 16.0
@export var enemy_rotation_rate: float = 7.0
@export var root_motion_multiplier: float = 20000.0
var guard_player_distance: float = 32.0
var rng := RandomNumberGenerator.new()
var guard_time_rand: float
@onready var i_frames_in_sec: float = 0.5
@export var wait_time_floor: float = 1.5
@export var wait_time_ceiling: float = 2.5
var current_oneshot_anim: String
@export var attack_anim_damage_cutoff: float = 0.25
@export var takedamage1_rootmotion_cutoff: float = 0.15
@export var takedamage2_rootmotion_cutoff: float = 0.485
var hit_received: bool = false
var slide_away: bool = false
var delta_cache: float = 0.0

@onready var anim_tree: AnimationTree = $AnimationTree
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var combat_cast: ShapeCast3D = $EnemyMesh/CombatCast3D
@onready var nearby_cast: RayCast3D = $EnemyMesh/NearbyCast3D
@onready var i_frames: Timer = $InvincibilityTimer

var nearby_allies: Array[Node3D]
var nearby_players: Array[Node3D]
var targeted_player: Node3D = null

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
@export var gravity_multiplier: float = 1.0

enum EnemyMovementState {
	IDLE = 0,
	ROAMING = 1,
	TRACK = 2,
	RELOCATE = 3,
	GUARD = 4,
	ATTACK = 5,
	DAMAGED = 6,
	FLEE = 7,
	DEAD = 8
}

enum EnemyType {
	SMALL = 0,
	MEDIUM = 1,
	LARGE = 2,
	FLYING = 3
}

var movement_state: EnemyMovementState = EnemyMovementState.IDLE
@export var enemy_type: EnemyType # set per enemy type in editor

func _ready() -> void:
	rng.randomize()
	combat_cast.enabled = false
	combat_cast.add_exception($".") #'Exclude Parent' doesn't seem to work since combat_cast isn't a direct child of EnemyStarfiend, but instead its mesh.
	nearby_cast.add_exception($".")


func _physics_process(delta: float) -> void:
	#print(velocity.length())
	#print(is_on_floor())
	anim_tree.set("parameters/IdleRunBlendspace/blend_position", velocity.length())
	# if there is a player, do something
	if targeted_player != null:
		# if we are tracking, follow the player.
		if movement_state == EnemyMovementState.TRACK:
			# for whatever reason none of this logic works if abstracted into another function.
			if !$GuardTimer.is_stopped():
				$GuardTimer.stop()
			
			delta_cache = delta
			
			execute_nav(delta)
			
			# face the player smoothly
			rotate_enemy_tracking(delta)
			
		# if guarding, periodically check what the player is doing.
		elif movement_state == EnemyMovementState.GUARD:
			handle_guard_state(delta)
		
		elif movement_state == EnemyMovementState.ATTACK:
			handle_attack_state(delta)
		
		elif movement_state == EnemyMovementState.DAMAGED:
			handle_damaged_state(delta)
			
		#print(movement_state)
	# if there's no player, just be still. (add roaming here later)
	else:
		movement_state = EnemyMovementState.IDLE
		apply_only_gravity(delta)
		
		if is_on_floor():
			velocity = Vector3.ZERO
		else:
			velocity = Vector3(0.0, velocity.y, 0.0)
		
		move_and_slide()


func apply_only_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * gravity_multiplier * delta


# navigates to a player, relying on target_pos (updated from update_nav_target_pos)
func execute_nav(delta: float, modifier: float = 120.0) -> void:
	var new_velocity: Vector3
	# only navigate if the target can be reached.
	if nav_agent.is_target_reachable():
		var current_location: Vector3 = global_position
		var next_location: Vector3 = nav_agent.get_next_path_position()
		# get the direction to the next point, and multiply that by an arbitrary speed to get a new velocity (vector) w/ direction + magnitude.
		new_velocity = (next_location - current_location).normalized() * enemy_speed * delta * modifier
	else:
		new_velocity = Vector3(0.0, velocity.y, 0.0)
	
	# converts our newly calculated velocity to a 'safe velocity' that factors in other nearby agents, etc.
	# see _on_navigation_agent_3d_velocity_computed.
	nav_agent.set_velocity(new_velocity)
	
	#print(nav_agent.is_target_reachable())


# called by the level itself, as of now Level.gd
func update_nav_target_pos(target_pos: Vector3) -> void:
	if movement_state == EnemyMovementState.TRACK:
		nav_agent.set_target_position(target_pos)


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
						col["collider"].take_damage(enemy_normal_damage_stat, $EnemyMesh.transform.basis.z * -1.0)


func handle_guard_state(delta: float) -> void:
	# if the enemy is touching the player from the front while the player is attacking, slide them using the same root motion vector as the player, but increased.
	# this makes combat feel much better when colliding with enemies, but it still isn't perfect.
	if nearby_cast.is_colliding():
		var player: CharacterBody3D = nearby_cast.get_collider()
		# an eight_directional version of find_relative_direction *might* be preferable here later.
		var player_dir: String = find_relative_direction($EnemyMesh.transform.basis.z * -1.0, player.player_mesh.transform.basis.z * -1.0)
		#print(player_dir)
		if player.movement_state == player.PlayerMovementState.ATTACK && player_dir == "front":
			slide_away = true
		else:
			# I think this is fine, may help with edge cases
			slide_away = false
	
	
	# slide away from the player using their velocity when the player is attacking.
	if slide_away:
		# this line could break later with multiplayer
		var root_motion: Vector3 = nearby_players[0].anim_tree.get_root_motion_position().rotated(Vector3.UP, nearby_players[0].player_mesh.rotation.y)
		velocity += root_motion * 50000.0 * delta
		
	
	if $GuardTimer.is_stopped():
		start_guard_timer()
			
	# face the player smoothly
	rotate_enemy_tracking(delta)
	apply_only_gravity(delta)
	move_and_slide()
	
	# reset velocity at the end since we're using root motion.
	if is_on_floor():
		velocity = Vector3.ZERO
	else:
		velocity = Vector3(0.0, velocity.y, 0.0)


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
			handle_root_motion(delta)
			
	elif current_oneshot_anim == "TakeDamageShot2":
		# apply only gravity when the enemy is near the end of this anim and not on the ground. otherwise, full root motion.
		# this is tuned specifically for TakeDamage2.
		if anim_progress > takedamage2_rootmotion_cutoff && !is_on_floor():
			apply_only_gravity(delta)
			reset_velocity = false
		else:
			# enemy's own root motion
			handle_root_motion(delta)
			
			# additionally, keep adding some of the player's root motion.
			if slide_away:
				var root_motion: Vector3 = nearby_players[0].anim_tree.get_root_motion_position().rotated(Vector3.UP, nearby_players[0].player_mesh.rotation.y)
				velocity += root_motion * 50000.0 * delta
		
	move_and_slide()
	
	if reset_velocity:
		# reset velocity at end of each tick (after move_and_slide) so that it does not accumulate when using root motion.
		velocity = Vector3.ZERO


func rotate_enemy_tracking(delta: float) -> void:
	face_object_lerp($EnemyMesh, targeted_player.position, Vector3.UP, delta)
	# zero out X and Z rotations so that the enemy can't rotate in odd ways.
	$EnemyMesh.rotation.x = 0.0;
	$EnemyMesh.rotation.z = 0.0;


# determine how to move when applying root motion.
func handle_root_motion(delta: float, rm_multiplier: float = root_motion_multiplier, lateral_only: bool = false) -> void:
	var up_vector: Vector3 = Vector3(0.0, 1.0, 0.0)
	# get the root motion position vector for the current frame, and rotate it to match the player's rotation.
	var root_motion: Vector3 = anim_tree.get_root_motion_position().rotated(up_vector, $EnemyMesh.rotation.y)
	
	if lateral_only:
		velocity.x += root_motion.x * rm_multiplier * delta
		velocity.z += root_motion.z * rm_multiplier * delta
	else:
		# apply root motion, and multiply it by an arbitrary value to get a speed that makes sense.
		velocity += root_motion * rm_multiplier * delta
	
	# still add gravity if not on floor
	apply_only_gravity(delta)


# when enemy gets within a set distance to the target (player), switch to guard state.
func _on_navigation_agent_3d_target_reached():
	if movement_state == EnemyMovementState.TRACK || movement_state == EnemyMovementState.RELOCATE:
		movement_state = EnemyMovementState.GUARD
		# change this to decel
		velocity = Vector3.ZERO


# final velocity when in track mode.
func _on_navigation_agent_3d_velocity_computed(safe_velocity):
	# smoother velocity with move_toward, helps with corners, etc
	velocity = velocity.move_toward(safe_velocity, 12.0 * delta_cache)
	apply_only_gravity(delta_cache)
	move_and_slide()


func _on_guard_timer_timeout():
	if targeted_player != null:
		# if the player gets too far away, resume tracking.
		var to_player: Vector3 = targeted_player.global_position - $EnemyMesh.global_position
		if to_player.length_squared() > guard_player_distance:
			movement_state = EnemyMovementState.TRACK
		# if the player is in range, attack!
		else:
			begin_attack()


func take_damage(amount: float, player_combo_stage: int) -> void:
	# take damage.
	enemy_health_current -= amount
	enemy_health_current = clamp(enemy_health_current, 0.0, enemy_health_max)
	
	# cancel out any existing oneshot animation on the enemy if it exists.
	# *** this if check will probably need to be modified.
	if movement_state == EnemyMovementState.ATTACK:
		var enemy_attack_anim: String = "parameters/" + current_oneshot_anim + "/request"
		anim_tree.set(enemy_attack_anim, AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		
	# switch enemy state to damaged.
	movement_state = EnemyMovementState.DAMAGED
	velocity = Vector3.ZERO
	
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


func _on_animation_tree_animation_finished(anim_name):
	# if finishing attack animation, resume TRACK state.
	if movement_state == EnemyMovementState.ATTACK:
		# reset hit reg for each nearby player at the end of each attack anim.
		for player in nearby_players:
			player.hit_received = false
		
		if anim_name == "EnemyAttack1":
			movement_state = EnemyMovementState.TRACK
			combat_cast.enabled = false
	
	# if ending taking damage, resume track or guard state if we have a player still, and idle if not.
	elif movement_state == EnemyMovementState.DAMAGED:
		if targeted_player != null:
			if anim_name == "TakeDamage1" || anim_name == "TakeDamage2":
				slide_away = false
				
				var to_player: Vector3 = targeted_player.global_position - $EnemyMesh.global_position
				if to_player.length_squared() > guard_player_distance:
					movement_state = EnemyMovementState.TRACK
				else:
					movement_state = EnemyMovementState.GUARD
		else:
			movement_state = EnemyMovementState.IDLE


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


### HELPER FUNCTIONS
func tween_val(object: Node, property: NodePath, final_val: Variant, duration: float, trans_type: Tween.TransitionType = Tween.TRANS_LINEAR, ease_type: Tween.EaseType = Tween.EASE_IN_OUT, parallel: bool = true):
	var tween: Tween = get_tree().create_tween()
	tween.stop()
	tween.set_trans(trans_type)
	tween.set_ease(ease_type)
	tween.set_parallel(parallel)
	tween.tween_property(object, property, final_val, duration)
	tween.play()
	
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


