@tool
@icon("res://addons/road-generator/resources/road_intersection.png")

class_name IntersectionNGon
extends IntersectionSettings
## Defines an intersection where each edge is connected
## to its siblings with curve shoulders, forming a filled n-gon.


# ------------------------------------------------------------------------------
#region Signals/Enums/Const/Export/Vars
# ------------------------------------------------------------------------------

enum _IntersectNGonFacing {
	ORIGIN,
	AWAY,
	OTHER
}

const SegGeo := preload("res://addons/road-generator/procgen/segment_geo.gd")

const STOP_ROW_SIZE: float = 2.0  # TODO: make proportional to density
const LANE_NAME_PREFIX := "RoadLane_"

# ------------------------------------------------------------------------------
#endregion
#region Abstract overrides
# ------------------------------------------------------------------------------

func generate_mesh(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
	if not can_generate_mesh(intersection.transform, edges):
		push_error("Conditions for NGon mesh generation not met. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	if edges.size() == 0:
		push_error("No edges provided for NGon mesh generation. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	if not intersection.has_method("is_road_intersection"):
		push_error("intersection is not an intersection node. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.
	return _generate_debug_mesh(intersection, edges, container)


func get_min_distance_from_intersection_point(rp: RoadPoint) -> float:
	# TODO TBD when mesh generation is implemented.
	return 0.0


func generate_lanes(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> void:
	var active_lanes: Array[RoadLane] = []
	if not container.generate_ai_lanes:
		_clear_generated_lanes(intersection, active_lanes)
		return

	var manager: RoadManager = container.get_manager()
	var primaries := _compute_edge_primaries(edges, intersection)

	for i in range(edges.size()):
		var edge: RoadPoint = edges[i]
		if not is_instance_valid(edge):
			continue
		var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
		if facing == _IntersectNGonFacing.OTHER:
			continue
		var entering := _directional_lanes(edge, _entering_dir(facing))
		if entering.is_empty():
			continue
		var entry_dir := _edge_inward_dir(edge, intersection)
		var primary: int = primaries[i]

		# Through lanes: every entering lane routes straight across to this edge's
		# primary target. Surplus lanes merge onto its outermost exit lane, built
		# from the divider outward.
		if primary >= 0:
			var exiting := _edge_exit_lanes(edges[primary], intersection)
			for k in range(entering.size()):
				var src: Dictionary = entering[k]
				var entry := _lane_stop_position(edge, intersection, src["index"])
				var exit_point := intersection.global_transform.origin
				var exit_dir := entry_dir
				var next_tag := ""
				if not exiting.is_empty():
					var target: Dictionary = exiting[mini(k, exiting.size() - 1)]
					exit_point = _lane_stop_position(target["edge"], intersection, target["index"])
					exit_dir = -_edge_inward_dir(target["edge"], intersection)
					next_tag = target["tag"]
				var lane_name := "%s%s_%s" % [LANE_NAME_PREFIX, edge.name, src["tag"]]
				_emit_lane(intersection, container, manager, active_lanes, lane_name,
						src["tag"], next_tag, entry, entry_dir, exit_point, exit_dir,
						not exiting.is_empty())

		# Turn lanes: the turn-side entering lane reaches each remaining edge.
		for j in range(edges.size()):
			if j == i or j == primary or not is_instance_valid(edges[j]):
				continue
			var target_edge: RoadPoint = edges[j]
			var target_facing: _IntersectNGonFacing = _get_edge_facing(target_edge, intersection)
			if target_facing == _IntersectNGonFacing.OTHER:
				continue
			var target_exit := _directional_lanes(target_edge, _exiting_dir(target_facing))
			if target_exit.is_empty():
				continue
			var clockwise := _turn_is_clockwise(edge, target_edge, intersection)
			var turn_src: Dictionary = entering[entering.size() - 1] if clockwise else entering[0]
			var turn_dst: Dictionary = target_exit[target_exit.size() - 1] if clockwise else target_exit[0]
			var turn_entry := _lane_stop_position(edge, intersection, turn_src["index"])
			var turn_exit := _lane_stop_position(target_edge, intersection, turn_dst["index"])
			var turn_exit_dir := -_edge_inward_dir(target_edge, intersection)
			var turn_name := "%s%s_%s_%s" % [LANE_NAME_PREFIX, edge.name, turn_src["tag"], target_edge.name]
			_emit_lane(intersection, container, manager, active_lanes, turn_name,
					turn_src["tag"], turn_dst["tag"], turn_entry, entry_dir, turn_exit, turn_exit_dir)

	_clear_generated_lanes(intersection, active_lanes)


# ------------------------------------------------------------------------------
#endregion
#region Generation functions
# ------------------------------------------------------------------------------



func _get_edge_facing(edge: RoadPoint, intersection: Node3D) -> _IntersectNGonFacing:
	if not intersection.has_method("is_road_intersection"):
		push_error("intersection is not an intersection node. Returning OTHER facing.")
		return _IntersectNGonFacing.OTHER

	var facing: _IntersectNGonFacing = _IntersectNGonFacing.OTHER
	if edge.get_node_or_null(edge.prior_pt_init) == intersection:
		facing = _IntersectNGonFacing.ORIGIN
	elif edge.get_node_or_null(edge.next_pt_init) == intersection:
		facing = _IntersectNGonFacing.AWAY
	else:
		push_warning("Failed to find intersection connection between %s and %s" % [edge.name, intersection.name])
		facing = _IntersectNGonFacing.OTHER
	return facing


## World-space direction along an edge pointing toward the intersection (the
## travel direction of its entering lanes).
func _edge_inward_dir(edge: RoadPoint, intersection: Node3D) -> Vector3:
	var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
	var parallel_v: Vector3 = edge.global_transform.basis.z.normalized()
	if facing == _IntersectNGonFacing.ORIGIN:
		parallel_v = -parallel_v
	return parallel_v


## World-space center of an edge's stop line, where its lanes meet the intersection.
func _edge_stop_center(edge: RoadPoint, intersection: Node3D) -> Vector3:
	return edge.global_transform.origin + _edge_inward_dir(edge, intersection) * STOP_ROW_SIZE


func _entering_dir(facing: _IntersectNGonFacing) -> int:
	return RoadPoint.LaneDir.REVERSE if facing == _IntersectNGonFacing.AWAY else RoadPoint.LaneDir.FORWARD


func _exiting_dir(facing: _IntersectNGonFacing) -> int:
	return RoadPoint.LaneDir.FORWARD if facing == _IntersectNGonFacing.AWAY else RoadPoint.LaneDir.REVERSE


## Lanes of the given direction on an edge, ordered from the centerline outward,
## each as a dictionary with its `index` in traffic_dir and its `F#`/`R#` `tag`.
func _directional_lanes(edge: RoadPoint, dir: int) -> Array:
	var rev_count := edge.get_rev_lane_count()
	var result: Array = []
	for i in range(edge.traffic_dir.size()):
		if edge.traffic_dir[i] != dir:
			continue
		var tag: String
		if dir == RoadPoint.LaneDir.FORWARD:
			tag = "F%d" % (i - rev_count)
		else:
			tag = "R%d" % (rev_count - 1 - i)
		result.append({"index": i, "tag": tag})
	result.sort_custom(func(a, b): return int(a["tag"].substr(1)) < int(b["tag"].substr(1)))
	return result


## Exit lanes available on an edge, tagged with the edge they belong to so a
## through lane can target them.
func _edge_exit_lanes(edge: RoadPoint, intersection: Node3D) -> Array:
	var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
	if facing == _IntersectNGonFacing.OTHER:
		return []
	var lanes := _directional_lanes(edge, _exiting_dir(facing))
	for lane in lanes:
		lane["edge"] = edge
	return lanes


## True when the edge at `index` is a valid, intersection-facing edge eligible
## to take part in lane matching.
func _edge_is_eligible(edges: Array[RoadPoint], index: int, intersection: Node3D) -> bool:
	if not is_instance_valid(edges[index]):
		return false
	return _get_edge_facing(edges[index], intersection) != _IntersectNGonFacing.OTHER


## Picks each edge's primary target: the edge across the intersection it points
## most directly at (smallest angle from dead-ahead, regardless of distance).
## The returned array holds each edge's primary index, or -1 when it has none.
## Every eligible edge routes its entering lanes through to its primary, whether
## or not the choice is reciprocated.
func _compute_edge_primaries(edges: Array[RoadPoint], intersection: Node3D) -> Array[int]:
	var origin := intersection.global_transform.origin
	var count := edges.size()
	var primary: Array[int] = []
	primary.resize(count)
	primary.fill(-1)
	for i in range(count):
		if not _edge_is_eligible(edges, i, intersection):
			continue
		var dir_i := (edges[i].global_transform.origin - origin).normalized()
		var best := -1
		var best_dot := INF
		for j in range(count):
			if j == i or not _edge_is_eligible(edges, j, intersection):
				continue
			var dot := dir_i.dot((edges[j].global_transform.origin - origin).normalized())
			if dot < best_dot:
				best_dot = dot
				best = j
		primary[i] = best
	return primary


## True if the target edge lies clockwise (to the right) of the edge's inbound
## direction about the intersection's up axis.
func _turn_is_clockwise(edge: RoadPoint, target: RoadPoint, intersection: Node3D) -> bool:
	var up: Vector3 = intersection.global_transform.basis.y.normalized()
	var inward := _edge_inward_dir(edge, intersection)
	var to_target := (target.global_transform.origin - intersection.global_transform.origin).normalized()
	return inward.signed_angle_to(to_target, up) > 0.0


## Finds an existing generated lane by name or creates one, ensuring group
## membership and editor metadata.
func _get_or_create_lane(intersection: Node3D, container: RoadContainer, manager: RoadManager, lane_name: String) -> RoadLane:
	var existing := intersection.get_node_or_null(lane_name)
	var lane: RoadLane
	if existing is RoadLane:
		lane = existing
	else:
		lane = RoadLane.new()
		intersection.add_child(lane)
		lane.name = lane_name
		lane.set_meta("_edit_lock_", true)
		lane.auto_free_vehicles = container.auto_free_vehicles
		if container.debug_scene_visible:
			lane.owner = container.get_owner()
	if container.ai_lane_group != "":
		lane.add_to_group(container.ai_lane_group)
	elif is_instance_valid(manager) and manager.ai_lane_group != "":
		lane.add_to_group(manager.ai_lane_group)
	return lane


## Creates or updates a single lane with its tags, curve and draw settings.
## Lanes the user has promoted to editable (given an owner) are left untouched.
func _emit_lane(intersection: Node3D, container: RoadContainer, manager: RoadManager, active_lanes: Array[RoadLane], lane_name: String, prior_tag: String, next_tag: String, entry: Vector3, entry_dir: Vector3, exit_point: Vector3, exit_dir: Vector3, extend_exit: bool = true) -> void:
	var existing := intersection.get_node_or_null(lane_name)
	var lane := _get_or_create_lane(intersection, container, manager, lane_name)
	active_lanes.append(lane)
	if existing is RoadLane and is_instance_valid(existing.owner):
		return
	lane.lane_prior_tag = prior_tag
	lane.lane_next_tag = next_tag
	_assign_through_curve(lane, intersection, entry, exit_point, entry_dir, exit_dir, extend_exit)
	lane.draw_in_editor = container.draw_lanes_editor
	lane.draw_in_game = container.draw_lanes_game
	lane.refresh_geom = true
	lane.rebuild_geom()


## World-space center of a single lane at its edge's stop line. Geometric edges
## center their lanes; divider-aligned edges keep the direction split at origin.
func _lane_stop_position(edge: RoadPoint, intersection: Node3D, lane_index: int) -> Vector3:
	var reference := edge.traffic_dir.size() / 2.0
	if edge.alignment == RoadPoint.Alignment.DIVIDER:
		reference = edge.get_rev_lane_count()
	var offset := (lane_index - reference + 0.5) * edge.lane_width
	var perpendicular_v: Vector3 = edge.global_transform.basis.x.normalized()
	return _edge_stop_center(edge, intersection) + perpendicular_v * offset


## Curve from an entry RoadPoint to an exit RoadPoint, in the lane's local space.
## The lane runs straight from each RoadPoint up to its stop line, then arcs
## across the intersection with bezier handles aligned to the entry and exit
## travel directions (staying straight when those directions are colinear). With
## no exit edge to reach, the lane simply ends at the stop line.
func _assign_through_curve(lane: RoadLane, intersection: Node3D, entry: Vector3, exit_point: Vector3, entry_dir: Vector3, exit_dir: Vector3, extend_exit: bool = true) -> void:
	var to_local: Transform3D = lane.global_transform.affine_inverse()
	var dir_in := (to_local.basis * entry_dir).normalized()
	var dir_out := (to_local.basis * exit_dir).normalized()
	var entry_stop := to_local * entry
	var exit_stop := to_local * exit_point
	var lead := dir_in * (STOP_ROW_SIZE / 3.0)
	var handle := entry_stop.distance_to(exit_stop) / 3.0

	var curve := Curve3D.new()
	# Lead in from the entry RoadPoint to its stop line, then arc across.
	curve.add_point(entry_stop - dir_in * STOP_ROW_SIZE, Vector3.ZERO, lead)
	curve.add_point(entry_stop, -lead, dir_in * handle)
	if extend_exit:
		# Arc to the exit stop line, then lead out to the exit RoadPoint.
		var out_lead := dir_out * (STOP_ROW_SIZE / 3.0)
		curve.add_point(exit_stop, -dir_out * handle, out_lead)
		curve.add_point(exit_stop + dir_out * STOP_ROW_SIZE, -out_lead, Vector3.ZERO)
	else:
		curve.add_point(exit_stop, -dir_out * handle, Vector3.ZERO)
	lane.curve = curve


## Frees previously generated lanes that are no longer active.
func _clear_generated_lanes(intersection: Node3D, keep: Array[RoadLane]) -> void:
	for child in intersection.get_children():
		if not (child is RoadLane):
			continue
		if not str(child.name).begins_with(LANE_NAME_PREFIX):
			continue
		if keep.has(child):
			continue
		child.queue_free()


## Generates a triangles from shoulders to intersection point,
## and triangles from an edge's shoulders to the intersection point.
## The end result is a very low-poly n-gon.[br][br]
## Edges MUST have been sorted by angle from intersection beforehand.
func _generate_debug_mesh(intersection: Node3D, edges: Array[RoadPoint], container: RoadContainer) -> Mesh:
	if not intersection.has_method("is_road_intersection"):
		push_error("intersection is not an intersection node. Returning an empty mesh.")
		return Mesh.new() # Empty mesh.

	var parent_transform: Transform3D = intersection.transform
	
	# origin is the intersection position, coords are relative to it.
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	const TOPSIDE_SMOOTHING_GROUP = 1
	surface_tool.set_smooth_group(TOPSIDE_SMOOTHING_GROUP)

	# First, add an additional row of quads to each edge,
	# to give a UV space for stop marks or other markings.
	# We also prepare the intersection by storing appropriate
	# shoulder and gutter positions.

	## Array[Array[Vector3][2]]
	var edge_shoulders: Array[Array] = []
	## Array[Array[Vector3][2]]
	var edge_gutters: Array[Array] = []
	## Array[Array[Vector3][2]]
	var edge_road_sides: Array[Array] = []
	
	const uv_width := 0.125 # 1/8 for breakdown of texture.
	const uv_gutter_width := uv_width * SegGeo.UV_MID_SHOULDER
	var density := container.effective_density()

	for edge: RoadPoint in edges:
		var facing: _IntersectNGonFacing = _get_edge_facing(edge, intersection)
		if facing == _IntersectNGonFacing.OTHER:
			push_error("Unexpected RoadPoint state in IntersectionNGon mesh generation (next/prior points both null or defined on %s). Returning an empty mesh." % [edge.name])
			return Mesh.new() # Empty mesh.
		
		var lane_width: float = edge.lane_width
		var lanes_count = edge.lanes.size()
		var lanes_tot_width: float = lane_width * lanes_count
		var shoulder_offset_l: float = edge.shoulder_width_l
		var shoulder_offset_r: float = edge.shoulder_width_r
		var gutter: Vector2 = edge.gutter_profile
		
		# Aim for real-world texture proportions width:height of 2:1 matching texture,
		# but then the hight of 1 full UV is half the with across all lanes, so another 2x
		var uv_height := STOP_ROW_SIZE / lane_width / 8.0 # ratio of 1/4th down vs width of image to be square

		var perpendicular_v: Vector3 = (edge.transform.basis.x).normalized()
		var up_vector: Vector3 = (edge.transform.basis.y).normalized()
		var parallel_v: Vector3 = (edge.transform.basis.z).normalized()

		var road_side_l: Vector3 = edge.position
		var road_side_r: Vector3 = edge.position
		road_side_l -= perpendicular_v * (lanes_tot_width / 2.0)
		road_side_r += perpendicular_v * (lanes_tot_width / 2.0)

		var shoulder_l: Vector3 = road_side_l
		var shoulder_r: Vector3 = road_side_r
		shoulder_l -= shoulder_offset_l * perpendicular_v
		shoulder_r += shoulder_offset_r * perpendicular_v

		var gutter_l: Vector3 = shoulder_l + (gutter[0] * -perpendicular_v + gutter[1] * up_vector)
		var gutter_r: Vector3 = shoulder_r + (gutter[0] * perpendicular_v + gutter[1] * up_vector)

		if facing == _IntersectNGonFacing.ORIGIN:	
			parallel_v = -parallel_v

		var shoulder_l_stop: Vector3 = shoulder_l + parallel_v * STOP_ROW_SIZE
		var shoulder_r_stop: Vector3 = shoulder_r + parallel_v * STOP_ROW_SIZE
		var gutter_l_stop: Vector3 = gutter_l + parallel_v * STOP_ROW_SIZE
		var gutter_r_stop: Vector3 = gutter_r + parallel_v * STOP_ROW_SIZE
		var road_side_l_stop: Vector3 = road_side_l + parallel_v * STOP_ROW_SIZE
		var road_side_r_stop: Vector3 = road_side_r + parallel_v * STOP_ROW_SIZE

		if facing == _IntersectNGonFacing.ORIGIN:	
			edge_shoulders.append([shoulder_l_stop, shoulder_r_stop])
			edge_gutters.append([gutter_l_stop, gutter_r_stop])
			edge_road_sides.append([road_side_l_stop, road_side_r_stop])
		else: # facing == _IntersectNGonFacing.AWAY
			edge_shoulders.append([shoulder_r_stop, shoulder_l_stop])
			edge_gutters.append([gutter_r_stop, gutter_l_stop])
			edge_road_sides.append([road_side_r_stop, road_side_l_stop])

		# swap sides if needed
		if facing == _IntersectNGonFacing.ORIGIN:
			var temp: Vector3 = shoulder_l
			shoulder_l = shoulder_r
			shoulder_r = temp
			temp = shoulder_l_stop
			shoulder_l_stop = shoulder_r_stop
			shoulder_r_stop = temp
			temp = gutter_l
			gutter_l = gutter_r
			gutter_r = temp
			temp = gutter_l_stop
			gutter_l_stop = gutter_r_stop
			gutter_r_stop = temp
			temp = road_side_l
			road_side_l = road_side_r
			road_side_r = temp
			temp = road_side_l_stop
			road_side_l_stop = road_side_r_stop
			road_side_r_stop = temp

		# Left gutter quad
		surface_tool.set_uv(Vector2(0.0, uv_height))
		surface_tool.add_vertex(gutter_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(0.0, 0.0))
		surface_tool.add_vertex(gutter_l - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_l - parent_transform.origin)

		surface_tool.set_uv(Vector2(uv_gutter_width, uv_height))
		surface_tool.add_vertex(shoulder_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(0.0, uv_height))
		surface_tool.add_vertex(gutter_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_l - parent_transform.origin)

		# Left shoulder quad
		surface_tool.set_uv(Vector2(uv_width, uv_height))
		surface_tool.add_vertex(road_side_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, uv_height))
		surface_tool.add_vertex(shoulder_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_l - parent_transform.origin)

		surface_tool.set_uv(Vector2(uv_width, 0.0))
		surface_tool.add_vertex(road_side_l - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width, uv_height))
		surface_tool.add_vertex(road_side_l_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_l - parent_transform.origin)

		# Lanes quads
		for i in range(lanes_count):
			var current_perpendicular_v: Vector3 = perpendicular_v
			if facing == _IntersectNGonFacing.ORIGIN:
				current_perpendicular_v = -perpendicular_v
			var lane_left_side: Vector3 = road_side_l + current_perpendicular_v * (lane_width * i)
			var lane_right_side: Vector3 = road_side_l + current_perpendicular_v * (lane_width * (i + 1))
			var lane_left_side_stop: Vector3 = lane_left_side + parallel_v * STOP_ROW_SIZE
			var lane_right_side_stop: Vector3 = lane_right_side + parallel_v * STOP_ROW_SIZE

			# Lane quad
			var u_near := uv_width*6
			var u_far := uv_width*7
			
			surface_tool.set_uv(Vector2(uv_width*7, uv_height))
			surface_tool.add_vertex(lane_left_side - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*6, uv_height))
			surface_tool.add_vertex(lane_right_side - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*6, 0.0))
			surface_tool.add_vertex(lane_right_side_stop - parent_transform.origin)

			surface_tool.set_uv(Vector2(uv_width*7, uv_height))
			surface_tool.add_vertex(lane_left_side - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*6, 0.0))
			surface_tool.add_vertex(lane_right_side_stop - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*7, 0.0))
			surface_tool.add_vertex(lane_left_side_stop - parent_transform.origin)

		# Right shoulder quad
		surface_tool.set_uv(Vector2(uv_width, uv_height))
		surface_tool.add_vertex(road_side_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width, 0.0))
		surface_tool.add_vertex(road_side_r - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_r - parent_transform.origin)

		surface_tool.set_uv(Vector2(uv_gutter_width, uv_height))
		surface_tool.add_vertex(shoulder_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width, uv_height))
		surface_tool.add_vertex(road_side_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_r - parent_transform.origin)

		# Right gutter quad
		surface_tool.set_uv(Vector2(0.0, 0.0))
		surface_tool.add_vertex(gutter_r - parent_transform.origin)
		surface_tool.set_uv(Vector2(0.0, uv_height))
		surface_tool.add_vertex(gutter_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_r - parent_transform.origin)

		surface_tool.set_uv(Vector2(0.0, uv_height))
		surface_tool.add_vertex(gutter_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, uv_height))
		surface_tool.add_vertex(shoulder_r_stop - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
		surface_tool.add_vertex(shoulder_r - parent_transform.origin)

	# Then, connect edges with its siblings (gutters and shoulders quads).
	# At the same time, create triangles from shoulders to intersection point;
	# to form a triangle fan filling the intersection.

	var iteration_i = 0
	for sides in edge_road_sides:
		var side_l: Vector3 = sides[0]
		var side_r: Vector3 = sides[1]

		# add vertices

		# add "road edge" triangle
		# Below is ((right-orign)-(left-origin)).length() expanded out
		# This is ((side_l) + (side_r))/2 expanded
		var mid_point := (side_l + side_r - parent_transform.origin*2)/2.0
		# Distance from edge to the intersection center
		var sibling_dist:float = mid_point.length()
		var sibling_width:float = (side_r - side_l).length()
		var v_dist: float = sibling_width / 16.0
		# find center point between left/right, and get length to center
		var center_dist := sibling_dist / 2.0 / sibling_width
		surface_tool.set_uv(Vector2(uv_width*7, 0.0))
		surface_tool.add_vertex(side_r - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width*6, 0.0))
		surface_tool.add_vertex(side_l - parent_transform.origin)
		surface_tool.set_uv(Vector2(uv_width*6.5, center_dist))
		surface_tool.add_vertex(Vector3.ZERO)

		# add "sibling" triangle
		# /!\ /!\ /!\ only support nodes in a very specific order
		# (edges should be sorted by the caller)
		if (edge_shoulders.size() > 1):
			var next_iteration_i: int = (iteration_i + 1) % edge_shoulders.size()
			var next_side_r: Vector3 = edge_road_sides[next_iteration_i][1]
			# This is ((next_side_r) + (side_l))/2 expanded
			mid_point = (next_side_r + side_l - parent_transform.origin*2.0)/2.0
			sibling_dist = mid_point.length()
			sibling_width = (next_side_r - side_l).length()
			var v_span_dist: float = sibling_dist / 2.0 / sibling_width

			surface_tool.set_uv(Vector2(uv_width*6.5, 0.0))
			surface_tool.add_vertex(Vector3.ZERO)
			surface_tool.set_uv(Vector2(uv_width*7, v_span_dist))
			surface_tool.add_vertex(side_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width*6, v_span_dist))
			surface_tool.add_vertex(next_side_r - parent_transform.origin)

			# also add the gutter profile and the shoulder offset
			# on the intersection exterior border
			# (quad from one edge's gutter to the next edge's gutter, same for shoulders).

			# shoulder quad
			var shoulder_l: Vector3 = edge_shoulders[iteration_i][0]
			var next_shoulder_r: Vector3 = edge_shoulders[next_iteration_i][1]

			surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
			surface_tool.add_vertex(shoulder_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_gutter_width, v_dist))
			surface_tool.add_vertex(next_shoulder_r - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width, v_dist))
			surface_tool.add_vertex(next_side_r - parent_transform.origin)

			surface_tool.set_uv(Vector2(uv_width, 0.0))
			surface_tool.add_vertex(side_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
			surface_tool.add_vertex(shoulder_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_width, v_dist))
			surface_tool.add_vertex(next_side_r - parent_transform.origin)

			# gutter quad
			var current_gutter_l: Vector3 = edge_gutters[iteration_i][0]
			var next_gutter_r: Vector3 = edge_gutters[next_iteration_i][1]

			surface_tool.set_uv(Vector2(uv_gutter_width, 0.0))
			surface_tool.add_vertex(shoulder_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(current_gutter_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(uv_gutter_width, v_dist))
			surface_tool.add_vertex(next_shoulder_r - parent_transform.origin)
			
			surface_tool.set_uv(Vector2(uv_gutter_width, v_dist))
			surface_tool.add_vertex(next_shoulder_r - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, 0.0))
			surface_tool.add_vertex(current_gutter_l - parent_transform.origin)
			surface_tool.set_uv(Vector2(0.0, v_dist))
			surface_tool.add_vertex(next_gutter_r - parent_transform.origin)

		iteration_i += 1
	
	surface_tool.index()
	var material: Material = container.effective_surface_material()
	if material:
		surface_tool.set_material(material)
	surface_tool.generate_normals()
	var mesh: ArrayMesh = surface_tool.commit()  # should be MeshInstance3D?
	#mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


#endregion
# ------------------------------------------------------------------------------
