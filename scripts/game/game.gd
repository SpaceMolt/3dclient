extends Node

func _ready() -> void:
	# The login frame carries player/ship/system; get_status seeds cargo, skills,
	# missions, and location. Later changes arrive as action_result deltas.
	NetworkManager.send_command("get_status", {})
	NetworkManager.send_command("get_system", {}, func(content):
		StateManager.update_system(content)
	)
	NetworkManager.send_command("get_nearby", {}, func(content):
		StateManager.update_nearby(content)
	)
	# Load galaxy map (from cache first, then refresh from server)
	if not StateManager.load_cached_map():
		_fetch_galaxy_map()
	else:
		# Refresh in background even if cache exists
		_fetch_galaxy_map()


func _fetch_galaxy_map() -> void:
	NetworkManager.send_command("get_map", {}, func(content: Dictionary):
		if content.has("systems"):
			StateManager.set_galaxy_map(content)
	)
