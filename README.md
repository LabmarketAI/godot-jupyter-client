# godot-jupyter-client

A Godot 4 addon that subscribes to a running
[`jupyter_pubsub`](https://github.com/LabmarketAI/qiskit-aer-container)
server and streams live Jupyter notebook cell outputs into your game or
visualisation.

---

## Installation

1. Copy the `addons/jupyter_client/` folder into your Godot project's
   `addons/` directory.
2. Open **Project → Project Settings → Plugins** and enable
   **JupyterPubSubClient**.

The plugin registers a global `JupyterPubSubClient` autoload singleton that
is immediately available from any script.

---

## Quick start

```gdscript
extends Node

func _ready() -> void:
    JupyterPubSubClient.host = "localhost"
    JupyterPubSubClient.port = 8888

    # Discover active cells
    JupyterPubSubClient.cells_discovered.connect(_on_cells_discovered)
    JupyterPubSubClient.list_cells()

    # Subscribe to a tagged cell
    JupyterPubSubClient.message_received.connect(_on_message)
    JupyterPubSubClient.subscribe("nx-graph")


func _on_cells_discovered(cells: Array) -> void:
    for cell in cells:
        print("Active cell: ", cell)


func _on_message(envelope: Dictionary) -> void:
    print("Cell output from [%s]: " % envelope["cell_name"], envelope["data"])
```

---

## API

### Properties

| Property | Type   | Default       | Description                        |
|----------|--------|---------------|------------------------------------|
| `host`   | String | `"localhost"` | Jupyter server hostname (no scheme)|
| `port`   | int    | `8888`        | Jupyter server port                |

### Methods

| Method                    | Description                                                   |
|---------------------------|---------------------------------------------------------------|
| `list_cells()`            | `GET /pubsub/cells` — results emitted via `cells_discovered`  |
| `subscribe(cell_name)`    | Open a WebSocket to `/pubsub/ws/<cell_name>` (auto-reconnects)|
| `unsubscribe(cell_name)`  | Close the WebSocket for that cell                             |
| `unsubscribe_all()`       | Close all active subscriptions                                |

### Signals

| Signal                          | Description                                    |
|---------------------------------|------------------------------------------------|
| `cells_discovered(cells)`       | Array of cell info Dicts from the server       |
| `message_received(envelope)`    | Fired for every complete message from any cell |
| `cell_subscribed(cell_name)`    | WebSocket handshake succeeded                  |
| `cell_unsubscribed(cell_name)`  | WebSocket closed                               |
| `error_occurred(message)`       | HTTP or WebSocket error string                 |

### Message envelope

Each `message_received` emission delivers a Dictionary with these keys
(matching the `jupyter_pubsub` server protocol):

```
{
  "cell_name":    "nx-graph",
  "kernel_id":   "abc-123",
  "msg_id":      "7f3a...",
  "msg_type":    "stream",
  "chunk_id":    1,
  "total_chunks": 1,
  "data":        "...",
  "metadata":    {}
}
```

Multi-chunk messages are reassembled transparently before the signal fires;
your callback always receives a single complete envelope.

---

## Server setup

See the
[qiskit-aer-container README](https://github.com/LabmarketAI/qiskit-aer-container)
for instructions on running the `jupyter_pubsub` server extension locally or
via Docker.

Tag a cell for publishing by adding a `# pubsub: <name>` comment:

```python
# pubsub: nx-graph
import networkx as nx, json
G = nx.karate_club_graph()
print(json.dumps(nx.node_link_data(G, edges="links")))
```

---

## Addon file structure

```
addons/
  jupyter_client/
    plugin.cfg                   ← Godot plugin manifest
    plugin.gd                    ← EditorPlugin (registers autoload)
    jupyter_pubsub_client.gd     ← Autoload singleton (Node)
    jupyter_cell_subscription.gd ← Per-cell WebSocket manager (Node)
```