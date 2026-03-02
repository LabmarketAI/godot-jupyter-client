## JupyterPubSubClient
##
## Autoload singleton that connects to a running jupyter_pubsub server,
## discovers tagged cells via the REST API, and streams live cell output
## through per-cell WebSocket subscriptions.
##
## Usage (from any script):
##   JupyterPubSubClient.host = "localhost"
##   JupyterPubSubClient.port = 8888
##   JupyterPubSubClient.cells_discovered.connect(_on_cells_discovered)
##   JupyterPubSubClient.message_received.connect(_on_message)
##   JupyterPubSubClient.list_cells()
##   JupyterPubSubClient.subscribe("nx-graph")
##
extends Node

## Emitted when the /pubsub/cells REST call completes.
## [param cells] is an Array of Dictionaries as returned by the server.
signal cells_discovered(cells: Array)

## Emitted when any subscribed cell receives a new message envelope.
## [param envelope] keys: cell_name, kernel_id, msg_id, msg_type,
##                        chunk_id, total_chunks, data, metadata
signal message_received(envelope: Dictionary)

## Emitted when a WebSocket subscription is successfully opened.
signal cell_subscribed(cell_name: String)

## Emitted when a WebSocket subscription is closed.
signal cell_unsubscribed(cell_name: String)

## Emitted on HTTP or WebSocket errors.
signal error_occurred(message: String)

## Jupyter server hostname (no scheme).
@export var host: String = "localhost"

## Jupyter server port.
@export var port: int = 8888

# Active subscriptions keyed by cell_name.
var _subscriptions: Dictionary = {}

# Pending HTTP request nodes keyed by their node instance.
var _pending_requests: Dictionary = {}


## Fetch the list of currently active cells from GET /pubsub/cells.
## Results are emitted via [signal cells_discovered].
func list_cells() -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_list_cells_completed.bind(http))
	_pending_requests[http] = true

	var url := "http://%s:%d/pubsub/cells" % [host, port]
	var err := http.request(url)
	if err != OK:
		_cleanup_http(http)
		error_occurred.emit("list_cells: HTTPRequest failed (err %d)" % err)


## Subscribe to live output from [param cell_name].
## Messages are emitted via [signal message_received].
## Calling subscribe() on an already-subscribed cell is a no-op.
func subscribe(cell_name: String) -> void:
	if _subscriptions.has(cell_name):
		return

	var sub: JupyterCellSubscription = JupyterCellSubscription.new()
	sub.name = "sub_%s" % cell_name.replace("-", "_")
	add_child(sub)
	_subscriptions[cell_name] = sub

	sub.message_received.connect(_on_sub_message.bind(cell_name))
	sub.subscribed.connect(_on_sub_connected.bind(cell_name))
	sub.unsubscribed.connect(_on_sub_disconnected.bind(cell_name))
	sub.error_occurred.connect(_on_sub_error.bind(cell_name))

	sub.open(host, port, cell_name)


## Unsubscribe from [param cell_name] and close its WebSocket.
func unsubscribe(cell_name: String) -> void:
	if not _subscriptions.has(cell_name):
		return
	var sub: JupyterCellSubscription = _subscriptions[cell_name]
	sub.close()
	_subscriptions.erase(cell_name)
	sub.queue_free()


## Unsubscribe from all active cell subscriptions.
func unsubscribe_all() -> void:
	for cell_name in _subscriptions.keys():
		unsubscribe(cell_name)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _on_list_cells_completed(
		result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest) -> void:

	_cleanup_http(http)

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		error_occurred.emit(
			"list_cells: HTTP %d (result %d)" % [response_code, result])
		return

	var json := JSON.new()
	var parse_err := json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		error_occurred.emit("list_cells: JSON parse error")
		return

	var parsed = json.get_data()
	var cells: Array = []
	if parsed is Dictionary and parsed.has("cells"):
		cells = parsed["cells"]
	elif parsed is Array:
		cells = parsed

	cells_discovered.emit(cells)


func _cleanup_http(http: HTTPRequest) -> void:
	_pending_requests.erase(http)
	http.queue_free()


func _on_sub_message(envelope: Dictionary, cell_name: String) -> void:
	message_received.emit(envelope)


func _on_sub_connected(cell_name: String) -> void:
	cell_subscribed.emit(cell_name)


func _on_sub_disconnected(cell_name: String) -> void:
	# Keep the subscription in _subscriptions so the auto-reconnect cycle
	# continues to be tracked.  Explicit cleanup happens in unsubscribe().
	cell_unsubscribed.emit(cell_name)


func _on_sub_error(message: String, cell_name: String) -> void:
	error_occurred.emit("[%s] %s" % [cell_name, message])
