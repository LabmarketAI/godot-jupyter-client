## JupyterCellSubscription
##
## Manages a single WebSocket connection to ws://<host>:<port>/pubsub/ws/<cell_name>.
## Automatically reconnects after an unexpected disconnect.
##
## Instantiated and owned by JupyterPubSubClient; not intended for direct use.
##
class_name JupyterCellSubscription
extends Node

## Emitted when a complete message envelope has been received and parsed.
signal message_received(envelope: Dictionary)

## Emitted once the WebSocket handshake succeeds.
signal subscribed()

## Emitted when the WebSocket closes (intentional or otherwise).
signal unsubscribed()

## Emitted on connection or parse errors.
signal error_occurred(message: String)

# Seconds between reconnection attempts.
@export var reconnect_delay: float = 3.0

var _host: String = ""
var _port: int = 8888
var _cell_name: String = ""

var _ws: WebSocketPeer = WebSocketPeer.new()
var _ws_url: String = ""

var _connected: bool = false
var _closing: bool = false
var _reconnect_timer: float = 0.0

# Multi-chunk reassembly: msg_id -> { chunks: {chunk_id: data}, total: int }
var _pending_chunks: Dictionary = {}


## Open the WebSocket connection for [param cell_name].
func open(p_host: String, p_port: int, p_cell_name: String) -> void:
	_host = p_host
	_port = p_port
	_cell_name = p_cell_name
	_ws_url = "ws://%s:%d/pubsub/ws/%s" % [_host, _port, _cell_name]
	_connect()


## Close the WebSocket and prevent further reconnection attempts.
func close() -> void:
	_closing = true
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_ws.close()


func _process(delta: float) -> void:
	if _closing:
		return

	var state := _ws.get_ready_state()

	match state:
		WebSocketPeer.STATE_OPEN:
			_ws.poll()
			if not _connected:
				_connected = true
				subscribed.emit()
			_drain_packets()

		WebSocketPeer.STATE_CONNECTING:
			_ws.poll()

		WebSocketPeer.STATE_CLOSING:
			_ws.poll()

		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				unsubscribed.emit()

			_reconnect_timer -= delta
			if _reconnect_timer <= 0.0:
				_connect()


func _connect() -> void:
	_reconnect_timer = reconnect_delay
	_ws = WebSocketPeer.new()
	var err := _ws.connect_to_url(_ws_url)
	if err != OK:
		error_occurred.emit(
			"WebSocket connect_to_url failed (err %d): %s" % [err, _ws_url])


func _drain_packets() -> void:
	while _ws.get_available_packet_count() > 0:
		var raw := _ws.get_packet()

		var json := JSON.new()
		var parse_err := json.parse(raw.get_string_from_utf8())
		if parse_err != OK:
			error_occurred.emit("JSON parse error on incoming packet")
			continue

		var envelope = json.get_data()
		if envelope is not Dictionary:
			error_occurred.emit("Unexpected envelope type: %s" % type_string(typeof(envelope)))
			continue

		_handle_envelope(envelope)


func _handle_envelope(envelope: Dictionary) -> void:
	# Single-chunk (or no chunking) path – emit immediately.
	var total: int = envelope.get("total_chunks", 1)
	if total <= 1:
		message_received.emit(envelope)
		return

	# Multi-chunk reassembly path.
	var msg_id: String = envelope.get("msg_id", "")
	if msg_id.is_empty():
		# No msg_id to correlate; emit as-is.
		message_received.emit(envelope)
		return

	var chunk_id: int = envelope.get("chunk_id", 1)

	if not _pending_chunks.has(msg_id):
		_pending_chunks[msg_id] = {"chunks": {}, "total": total, "base": envelope}
	elif _pending_chunks[msg_id]["total"] != total:
		error_occurred.emit(
			"Chunk total mismatch for msg_id %s (expected %d, got %d)" % [
				msg_id, _pending_chunks[msg_id]["total"], total])
		_pending_chunks.erase(msg_id)
		return

	_pending_chunks[msg_id]["chunks"][chunk_id] = envelope.get("data", "")

	if _pending_chunks[msg_id]["chunks"].size() == total:
		# All chunks received – assemble and emit.
		var assembled_data := ""
		for i in range(1, total + 1):
			assembled_data += _pending_chunks[msg_id]["chunks"].get(i, "")

		var complete: Dictionary = _pending_chunks[msg_id]["base"].duplicate()
		complete["data"] = assembled_data
		complete["chunk_id"] = 1
		complete["total_chunks"] = 1

		_pending_chunks.erase(msg_id)
		message_received.emit(complete)
