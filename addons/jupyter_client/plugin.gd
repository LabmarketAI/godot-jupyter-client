@tool
extends EditorPlugin


func _enter_tree() -> void:
	add_autoload_singleton("JupyterPubSubClient", "res://addons/jupyter_client/jupyter_pubsub_client.gd")


func _exit_tree() -> void:
	remove_autoload_singleton("JupyterPubSubClient")
