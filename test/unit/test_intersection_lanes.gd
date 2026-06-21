extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")

var road_util: RoadUtils


func before_each():
	road_util = RoadUtils.new()
	road_util.gut = gut


func _count_lanes(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is RoadLane:
			count += 1
	return count


# ------------------------------------------------------------------------------


func test_generates_one_lane_per_edge():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	container.generate_ai_lanes = true
	road_util.create_intersection_two_branch(container)

	container.rebuild_segments(true)

	var inter: RoadIntersection = container.get_intersections()[0]
	assert_eq(_count_lanes(inter), 2, "One RoadLane generated per edge")


func test_no_lanes_when_generation_disabled():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	container.generate_ai_lanes = false
	road_util.create_intersection_two_branch(container)

	container.rebuild_segments(true)

	var inter: RoadIntersection = container.get_intersections()[0]
	assert_eq(_count_lanes(inter), 0, "No lanes when generation disabled")


func test_rebuild_does_not_duplicate_lanes():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	container.generate_ai_lanes = true
	road_util.create_intersection_two_branch(container)

	container.rebuild_segments(true)
	container.rebuild_segments(true)

	var inter: RoadIntersection = container.get_intersections()[0]
	assert_eq(_count_lanes(inter), 2, "Lanes reused, not duplicated, on rebuild")


func test_lanes_added_to_ai_group():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	container.generate_ai_lanes = true
	container.ai_lane_group = "test_ai_lanes"
	road_util.create_intersection_two_branch(container)

	container.rebuild_segments(true)

	var inter: RoadIntersection = container.get_intersections()[0]
	var checked := 0
	for child in inter.get_children():
		if child is RoadLane:
			checked += 1
			assert_true(child.is_in_group("test_ai_lanes"), "Lane is in the AI lane group")
	assert_eq(checked, 2, "Both lanes checked for group membership")


func test_lanes_have_curve_points():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.setup_road_container()
	container.generate_ai_lanes = true
	road_util.create_intersection_two_branch(container)

	container.rebuild_segments(true)

	var inter: RoadIntersection = container.get_intersections()[0]
	for child in inter.get_children():
		if child is RoadLane:
			assert_eq(child.curve.point_count, 2, "Stub lane has start and end points")
