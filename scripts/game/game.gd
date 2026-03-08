extends Node

func _ready() -> void:
	# Fetch system data immediately after login
	NetworkManager.send_command("get_system", {}, func(content):
		StateManager.update_system(content)
	)
	NetworkManager.send_command("get_nearby", {}, func(content):
		StateManager.update_nearby(content)
	)
