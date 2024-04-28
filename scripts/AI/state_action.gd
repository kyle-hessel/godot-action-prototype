extends Node

class_name StateAction

var action: Callable
var action_args: Array
var tickable: bool = false
var tick: bool = tickable

signal action_complete

func _init(_action: Callable, _args: Array = [], _tick: bool = false) -> void:
	action = _action
	action_args = _args
	tickable = _tick

func _ready() -> void:
	if tickable:
		action = action.bind(self) # bind an extra reference to this StateAction to its callable, so that the action_complete signal can be emitted from ticking actions.

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
		#print(action.get_method())
		#print(action.is_valid())
		emit_signal("action_complete")
