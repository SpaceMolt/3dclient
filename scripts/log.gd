class_name Log
extends RefCounted

## Static developer logging utility.
## Use Log.d(), Log.i(), Log.w(), Log.e() for colored, class-aware console output.
## All messages are also written to spacemolt.log.

enum Level { DEBUG, INFO, WARNING, ERROR }

const LOG_FILE_NAME := "spacemolt.log"

# Deduplication: skip consecutive identical messages (compared without timestamp)
static var _last_formatted: String = ""

# File logging
static var _log_file: FileAccess = null
static var _log_path: String = ""
static var _initialized: bool = false


static func d(msg: String) -> void:
	if OS.is_debug_build():
		_log(Level.DEBUG, msg)


static func i(msg: String) -> void:
	_log(Level.INFO, msg)


static func w(msg: String) -> void:
	_log(Level.WARNING, msg)


static func e(msg: String) -> void:
	_log(Level.ERROR, msg)


static func get_log_path() -> String:
	_ensure_initialized()
	if _log_path.begins_with("user://"):
		return ProjectSettings.globalize_path(_log_path)
	return _log_path


static func _log(level: Level, msg: String) -> void:
	_ensure_initialized()

	var classname := _get_caller_class()
	var prefix := _level_prefix(level)
	var color := _level_color(level)

	# Build content string for dedup (no timestamp — timestamps change every second)
	var tag: String
	if classname.is_empty():
		tag = prefix
	else:
		tag = "%s [%s]" % [prefix, classname]
	var formatted := "%s %s" % [tag, msg]

	# Deduplicate consecutive identical messages
	if formatted == _last_formatted:
		return
	_last_formatted = formatted

	var timestamp := Time.get_datetime_string_from_system()

	# Console output (colored via print_rich, plain on web)
	var is_web := OS.has_feature("web")
	if is_web:
		print("[%s] %s" % [timestamp, formatted])
	else:
		print_rich(
			"[color=%s][b][%s] %s[/b][/color] %s" % [color, timestamp, tag, msg]
		)

	# File output (plain text, always)
	if _log_file:
		_log_file.store_string("[%s] %s\n" % [timestamp, formatted])
		_log_file.flush()

	# Stack trace for errors
	if level == Level.ERROR:
		_print_stack_trace(is_web)


static func _print_stack_trace(is_web: bool) -> void:
	var stack := get_stack()
	for frame: Dictionary in stack:
		var source: String = frame.get("source", "")
		if source.is_empty() or source.ends_with("log.gd"):
			continue
		var stack_line := "  at %s:%s in %s" % [
			source, frame.get("line", "?"), frame.get("function", "?")
		]
		if is_web:
			print(stack_line)
		else:
			print_rich("[color=#6b8fa3]%s[/color]" % stack_line)
		if _log_file:
			_log_file.store_string("%s\n" % stack_line)
			_log_file.flush()


static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_log_path = _resolve_log_path()
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log_file:
		_log_file.store_string(
			"=== SpaceMolt Log Started %s ===\n" % Time.get_datetime_string_from_system()
		)


static func _resolve_log_path() -> String:
	if not OS.has_feature("editor"):
		var exe_dir := OS.get_executable_path().get_base_dir()
		if not exe_dir.is_empty():
			return exe_dir.path_join(LOG_FILE_NAME)
	return "user://" + LOG_FILE_NAME


static func _level_prefix(level: Level) -> String:
	match level:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARNING:
			return "WARN"
		Level.ERROR:
			return "ERROR"
	return "?"


static func _level_color(level: Level) -> String:
	match level:
		Level.DEBUG:
			return "#6b8fa3"   # ThemeColors.HULL_GREY
		Level.INFO:
			return "#00d4ff"   # ThemeColors.PLASMA_CYAN
		Level.WARNING:
			return "#ffd93d"   # ThemeColors.WARNING_YELLOW
		Level.ERROR:
			return "#e63946"   # ThemeColors.CLAW_RED
	return "#a8c5d6"


static func _get_caller_class() -> String:
	var stack := get_stack()
	# Walk past Log's own frames to find the actual caller
	for frame: Dictionary in stack:
		var source: String = frame.get("source", "")
		if source.is_empty() or source.ends_with("log.gd"):
			continue
		return _extract_class_name(source)
	return ""


static func _extract_class_name(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return path.get_file().get_basename()

	for _i in range(10):
		if file.eof_reached():
			break
		var line := file.get_line().strip_edges()
		if line.begins_with("class_name"):
			var parts := line.split(" ")
			if parts.size() >= 2:
				file.close()
				return parts[1]

	file.close()
	return path.get_file().get_basename()
