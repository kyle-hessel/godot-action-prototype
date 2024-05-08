extends StateBase

class_name StateMachine

# NOTE: exports will trigger *after* _init: see https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_notifications.html#init-vs-initialization-vs-export
@export var states: Array[State] = []

# If the StateMachine's variables are not initialized with exports, then they will be initialized in init() instead, such as when being created at runtime.
func _init(_states: Array[State], _trans_rule: Callable = _trans_rule_test, _trans: Callable = _trans_test) -> void:
	states = _states
	trans_rule = _trans_rule
	trans = _trans
	# add all StateActions as child nodes of this State node. this ensures their own code, including possible ticking, can run.
	for state: State in states:
		add_child(state)

func _ready() -> void:
	if !trans_rule_data.is_empty():
		trans_rule = Callable(get_node(trans_rule_data[0]), trans_rule_data[1])
	if !trans_data.is_empty():
		trans = Callable(get_node(trans_data[0]), trans_data[1])
	
	# call the first action in line to begin the execution chain.
	execute_state_context()

# NOTE: StateMachine's execute_state_context executes a state.
func execute_state_context() -> void:
	states[pos].state_complete.connect(consider_transition, CONNECT_ONE_SHOT)
	states[pos].execute_state_context()
	print("State machine: after state is ran")

func consider_transition() -> void:
	super()
	
	# TODO: Decide if any overriden functionality is needed on top of the base consider_transition, such as manipulation
	# of pos to determine which state runs next. this may not be necessary; it could be handled in the transition Callable itself.
	# OR, the Callable could return a value, and this function could make sense of it.
