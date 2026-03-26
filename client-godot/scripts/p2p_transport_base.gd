extends Node
class_name P2PTransportBase

signal event_emitted(message: String)

func setup(_run_id: String, _local_steam_id: String) -> void:
	pass

func connect_to_host(_target_host_steam_id: String) -> Dictionary:
	return {
		"ok": false,
		"code": "TRANSPORT_NOT_IMPLEMENTED",
	}

func disconnect(_reason_code: String = "MANUAL_STOP") -> void:
	pass

func get_connection_state_text() -> String:
	return "DISCONNECTED"

func get_role() -> String:
	return "none"

func get_host_steam_id() -> String:
	return ""
