extends Node3D

@export var chunk_size: int = 400
@export var terrain_amplitude: int = 20
@export var view_distance: int = 4000
@export var viewer: CharacterBody3D
@export var chunk_mesh_scene: PackedScene

@export var noise: FastNoiseLite

var viewer_position: Vector2 = Vector2()
var terrain_chunks = {}
var chunks_visible: int = 0
var last_visible_chunks = []


func _ready() -> void:
	# init
	chunks_visible = roundi(view_distance / chunk_size)
	set_wireframe()
	update_visible_chunks()


func _process(delta: float) -> void:
	
	# cache position of whatever is viewing this terrain
	viewer_position.x = viewer.global_position.x
	viewer_position.y = viewer.global_position.z
	
	update_visible_chunks()
	
	
#debug
func set_wireframe():
	RenderingServer.set_debug_generate_wireframes(true)
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_WIREFRAME


func update_visible_chunks():
	# clear previously visible chunks
	for chunk in last_visible_chunks:
		chunk.set_chunk_visibility(false)
	last_visible_chunks.clear()
	
	var current_x = roundi(viewer_position.x / chunk_size)
	var current_y = roundi(viewer_position.y / chunk_size)
	
	# search in range of chunks visible in all directions
	for y_offset in range(-chunks_visible, chunks_visible):
		for x_offset in range(-chunks_visible, chunks_visible):
			# get a chunk coordinate
			var view_chunk_coord: Vector2 = Vector2(current_x - x_offset, current_y - y_offset)
			
			# if our terrain chunks have this coordinate, update chunk.
			if terrain_chunks.has(view_chunk_coord):
				terrain_chunks[view_chunk_coord].update_chunk(viewer_position, view_distance)
				
				# if update_lod function returns true, generate terrain again.
				if terrain_chunks[view_chunk_coord].update_lod(viewer_position):
					terrain_chunks[view_chunk_coord].generate_chunk(noise, view_chunk_coord, chunk_size, true)
					
				# if chunk is visible, add it to our list of chunks
				if terrain_chunks[view_chunk_coord].get_chunk_visibility():
					last_visible_chunks.append(terrain_chunks[view_chunk_coord])
					
			# if this chunk doesn't exist, instantiate it.
			else:
				var chunk: TerrainChunk = chunk_mesh_scene.instantiate()
				add_child(chunk)
				chunk.terrain_y_amplitude = terrain_amplitude
				
				var pos := view_chunk_coord * chunk_size
				var world_position: Vector3 = Vector3(pos.x, 0, pos.y) # 2D terrain y = 3D terrain z
				
				chunk.set_collision = true
				chunk.global_position = world_position
				chunk.generate_chunk(noise, view_chunk_coord, chunk_size, false)
				terrain_chunks[view_chunk_coord] = chunk
