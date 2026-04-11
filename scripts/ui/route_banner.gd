extends PanelContainer

## Top-of-screen banner that shows auto-travel progress with an abort button.
## Managed by the galaxy map; shown during active route execution.

@onready var progress_label: Label = %RouteProgressLabel
@onready var abort_button: Button = %RouteAbortButton

signal abort_requested


func _ready() -> void:
	abort_button.pressed.connect(func(): abort_requested.emit())


func update_progress(current: int, total: int, system_name: String) -> void:
	progress_label.text = "Auto-travel: %s (%d/%d)" % [system_name, current, total]


func show_route(total_jumps: int) -> void:
	progress_label.text = "Starting route (%d jumps)..." % total_jumps
	show()


func hide_route() -> void:
	hide()
