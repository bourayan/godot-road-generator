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

	# p1 connects on its next side, so the lanes travelling toward the
	# intersection (and through it) are its reverse lanes; p2 the forward ones.
	assert_eq(_tags(_lanes_for_edge(inter, "p1")), ["R0", "R1"], "Entering edge tags")
	assert_eq(_tags(_lanes_for_edge(inter, "p2")), ["F0", "F1"], "Entering edge tags")


func test_variable_lane_counts():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	# Edge p1 enters the intersection on its reverse lanes; give it three.
	var p1: RoadPoint = container.get_node("p1")
	p1.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
	]

	container.rebuild_segments(true)

	assert_eq(_lanes_for_edge(inter, "p1").size(), 3, "Three entering reverse lanes")
	assert_eq(_lanes_for_edge(inter, "p2").size(), 2, "Two entering forward lanes")


func test_lane_visibility_follows_container():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	container.rebuild_segments(true)

	container.draw_lanes_editor = true
	container.draw_lanes_game = false
	for lane in _lanes(inter):
		assert_true(lane.draw_in_editor, "Editor draw follows container")
		assert_false(lane.draw_in_game, "Game draw follows container")

	container.draw_lanes_editor = false
	container.draw_lanes_game = true
	for lane in _lanes(inter):
		assert_false(lane.draw_in_editor, "Editor draw toggles off with container")
		assert_true(lane.draw_in_game, "Game draw toggles on with container")


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

	# RoadPoint, stop line, opposite stop line, opposite RoadPoint.
	for lane in _lanes(inter):
		assert_eq(lane.curve.point_count, 4, "Lane runs RoadPoint to RoadPoint via its stop lines")


func test_straight_through_lane_crosses_intersection():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("RoadLane_p1_R0")
	var lane_start := lane.get_lane_start()
	var lane_end := lane.get_lane_end()
	assert_almost_eq(lane_start.x, lane_end.x, 0.01, "Through lane keeps a constant offset")
	assert_true(lane_start.z < 0.0 and lane_end.z > 0.0, "Through lane spans both edges")


func test_through_lane_reaches_road_points():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("RoadLane_p1_R0")
	var p1: RoadPoint = container.get_node("p1")
	var p2: RoadPoint = container.get_node("p2")
	assert_almost_eq(lane.get_lane_start().z, p1.global_transform.origin.z, 0.01,
			"Lane starts at the entry RoadPoint, not the stop line")
	assert_almost_eq(lane.get_lane_end().z, p2.global_transform.origin.z, 0.01,
			"Lane ends at the exit RoadPoint, not the stop line")


func test_straight_through_keeps_tag():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("RoadLane_p1_R0")
	assert_eq(lane.lane_next_tag, "R0", "Straight-through lane exits with the same tag")


func test_mismatched_lane_counts_merge():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	# Three entering lanes feeding into two exit lanes opposite.
	var p1: RoadPoint = container.get_node("p1")
	p1.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
	]

	container.rebuild_segments(true)

	assert_eq(_lanes_for_edge(inter, "p1").size(), 3, "All entering lanes generated")
	for lane in _lanes_for_edge(inter, "p1"):
		assert_eq(lane.curve.point_count, 4, "Each lane is routed")
	var extra: RoadLane = inter.get_node("RoadLane_p1_R2")
	assert_eq(extra.lane_next_tag, "R1", "Surplus lane merges into the outer exit lane")


func test_colinear_lane_stays_straight():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("RoadLane_p1_R0")
	var chord := lane.get_lane_start().distance_to(lane.get_lane_end())
	assert_almost_eq(lane.curve.get_baked_length(), chord, 0.1, "Colinear lane has no bulge")


func test_offset_lane_arcs_between_edges():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	# Shift the opposite edge sideways so the through lane must curve.
	var p2: RoadPoint = container.get_node("p2")
	p2.position += Vector3(10.0, 0.0, 0.0)

	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("RoadLane_p1_R0")
	var chord := lane.get_lane_start().distance_to(lane.get_lane_end())
	assert_gt(lane.curve.get_baked_length(), chord + 0.5, "Offset lane curves rather than cutting straight")


func _turn_lane_to(node: Node, edge_name: String, target_name: String) -> RoadLane:
	for child in node.get_children():
		if child is RoadLane and str(child.name).begins_with("RoadLane_%s_" % edge_name) \
				and str(child.name).ends_with("_%s" % target_name):
			return child
	return null


func test_four_way_generates_through_and_turn_lanes():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	# Each of four edges has two through lanes plus a turn to each adjacent edge.
	assert_eq(_lanes(inter).size(), 16, "Through and turn lanes for every edge")
	assert_eq(_lanes_for_edge(inter, "pn").size(), 4, "Two through and two turn lanes")


func test_four_way_turn_lane_reaches_target_edge():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	var turn := _turn_lane_to(inter, "pn", "pw")
	assert_not_null(turn, "Turn lane from pn to pw exists")
	if turn == null:
		return
	var turn_start := turn.get_lane_start()
	var turn_end := turn.get_lane_end()
	assert_lt(turn_start.z, -1.0, "Turn starts on the north edge")
	assert_lt(turn_end.x, -1.0, "Turn ends on the west edge")
	var chord := turn_start.distance_to(turn_end)
	assert_gt(turn.curve.get_baked_length(), chord + 0.5, "Turn lane arcs around the corner")


func test_four_way_turn_handedness():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	container.setup_road_container()
	road_util.create_intersection_four_branch(container)
	var inter: RoadIntersection = container.get_intersections()[0]

	container.rebuild_segments(true)

	# From the north edge heading south, west (pw) is the right turn and east
	# (pe) the left turn. Right turns source from the outer (curb-side) lane,
	# left turns from the inner (divider-side) lane.
	var right_turn := _turn_lane_to(inter, "pn", "pw")
	var left_turn := _turn_lane_to(inter, "pn", "pe")
	assert_not_null(right_turn, "Right turn pn->pw exists")
	assert_not_null(left_turn, "Left turn pn->pe exists")
	if right_turn == null or left_turn == null:
		return
	# pn's entering lanes lie on the west (-X) half; the outer/right lane sits
	# further from the centerline than the inner/left lane.
	assert_lt(right_turn.get_lane_start().x, left_turn.get_lane_start().x,
			"Right turn sources from the outer lane, left turn from the inner lane")


func test_divider_alignment_shifts_lane_offset():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	var p1: RoadPoint = container.get_node("p1")
	p1.traffic_dir = [
		RoadPoint.LaneDir.REVERSE,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD,
		RoadPoint.LaneDir.FORWARD,
	]

	p1.alignment = RoadPoint.Alignment.GEOMETRIC
	container.rebuild_segments(true)
	var geometric_x: float = (inter.get_node("RoadLane_p1_R0") as RoadLane).get_lane_start().x

	p1.alignment = RoadPoint.Alignment.DIVIDER
	container.rebuild_segments(true)
	var divider_x: float = (inter.get_node("RoadLane_p1_R0") as RoadLane).get_lane_start().x

	assert_almost_eq(divider_x - geometric_x, 4.0, 0.01, "Divider shifts entering lanes by one lane width")


func test_editable_lane_preserved_on_rebuild():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_intersection(container)
	container.rebuild_segments(true)

	var lane: RoadLane = inter.get_node("RoadLane_p1_R0")
	lane.owner = container
	var custom := Curve3D.new()
	custom.add_point(Vector3(99, 0, 0))
	custom.add_point(Vector3(100, 0, 0))
	lane.curve = custom

	container.rebuild_segments(true)

	assert_eq(lane.curve.get_point_position(0), Vector3(99, 0, 0), "User-edited lane is left intact")


# ------------------------------------------------------------------------------


func _make_t_junction(container) -> RoadIntersection:
	container.setup_road_container()
	road_util.create_intersection_three_branch(container)
	return container.get_intersections()[0]


func test_t_junction_bar_edges_pair_through():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_t_junction(container)

	container.rebuild_segments(true)

	# pw and pe form the straight bar, so each carries its entering lanes across.
	var lane: RoadLane = inter.get_node("RoadLane_pw_R0")
	assert_eq(lane.curve.point_count, 4, "Through lane runs RoadPoint to RoadPoint")
	assert_true(lane.get_lane_start().x < 0.0 and lane.get_lane_end().x > 0.0,
			"Through lane spans both bar edges")


func test_t_junction_stem_routes_through_to_primary():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_t_junction(container)

	container.rebuild_segments(true)

	# Incoming lanes always connect to the primary, even on the stem: both of its
	# entering lanes route through to pw (the bar edge it points most directly at).
	assert_not_null(inter.get_node_or_null("RoadLane_ps_R0"), "Stem routes to its primary")
	assert_not_null(inter.get_node_or_null("RoadLane_ps_R1"), "Stem routes to its primary")


func test_t_junction_stem_turns_to_non_primary_bar():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_t_junction(container)

	container.rebuild_segments(true)

	# pw is the stem's primary (taken as a through lane); the other bar edge pe is
	# reached as a turn.
	assert_not_null(_turn_lane_to(inter, "ps", "pe"), "Stem turns toward the non-primary bar")
	assert_null(_turn_lane_to(inter, "ps", "pw"), "Primary bar is a through lane, not a turn")


func test_t_junction_lane_count():
	var container = autoqfree(RoadContainer.new())
	add_child(container)
	container.generate_ai_lanes = true
	var inter := _make_t_junction(container)

	container.rebuild_segments(true)

	# Bar edges: two through lanes plus a turn to the stem apiece (3 each); stem:
	# two through lanes to its primary plus a turn to the other bar (3).
	assert_eq(_lanes(inter).size(), 9, "Through and turn lanes for the T")
