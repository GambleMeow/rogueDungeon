extends Node
class_name LobbyFlowController

signal lobby_state_changed(next_state: String)
signal lobby_event(message: String)

@export var return_to_lobby_delay_sec: float = 1.2

var _state: String = "idle"
var _run_id: String = ""
var _last_reason: String = ""
var _returning: bool = false

func enter_match(run_id: String) -> void:
	_run_id = run_id.strip_edges()
	_last_reason = ""
	_returning = false
	_set_state("in_match")
	emit_signal("lobby_event", "entered match run=%s" % _run_id)

func begin_return_to_lobby(reason_code: String) -> void:
	var reason := reason_code.strip_edges()
	if reason.is_empty():
		reason = "UNKNOWN_REASON"
	_last_reason = reason
	if _returning:
		return
	_returning = true
	_set_state("returning_to_lobby")
	emit_signal("lobby_event", "returning to lobby reason=%s" % _last_reason)
	call_deferred("_complete_return_to_lobby")

func reset_to_idle() -> void:
	_returning = false
	_last_reason = ""
	_run_id = ""
	_set_state("idle")

func get_state() -> String:
	return _state

func get_last_reason() -> String:
	return _last_reason

func _complete_return_to_lobby() -> void:
	await get_tree().create_timer(max(return_to_lobby_delay_sec, 0.01)).timeout
	_returning = false
	_set_state("in_lobby")
	emit_signal("lobby_event", "arrived lobby reason=%s" % _last_reason)

func _set_state(next_state: String) -> void:
	if _state == next_state:
		return
	_state = next_state
	emit_signal("lobby_state_changed", _state)
