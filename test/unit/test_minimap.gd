extends GdUnitTestSuite

# Label placement on the minimap: names that would print over each other are dropped.

const Minimap := preload("res://scripts/ui/minimap.gd")


func test_label_fits_when_nothing_is_taken() -> void:
	var taken: Array[Rect2] = []
	assert_bool(Minimap.label_fits(Rect2(0, 0, 40, 10), taken)).is_true()


func test_label_rejected_when_it_overlaps_a_placed_label() -> void:
	var taken: Array[Rect2] = [Rect2(0, 0, 40, 10)]
	assert_bool(Minimap.label_fits(Rect2(30, 5, 40, 10), taken)).is_false()
	assert_bool(Minimap.label_fits(Rect2(0, 12, 40, 10), taken)).is_true()
