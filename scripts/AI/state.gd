extends StateBase

class_name State

# NOTE: exports will trigger *after* _init: see https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_notifications.html#init-vs-initialization-vs-export
@export var state_type: int = 0 # pass in enums to this
@export var state_actions: Array[StateAction]

# If the State's variables are not initialized with exports, then they will be initialized in init() instead, such as when being created at runtime.
func _init(_type: int = 0, _actions: Array[StateAction] = [], _trans_rule: Callable = _trans_rule_test, _trans: Callable = _trans_test) -> void:
	state_type = _type # this is for classification used in the owning StateGraph.
	state_actions = _actions
	trans_rule = _trans_rule
	trans = _trans
	# add all StateActions as child nodes of this State node. this ensures their own code, including possible ticking, can run.
	for action: StateAction in state_actions:
		add_child(action)

func _ready() -> void:
	super()
	
	#execute_state_context() # NOTE: Debug only.

# called from StateMachine's execute_state function.
# NOTE: State's execute_state_context executes an action.
func execute_state_context() -> void:
	# set up a callback for the given action's action_complete signal to handle the action ending.
	if !state_actions[pos].action_complete.is_connected(consider_transition):
		state_actions[pos].action_complete.connect(consider_transition, CONNECT_ONE_SHOT)
	print("state executes action.")
	state_actions[pos].execute_action()

func consider_transition() -> void:
	print("action completes - state considers transition.")
	# set tick to false every time to either turn it off on a ticking action or, basically do nothing on anything else.
	state_actions[pos].tick = false
	# increment pos so that the next action is called next time execute_state_context runs.
	pos += 1
	#print("position is incremented.")
	
	# once all actions are complete, determine if a transition is in order by calling the super of this function.
	if pos >= state_actions.size():
		super()
	# otherwise, run call_action again to trigger the next action.
	else:
		execute_state_context()

func realign_pos() -> void:
	pos = ReservedTransitions.FIRST
