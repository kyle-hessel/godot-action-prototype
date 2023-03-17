extends CharacterBody3D

class_name Enemy

var enemy_speed: float = 5.0
@export var enemy_rotation_rate: float = 7.0

@onready var collision_shape : CollisionShape3D = $CollisionShape3D
@onready var nav_agent : NavigationAgent3D = $NavigationAgent3D

var nearby_players: Array[Node3D]
var targeted_player: Node3D = null

enum EnemyMovementState {
	IDLE = 0,
	ROAMING = 1,
	TRACK = 2,
	RELOCATE = 3,
	GUARD = 4,
	ATTACK = 5,
	FLEE = 6,
	DAMAGED = 7
}

var movement_state: EnemyMovementState = EnemyMovementState.IDLE

func _ready() -> void:
	pass


func _physics_process(delta: float) -> void:
	# if there is a player, do something
	if targeted_player != null:
		
		# if we aren't on guard, navigate.
		if movement_state != EnemyMovementState.GUARD:
			if !$GuardTimer.is_stopped():
				$GuardTimer.stop()
				
			execute_nav(delta)
			
			# face the player smoothly
			rotate_enemy_tracking(delta)
			
		# if guarding, periodically check what the player is doing.
		else:
			if $GuardTimer.is_stopped():
				$GuardTimer.start()
			
			# face the player smoothly
			rotate_enemy_tracking(delta)
	# if there's no player, just be still.
	else:
		movement_state = EnemyMovementState.IDLE
		velocity = Vector3.ZERO


# navigates to a player, relying on target_pos (updated from update_nav_target_pos)
func execute_nav(delta: float, modifier: float = 120.0) -> void:
	var new_velocity: Vector3
	movement_state = EnemyMovementState.TRACK
	
	# only navigate if the target can be reached.
	if nav_agent.is_target_reachable():
		var current_location: Vector3 = global_position
		var next_location: Vector3 = nav_agent.get_next_path_position()
		# get the direction to the next point, and multiply that by an arbitrary speed to get a new velocity (vector) w/ direction + magnitude.
		new_velocity = (next_location - current_location).normalized() * enemy_speed * delta * modifier
	else:
		new_velocity = Vector3.ZERO
		#movement_state = EnemyMovementState.IDLE
	
	# converts our newly calculated velocity to a 'safe velocity' that factors in other nearby agents, etc.
	# see _on_navigation_agent_3d_velocity_computed.
	nav_agent.set_velocity(new_velocity)
	
	print(nav_agent.is_target_reachable())


# called by the level itself, as of now Level.gd
func update_nav_target_pos(target_pos: Vector3) -> void:
	if movement_state == EnemyMovementState.TRACK:
		nav_agent.set_target_position(target_pos)


func rotate_enemy_tracking(delta: float) -> void:
	face_object_lerp($EnemyMesh, targeted_player.position, Vector3.UP, delta)
	# zero out X and Z rotations so that the enemy can't rotate in odd ways.
	$EnemyMesh.rotation.x = 0.0;
	$EnemyMesh.rotation.z = 0.0;

# when enemy gets within a set distance to the target (player), switch to guard state.
func _on_navigation_agent_3d_target_reached():
	movement_state = EnemyMovementState.GUARD
	velocity = Vector3.ZERO


func _on_navigation_agent_3d_velocity_computed(safe_velocity):
	# smoother velocity with move_toward, helps with corners, etc
	velocity = velocity.move_toward(safe_velocity, 0.25)
	move_and_slide()


func _on_guard_timer_timeout():
	if targeted_player != null:
		# if the player gets too far away, resume tracking
		var to_player: Vector3 = targeted_player.global_position - $EnemyMesh.global_position
		if (to_player.length_squared() > 12.0):
			movement_state = EnemyMovementState.TRACK


func _on_overlap_area_body_entered(body):
	if body is Player:
		if nearby_players.is_empty():
			nearby_players.push_back(body)
			targeted_player = body
		else:
			nearby_players.push_back(body)


func _on_overlap_area_body_exited(body):
	if body is Player:
		nearby_players.erase(body)
		
		if nearby_players.is_empty():
			targeted_player = null


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
	var v_z: Vector3 = -target.normalized()
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

