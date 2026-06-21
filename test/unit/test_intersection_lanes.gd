extends "res://addons/gut/test.gd"

const RoadUtils = preload("res://test/unit/road_utils.gd")

var road_util: RoadUtils


func before_each():
	road_util = RoadUtils.new()
	road_util.gut = gut


func _make_intersection(container) -> RoadIntersection:
	container.setup_road_container()
	road_util.create_intersection_two_branch(container)
	return container.get_intersections()[0]


func _lanes(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is RoadLane:
			result.append(child)
	return result


func _lanes_for_edge(node: Node, edge_name: String) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is RoadLane and str(child.name).begins_with("RoadLane_%s_" % edge_name):
			result.append(child)
	return result


func _tags(lanes: Array) -> Array:
	var result: Array = []
	for lane in lanes:
		result.append(lane.lane_prior_tag)
	result.sort()
	return result


# ------------------------------------------------------------------------------


func test_generates_one_lane_per_entering_lane():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	# Two default edges (2 forward + 2 reverse each): one enters forward, the
	# other enters reverse, for two entering lanes apiece.
	assert_eq(_lanes(inter).size(), 4, "One lane per entering lane")


func test_entering_lane_tags():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	assert_eq(_tags(_lanes_for_edge(inter, "p1")), ["F0", "F1"], "Forward edge tags")
	assert_eq(_tags(_lanes_for_edge(inter, "p2")), ["R0", "R1"], "Reverse edge tags")


func test_variable_lane_counts():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	# Edge p1 enters the intersection forward; give it three forward lanes.
	var p1: RoadPoint = container.get_node("p1")
	p1.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD,
	]

	container.rebuild_segments(true)

	assert_eq(_lanes_for_edge(inter, "p1").size(), 3, "Three entering forward lanes")
	assert_eq(_lanes_for_edge(inter, "p2").size(), 2, "Two entering reverse lanes")


func test_no_lanes_when_generation_disabled():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = false
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	assert_eq(_lanes(inter).size(), 0, "No lanes when generation disabled")


func test_rebuild_does_not_duplicate_lanes():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)
	container.rebuild_segments(true)

	assert_eq(_lanes(inter).size(), 4, "Lanes reused, not duplicated, on rebuild")


func test_lanes_added_to_ai_group():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.ai_lane_group = "test_ai_lanes"
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lanes := _lanes(inter)
	assert_eq(lanes.size(), 4, "All entering lanes generated")
	for lane in lanes:
		assert_true(lane.is_in_group("test_ai_lanes"), "Lane is in the AI lane group")


func test_lanes_have_curve_points():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	for lane in _lanes(inter):
		assert_eq(lane.curve.point_count, 2, "Lane has start and end points")
