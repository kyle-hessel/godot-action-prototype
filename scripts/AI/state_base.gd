extends Node

class_name StateBase

#region error handling for exports used in Callable initialization.
# NOTE: exports will trigger *after* _init in inherited classes: see https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_notifications.html#init-vs-initialization-vs-export
@export var trans_rule_data: Array = []:
	set(_trd):
		if not _trd[0] is NodePath:
			print("Error: " + str(Error.ERR_INVALID_PARAMETER) + ". Array pos 0 is not of type NodePath.")
			get_tree().quit(Error.ERR_INVALID_PARAMETER)
		if not _trd[1] is StringName:
			print("Error: " + str(Error.ERR_INVALID_PARAMETER) + ". Array pos 1 is not of type StringName.")
			get_tree().quit(Error.ERR_INVALID_PARAMETER)
		trans_rule_data = _trd

@export var trans_data: Array = []:
	set(_td):
		if not _td[0] is NodePath:
			print("Error: " + str(Error.ERR_INVALID_PARAMETER) + ". Array pos 0 is not of type NodePath.")
			return
		if not _td[1] is StringName:
			print("Error: " + str(Error.ERR_INVALID_PARAMETER) + ". Array pos 1 is not of type StringName.")
			return
		trans_data = _td
#endregion

var trans_rule: Callable
var trans: Callable
var trans_rule_result: bool

# represents the currently active State (anything derived from StateBase).
var pos: int = 0
var new_pos: int = 0

signal state_complete

func consider_transition() -> void:
	# call the transition rule Callable and store its result.
	print("trans rule is called.")
	trans_rule_result = trans_rule.call()
	
	# if the transition rule returned true, run the transition itself, which is the end of this state and handoff to the next state.
	if trans_rule_result == true:
		# transitions should always return an int to indicate which State or StateAction to initiate next.
		# this opens the door for modifiers to state_action execution order, too.
		# we use new_pos instead of pos to let the child override determine if it will use this value or not.
		print("trans is called.")
		pos = trans.call()
		emit_signal("state_complete")
	# if the transition rule returned false, loop the current state over again.
	# NOTE: If a transition is always guaranteed to return false, this creates an endless loop.
	else:
		pos = 0
		execute_state_context()

# sample transition rule test. always returns true to advance to trans_test, which halts execution.
func _trans_rule_test() -> bool:
	print("Transition rule!")
	return true

# NOTE: Might want to add separate transition args that can optionally be passed in on initialization after the transition Callable itself.
# sample transition test. always returns 0 to reset to default state.
func _trans_test() -> int:
	print("Transition!")
	return -1

# a function meant to be overriden by State and StateMachine.
func execute_state_context() -> void:
	pass
