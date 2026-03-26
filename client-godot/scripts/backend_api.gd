extends Node
class_name BackendApi

@export var base_url: String = "http://127.0.0.1:8080/v1"
@export var access_token: String = ""
@export var request_timeout_sec: float = 8.0

func get_session_state(run_id: String) -> Dictionary:
	return await _request_json(HTTPClient.METHOD_GET, "/runs/%s/session-state" % run_id)

func host_migration_claim(run_id: String) -> Dictionary:
	return await _request_json(HTTPClient.METHOD_POST, "/runs/%s/host-migration/claim" % run_id, {})

func host_migration_confirm(run_id: String, claim_token: String) -> Dictionary:
	return await _request_json(
		HTTPClient.METHOD_POST,
		"/runs/%s/host-migration/confirm" % run_id,
		{"claimToken": claim_token}
	)

func _request_json(method: int, path: String, body: Dictionary = {}) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = request_timeout_sec
	add_child(http)

	var headers := PackedStringArray(["Content-Type: application/json"])
	if not access_token.strip_edges().is_empty():
		headers.append("Authorization: Bearer %s" % access_token.strip_edges())

	var payload := ""
	if method != HTTPClient.METHOD_GET and not body.is_empty():
		payload = JSON.stringify(body)

	var err := http.request(_join_url(path), headers, method, payload)
	if err != OK:
		http.queue_free()
		return {
			"ok": false,
			"status": 0,
			"code": "HTTP_REQUEST_FAILED",
			"error": "request start failed: %s" % err
		}

	var completed: Array = await http.request_completed
	http.queue_free()

	var request_result: int = completed[0]
	var status_code: int = completed[1]
	var response_body: PackedByteArray = completed[3]
	var raw_text := response_body.get_string_from_utf8()

	var parsed: Variant = {}
	if not raw_text.is_empty():
		var json_parsed := JSON.parse_string(raw_text)
		if json_parsed != null:
			parsed = json_parsed

	var api_code := ""
	if parsed is Dictionary and parsed.has("code"):
		api_code = str(parsed["code"])

	return {
		"ok": request_result == HTTPRequest.RESULT_SUCCESS and status_code >= 200 and status_code < 300,
		"status": status_code,
		"code": api_code,
		"data": parsed,
		"request_result": request_result,
		"raw": raw_text
	}

func _join_url(path: String) -> String:
	var root := base_url.strip_edges()
	if root.ends_with("/"):
		root = root.substr(0, root.length() - 1)
	var suffix := path
	if not suffix.begins_with("/"):
		suffix = "/" + suffix
	return root + suffix
