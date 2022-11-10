extends CharacterBody3D


@export var SPEED: float = 5.0
@export var JUMP_VELOCITY: float = 4.5
@export var sensitivity = 2.5

# Get the gravity from the project settings to be synced with RigidBody nodes.
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	# capture mouse movement for camera navigation
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity.y -= gravity * delta

	# Handle Jump.
	if Input.is_action_just_pressed("Jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("Left", "Right", "Forward", "Backward")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
func _input(event):
	# mouse movement inputs
	if (event is InputEventMouseMotion):
		# mouse x movement (in 2d monitor space) becomes player rotation in 3D space around the Y axis.
		rotation.y -= event.relative.x / 1000 * sensitivity
		# mouse y movement (in 2d monitor space) becomes camera's up and down rotation around the X axis.
		#$Camera3D.rotation.x -= event.relative.y / 1000 * sensitivity
		# clamp player's x rotation.
		rotation.x = clamp(rotation.x, PI / -2, PI / 2)
		# clamp camera's x rotation.
		#$Camera3D.rotation.x = clamp($Camera3D.rotation.x, -2, 2)





