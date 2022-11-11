class_name TerrainChunk

extends MeshInstance3D

@export_range(20, 400, 1) var terrain_size: int = 200
@export_range(1, 100, 1) var resolution: int = 20
@export var terrain_y_amplitude: int = 20
var view_distances = [1000, 800, 500]
var chunk_lods = [5, 20, 50, 80]
var position_coord: Vector2 = Vector2()
const CENTER_OFFSET: float = 0.5

var set_collision: bool = false


func generate_chunk(noise: FastNoiseLite, coords: Vector2, size: float, visible_init: bool):
	terrain_size = size
	position_coord = coords * size
	
	# init
	var a_mesh: ArrayMesh
	var surftool = SurfaceTool.new()
	surftool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	for z in resolution + 1:
		for x in resolution + 1:
			# get the percentage of the current point's position relative to full resolution
			var percent = Vector2(x, z) / resolution
			
			# calculate point on mesh and offset by 0.5 to center terrain
			var point_on_mesh: Vector3 = Vector3((percent.x - CENTER_OFFSET), 0, (percent.y - CENTER_OFFSET))
			
			#multiply point by terrain's size to get proper vertex position
			var vertex = point_on_mesh * terrain_size
			
			# set Y axis amplitude of the vertex using noise
			vertex.y = noise.get_noise_2d(position.x + vertex.x, position.z + vertex.z) * terrain_y_amplitude
			
			# generate UVs using point percentage
			var uv = Vector2()
			uv.x = percent.x
			uv.y = percent.y # UV y-axis == 3D z-axis
			
			# configure UV and vertex
			surftool.set_uv(uv)
			surftool.add_vertex(vertex)

	# create indices for each triangle in a clockwise fashion
	var vert_index = 0
	for z in resolution:
		for x in resolution:
			surftool.add_index(vert_index + 0)
			surftool.add_index(vert_index + 1)
			surftool.add_index(vert_index + resolution + 1)
			surftool.add_index(vert_index + resolution + 1)
			surftool.add_index(vert_index + 1)
			surftool.add_index(vert_index + resolution + 2)
			
			vert_index += 1
		
		vert_index += 1

	# generate normals, create array mesh from collected data, assign that as our actual mesh.
	surftool.generate_normals()
	a_mesh = surftool.commit()
	mesh = a_mesh

	# create collisions, set default visibility
	if set_collision == true:
		create_collision()
		
	set_chunk_visibility(visible_init)


# called from infinite terrain scene
func update_chunk(view_position: Vector2, max_view_distance: int):
	# calculate distance from viewer's position (such as a player) to determine if chunk should be rendered.
	var viewer_distance: int = position_coord.distance_to(view_position)
	var _is_visible: bool = viewer_distance <= max_view_distance
	set_chunk_visibility(_is_visible)


# called from infinite terrain scene
func update_lod(view_position: Vector2) -> bool:
	# calculate which LOD to use based on viewer's position
	var viewer_distance: int = position_coord.distance_to(view_position)
	var update_terrain: bool = false
	var new_lod: int = 0
	
	if viewer_distance > view_distances[0]:
		new_lod = chunk_lods[0]
	elif viewer_distance <= view_distances[0]:
		new_lod = chunk_lods[1]
	elif viewer_distance < view_distances[1]:
		new_lod = chunk_lods[2]
	elif viewer_distance < view_distances[2]:
		new_lod = chunk_lods[3]
		set_collision = true
	
	if resolution != new_lod:
		resolution = new_lod
		update_terrain = true
		
	return update_terrain
		

func create_collision():
	# free existing data
	if get_child_count() > 0:
		for i in get_children():
			i.free()
	
	# generate triangular mesh collisions
	create_trimesh_collision()

func get_chunk_visibility() -> bool:
	return visible

func set_chunk_visibility(_is_visible: bool):
	visible = _is_visible
	
