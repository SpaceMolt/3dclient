extends GdUnitTestSuite

# Unit tests for the Log static utility class.


func before_test() -> void:
	# Reset dedup state between tests
	Log._last_formatted = ""


func test_level_prefix_debug() -> void:
	assert_str(Log._level_prefix(Log.Level.DEBUG)).is_equal("DEBUG")


func test_level_prefix_info() -> void:
	assert_str(Log._level_prefix(Log.Level.INFO)).is_equal("INFO")


func test_level_prefix_warning() -> void:
	assert_str(Log._level_prefix(Log.Level.WARNING)).is_equal("WARN")


func test_level_prefix_error() -> void:
	assert_str(Log._level_prefix(Log.Level.ERROR)).is_equal("ERROR")


func test_level_color_debug_is_hull_grey() -> void:
	assert_str(Log._level_color(Log.Level.DEBUG)).is_equal("#6b8fa3")


func test_level_color_info_is_plasma_cyan() -> void:
	assert_str(Log._level_color(Log.Level.INFO)).is_equal("#00d4ff")


func test_level_color_warning_is_yellow() -> void:
	assert_str(Log._level_color(Log.Level.WARNING)).is_equal("#ffd93d")


func test_level_color_error_is_red() -> void:
	assert_str(Log._level_color(Log.Level.ERROR)).is_equal("#e63946")


func test_info_does_not_crash() -> void:
	Log.i("test info message")
	assert_str(Log._last_formatted).contains("test info message")


func test_warning_does_not_crash() -> void:
	Log.w("test warning message")
	assert_str(Log._last_formatted).contains("test warning message")


func test_error_does_not_crash() -> void:
	Log.e("test error message")
	assert_str(Log._last_formatted).contains("test error message")


func test_debug_does_not_crash() -> void:
	Log.d("test debug message")
	# In debug builds this sets _last_formatted; in release it's a no-op
	if OS.is_debug_build():
		assert_str(Log._last_formatted).contains("test debug message")


func test_dedup_suppresses_consecutive_identical() -> void:
	Log.i("duplicate message")
	var first := Log._last_formatted
	assert_str(first).is_not_empty()
	# Second identical call should be suppressed (last_formatted unchanged)
	Log.i("duplicate message")
	assert_str(Log._last_formatted).is_equal(first)


func test_different_messages_not_deduplicated() -> void:
	Log.i("message one")
	var first := Log._last_formatted
	Log.i("message two")
	assert_str(Log._last_formatted).is_not_equal(first)


func test_get_log_path_is_not_empty() -> void:
	assert_str(Log.get_log_path()).is_not_empty()


func test_extract_class_name_from_this_file() -> void:
	# This test file has no class_name, so should return the filename
	var result := Log._extract_class_name("res://test/unit/test_log.gd")
	assert_str(result).is_equal("test_log")


func test_extract_class_name_from_known_class() -> void:
	# ThemeColors has class_name ThemeColors
	var result := Log._extract_class_name("res://scripts/theme_colors.gd")
	assert_str(result).is_equal("ThemeColors")
