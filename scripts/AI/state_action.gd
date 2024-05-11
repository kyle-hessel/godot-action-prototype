extends Node

class_name StateAction

#region error handling for exports used in Callable initialization.
# NOTE: exports will trigger *after* _init: see https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_notifications.html#init-vs-initialization-vs-export
@export var action_data: Array = []:
	set(_ad):
		if not _ad[0] is NodePath:
			print("Error: " + str(Error.ERR_INVALID_PARAMETER) + ". Array pos 0 is not of type NodePath.")
			get_tree().quit(Error.ERR_INVALID_PARAMETER)
		if not _ad[1] is StringName:
			print("Error: " + str(Error.ERR_INVALID_PARAMETER) + ". Array pos 1 is not of type StringName.")
			get_tree().quit(Error.ERR_INVALID_PARAMETER)
		action_data = _ad
#endregion

@export var action_args: Array
@export var tickable: bool = false

var action: Callable
var tick: bool = tickable

signal action_complete

func _init(_action: Callable = Callable(), _args: Array = [], _tick: bool = false) -> void:
	action = _action
	action_args = _args
	tickable = _tick

func _ready() -> void:
	if !action_data.is_empty():
		action = Callable(get_node(action_data[0]), action_data[1])
	
	if tickable:
		# bind an extra reference to this StateAction to its callable, so that the action_complete signal can be emitted from ticking actions.
		# NOTE: This is chosen over a return-type approach as every tickable action Callable would have to return true or false every single frame otherwise.
		# this has a larger up-front cost, but I think it's a better API.
		action = action.bind(self)

func _physics_process(delta: float) -> void:
	if tick:
		# ticking actions are called every physics frame, and emit action_complete internally using the bound reference to self.
		action.call(action_args)

func execute_action() -> void:
	# if the action is tickable, mark tick true so that _physics_process can start calling it every frame. this extra indirection is to keep the API cleaner.
	if tickable:
		tick = true
	# for one-shot actions, just call them and then report back when the action is complete.
	else:
		action.call(action_args)
		emit_signal("action_complete")
