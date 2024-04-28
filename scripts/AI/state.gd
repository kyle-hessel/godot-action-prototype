extends Node

class_name State

var state_type: int = 0 # pass in enums to this
var state_actions: Array[StateAction]
var state_tickable_actions: Array[StateAction]
var trans_rule: Callable
var pos: int = 0

signal actions_complete

func _init(_type: int) -> void:
	state_type = _type # this is for classification used in the owning StateGraph.

func _ready() -> void:
	for action: StateAction in get_children():
		state_actions.append(action)
	
	# set the function that the trans_rule Callable will call back to.
	# NOTE: this would probably be a passed in argument from a CharacterBody3D for instance, not a local function.
	trans_rule = _enter_trans_rule_test
	# set the transition rule to fire when all actions are complete, to decide if this state is continued or not.
	actions_complete.connect(trans_rule)
	
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
	
	# once all actions are complete, emit that information so that the StateGraph can continue.
	if pos >= state_actions.size():
		emit_signal("actions_complete")
	# otherwise, run call_action again to trigger the next action.
	else:
		call_action()

# sample transition. might not necessarily live here.
func _enter_trans_rule_test():
	print("Transition!")
