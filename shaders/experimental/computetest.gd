extends Node3D


# Called when the node enters the scene tree for the first time.
func _ready():
	var rendering_device = RenderingServer.create_local_rendering_device()

	var shader_file = load("res://scripts/computetest.glsl")
	var shader_spirv = shader_file.get_spirv()
	var shader_RID = rendering_device.shader_create_from_spirv(shader_spirv)
	
	var floats = PackedFloat32Array([1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]).to_byte_array()
	var storage_buffer_RID = rendering_device.storage_buffer_create(floats.size(), floats)
	var uniform = RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(storage_buffer_RID)
	var uniform_set_RID = rendering_device.uniform_set_create([uniform], shader_RID, 0)
	
	var pipeline_RID = rendering_device.compute_pipeline_create(shader_RID)
	
	var compute_list_id = rendering_device.compute_list_begin()
	
	rendering_device.compute_list_bind_compute_pipeline(compute_list_id, pipeline_RID)
	rendering_device.compute_list_bind_uniform_set(compute_list_id, uniform_set_RID, 0)
	rendering_device.compute_list_dispatch(compute_list_id, 2, 1, 1)
	rendering_device.compute_list_end()
	
	rendering_device.submit()
	rendering_device.sync()
	
	var output_bytes = rendering_device.buffer_get_data(storage_buffer_RID)
	var output = output_bytes.to_float32_array()
	print(output)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass
