@tool
extends MeshInstance3D

@export_range(20, 400, 1) var terrain_size: int = 100
@export_range(1, 100, 1) var resolution: int = 15

const CENTER_OFFSET: float = 0.5
@export var y_amplitude: float = 5.0
@export var noise_offset_x: float = 0.5
@export var noise_offset_z: float = 0.5

@export var create_collision = false
@export var remove_collision = false

@export var min_height = 0
@export var max_height = 1


func _ready() -> void:
	generate_terrain()

func generate_terrain():
	
	var a_mesh: ArrayMesh
	var surftool = SurfaceTool.new()
	
	var terrain_noise = FastNoiseLite.new()
	terrain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	terrain_noise.frequency = 0.1
	
	surftool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# generate terrain topology
	for z in resolution + 1:
		for x in resolution + 1:
			
			# offset this piece of terrain around center point
			var percent: Vector2 = Vector2(x, z) / resolution
			var point_on_mesh: Vector3 = Vector3((percent.x - CENTER_OFFSET), 0, (percent.y - CENTER_OFFSET))
			
			# make a vertex for terrain
			var terrain_vertex = point_on_mesh * terrain_size
			
			# set the y amplitude for this piece of terrain
			terrain_vertex.y = terrain_noise.get_noise_2d(terrain_vertex.x * noise_offset_x, terrain_vertex.z * noise_offset_z) * y_amplitude
			
			# apply noise to y axis
			#var y: float = terrain_noise.get_noise_2d(x * noise_offset_x, z * noise_offset_z) * y_amplitude
			
			#if y < min_height and y != null:
				#min_height = y
			#if y > max_height and y != null:
				#max_height = y
			
			# maps out what percentage of the way this position in UV space is relative to our terrain vertex in 3D space
			var uv = Vector2()
			uv.x = percent.x
			uv.y = percent.y
			
			surftool.set_uv(uv)
			surftool.add_vertex(terrain_vertex)
			
			#draw_sphere(Vector3(x, y, z))
	
	# arrange terrain topology (indices)
	var vert_index: int = 0
	
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
	
	# generate normals!
	surftool.generate_normals()
	
	# commit changes to procedural mesh
	a_mesh = surftool.commit()
	mesh = a_mesh
	update_shader()
	

func update_shader():
	var mat = get_active_material(0)
	mat.set_shader_parameter("min_height", min_height)
	mat.set_shader_parameter("max_height", max_height)

#visualization of verts (debug)
func draw_sphere(pos: Vector3):
	var ins = MeshInstance3D.new()
	add_child(ins)
	ins.position = pos
	var sphere = SphereMesh.new()
	sphere.radius = 0.1
	sphere.height = 0.2
	ins.mesh = sphere


var last_res = 0
var last_size = 0
var last_amplitude = 0
var last_offset_x = 0
var last_offset_z = 0

func _process(delta: float) -> void:
	if resolution != last_res or terrain_size != last_size or y_amplitude != last_amplitude or noise_offset_x != last_offset_x or noise_offset_z != last_offset_z:
		generate_terrain()
		last_res = resolution
		last_size = terrain_size
		last_amplitude = y_amplitude
		last_offset_x = noise_offset_x
		last_offset_z = noise_offset_z
		
	if remove_collision:
		clear_collision()
		remove_collision = false
		
	if create_collision:
		clear_collision()
		create_trimesh_collision()
		create_collision = false
		
func clear_collision():
	if get_child_count() > 0:
		for i in get_children():
			i.free()
