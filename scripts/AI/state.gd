extends Node

class_name State

var state_type: int = 0 # pass in enums to this
var state_actions: Array[StateAction]
var state_tickable_actions: Array[StateAction]
var trans_rule: Callable
var trans: Callable
var pos: int = 0

signal consider_trans
signal actions_complete

func _init(_type: int, _actions: Array[StateAction], _trans_rule: Callable = _trans_rule_test, _trans: Callable = _trans_test) -> void:
	state_type = _type # this is for classification used in the owning StateGraph.
	state_actions = _actions
	trans_rule = _trans_rule
	trans = _trans
	for action: StateAction in state_actions:
		add_child(action)

func _ready() -> void:
	# call the first action in line to begin the execution chain.
	call_action()

func call_action() -> void:
	# set up a lambda callback for the given action's action_complete signal to handle the action ending.
	state_actions[pos].action_complete.connect(determine_next_action, CONNECT_ONE_SHOT)
	
	state_actions[pos].execute_action()

func determine_next_action() -> void:
	# set tick to false every time to either turn it off on a ticking action or, basically do nothing on anything else.
	state_actions[pos].tick = false
	# increment pos so that the next action is executed below when this lambda function calls call_action again.
	pos += 1
	
	# once all actions are complete, determine if a transition is in order.
	if pos >= state_actions.size():
		consider_transition()
	# otherwise, run call_action again to trigger the next action.
	else:
		call_action()

func consider_transition() -> void:
	var trans_rule_result: bool = trans_rule.call()
	
	# if the transition rule returned true, run the transition itself, which is the end of this state and handoff to the next state.
	if trans_rule_result == true:
		trans.call()
	# if the transition rule returned false, loop the current state over again.
	else:
		pos = 0
		call_action()

# sample transition rule test. always returns true to transition out of the current state.
func _trans_rule_test() -> bool:
	print("Transition rule!")
	return true

# NOTE: Might want to add separate transition args that can optionally be passed in on initialization after the transition Callable itself.
# sample transition test. always queue_frees the node.
func _trans_test() -> void:
	print("Transition!")
	queue_free()
