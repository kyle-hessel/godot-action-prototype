extends StateBase

class_name StateMachine

var old_pos: int

# NOTE: exports will trigger *after* _init: see https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_notifications.html#init-vs-initialization-vs-export
@export var states: Array[StateBase] = []:
	set(_s):
		states = _s
		# TODO: Consider adding runtime checks in the event that States are generated and added during runtime at arbitrary points.
		# Not sure what these would look like. It may make sense to pass in an array of Callables to init for this as one more
		# optional parameter, and each can be checked before assigning the variable to assume it makes sense to add the State.
		# e.g. Don't add a new State to the enemy if they are dead. Simple! With good transition writing though,
		# this may be entirely unnecessary. 

var current_state: StateBase
var del_on_end: bool = false

# If the StateMachine's variables are not initialized with exports, then they will be initialized in init() instead, such as when being created at runtime.
func _init(_states: Array[StateBase], _trans_rule: Callable = _trans_rule_test, _trans: Callable = _trans_test, _del: bool = false) -> void:
	states = _states
	trans_rule = _trans_rule
	trans = _trans
	del_on_end = _del
	# add all StateActions as child nodes of this State node. this ensures their own code, including possible ticking, can run.
	for state: StateBase in states:
		add_child(state)

func _ready() -> void:
	if !trans_rule_data.is_empty():
		trans_rule = Callable(get_node(trans_rule_data[0]), trans_rule_data[1])
	if !trans_data.is_empty():
		trans = Callable(get_node(trans_data[0]), trans_data[1])
	
	# call the first action in line to begin the execution chain on the root StateMachine.
	# if this is a child StateMachine, let it stay dormant for the time being.
	if not get_parent() is StateMachine:
		print("state machine calls state.")
		execute_state_context()

# NOTE: StateMachine's execute_state_context executes a state.
func execute_state_context() -> void:
	current_state = states[pos]
	if !current_state.is_connected("state_complete", switch_state):
		current_state.state_complete.connect(switch_state, CONNECT_ONE_SHOT)
	current_state.execute_state_context()

func switch_state() -> void:
	old_pos = pos # cache the old pos in the event that a StateAction tries to exit out of this State Machine and fails (see below in elif pos>99).
	pos = current_state.pos
	
	# if the State's pos is -1, halt execution. if del_on_end was marked as true, delete the StateMachine entirely.
	if pos == ReservedTransitions.STOP:
		# TODO: If this StateMachine is a child in a larger HSM, gracefully have it transition out of itself *before* it gets deleted, OR delete the rest of the HSM, too.
		if del_on_end:
			queue_free()
		# otherwise, wait.
		else:
			pass
	# if pos is -2, trigger StateMachine's consider_transition.
	elif pos == ReservedTransitions.BREAKOUT:
		if get_parent() is StateMachine:
			consider_transition()
		# for now, just halt StateMachine execution if there's no parent StateMachine, as this is unintended behavior.
		else:
			print("Error! This StateMachine is the root of the HSM, it cannot be exited.")
	# otherwise, continue with the next State.
	else:
		execute_state_context()

func consider_transition() -> void:
	super()
	
#func realign_pos() -> void:
	#pass
