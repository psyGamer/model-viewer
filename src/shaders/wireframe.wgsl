struct Uniforms {
    model : mat4x4<f32>,
    view : mat4x4<f32>,
    proj : mat4x4<f32>,
};

struct Vertex {
    position: vec3<f32>,
    normal: vec3<f32>,
};

@binding(0) @group(0) var<uniform> uniforms : Uniforms;
@binding(1) @group(0) var<storage, read> vertices : array<Vertex>;
@binding(2) @group(0) var<storage, read> indices : array<u32>;

struct VertexInput {
    @builtin(vertex_index) vertexID : u32
}

struct VertexOutput {
    @builtin(position) position : vec4<f32>,
    @location(0) color : vec3<f32>
}

@vertex fn vertex_main(vertex : VertexInput) -> VertexOutput {
    // Determine the actual index into the vertex buffer
    var localToElement = array<u32, 6>(0u, 1u, 1u, 2u, 2u, 0u);
    var triangleIndex = vertex.vertexID / 6u;
    var localVertexIndex = vertex.vertexID % 6u;
    var elementIndexIndex = 3u * triangleIndex + localToElement[localVertexIndex];
    var elementIndex = indices[elementIndexIndex];
    
    var output : VertexOutput;
    output.position = uniforms.proj * uniforms.view * uniforms.model * vec4<f32>(vertices[elementIndex].position.xyz, 1.0);
    output.color = vertices[elementIndex].position.xyz;
    output.color = vec3<f32>(1.0);
    return output;
}

@fragment fn frag_main(@location(0) Color: vec3<f32>) -> @location(0) vec4<f32> {
    return vec4<f32>(Color, 1.0);
}
