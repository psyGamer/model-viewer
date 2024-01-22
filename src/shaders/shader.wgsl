struct Uniforms {
    modelViewProjectionMatrix : mat4x4<f32>,
};

struct Vertex {
    position: vec4<f32>, // Actually a vec3, but alignment
    normal: vec4<f32>,   // -||-
};

@binding(0) @group(0) var<uniform> uniforms : Uniforms;
@binding(1) @group(0) var<storage, read> vertices : array<Vertex>;

struct VertexInput {
    @builtin(vertex_index) vertexID : u32
};
struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) Color : vec3<f32>,
};

@vertex fn vertex_main(vertex: VertexInput) -> VertexOutput {
    var output : VertexOutput;
    output.Position = vec4<f32>(vertices[vertex.vertexID].position.xyz, 1.0) * uniforms.modelViewProjectionMatrix;
    output.Color = vertices[vertex.vertexID].position.xyz;
    return output;
}

@fragment fn frag_main(@location(0) Color: vec3<f32>) -> @location(0) vec4<f32> {
    return vec4<f32>(Color, 1.0);
}
