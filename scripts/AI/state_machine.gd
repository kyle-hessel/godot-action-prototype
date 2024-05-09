extends StateBase

class_name StateMachine

# NOTE: exports will trigger *after* _init: see https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_notifications.html#init-vs-initialization-vs-export
@export var states: Array[State] = []:
	set(_s):
		states = _s
		# TODO: Consider adding runtime checks in the event that States are generated and added during runtime at arbitrary points.
		# Not sure what these would look like. It may make sense to pass in an array of Callables to init for this as one more
		# optional parameter, and each can be checked before assigning the variable to assume it makes sense to add the State.
		# e.g. Don't add a new State to the enemy if they are dead. Simple! With good transition writing though,
		# this may be entirely unnecessary. 

var current_state: State
var del_on_end: bool = false

# If the StateMachine's variables are not initialized with exports, then they will be initialized in init() instead, such as when being created at runtime.
func _init(_states: Array[State], _trans_rule: Callable = _trans_rule_test, _trans: Callable = _trans_test, _del: bool = false) -> void:
	print("state machine init!")
	states = _states
	trans_rule = _trans_rule
	trans = _trans
	del_on_end = _del
	# add all StateActions as child nodes of this State node. this ensures their own code, including possible ticking, can run.
	for state: State in states:
		add_child(state)

func _ready() -> void:
	if !trans_rule_data.is_empty():
		trans_rule = Callable(get_node(trans_rule_data[0]), trans_rule_data[1])
	if !trans_data.is_empty():
		trans = Callable(get_node(trans_data[0]), trans_data[1])
	
	print("state machine calls state.")
	# call the first action in line to begin the execution chain.
	execute_state_context()

# NOTE: StateMachine's execute_state_context executes a state.
func execute_state_context() -> void:
	current_state = states[pos]
	if !current_state.is_connected("state_complete", switch_state):
		current_state.state_complete.connect(switch_state, CONNECT_ONE_SHOT)
	current_state.execute_state_context()

func switch_state() -> void:
	pos = current_state.pos
	
	# if the State's pos is -1, halt execution. if del_on_end was marked as true, delete StateMachine entirely.
	if pos == -1:
		if del_on_end:
			queue_free()
		# otherwise, wait.
		else:
			pass
	else:
		execute_state_context()

# TODO: Rewrite. Should only be triggered if the StateMachine has a parent StateMachine in get_parent,
# meaning that it is a state itself.
func consider_transition() -> void:
	super()
