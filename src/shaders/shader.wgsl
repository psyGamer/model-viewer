struct Uniforms {
    model : mat4x4<f32>,
    view : mat4x4<f32>,
    proj : mat4x4<f32>,
};

struct Vertex {
    Position: vec3<f32>,
    Normal: vec3<f32>,
};

@binding(0) @group(0) var<uniform> uniforms : Uniforms;
@binding(1) @group(0) var<storage, read> vertices : array<Vertex>;

struct VertexInput {
    @builtin(vertex_index) vertexID : u32
};
struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) Normal : vec3<f32>,
};

@vertex fn vertex_main(vertex: VertexInput) -> VertexOutput {
    var output : VertexOutput;
    output.Position = uniforms.proj * uniforms.view * uniforms.model * vec4<f32>(vertices[vertex.vertexID].Position, 1.0);
    let normal = uniforms.model * vec4<f32>(vertices[vertex.vertexID].Normal, 1.0);
    output.Normal = normal.xyz / normal.w;
    return output;
}

struct FragmentInput {
    @location(0) Normal : vec3<f32>,
}

@fragment fn frag_main(frag: FragmentInput) -> @location(0) vec4<f32> {
    const sunDir = normalize(vec3<f32>(10, 10, 10));

    let nDotL = max(0, dot(frag.Normal, sunDir));
    let ambiance = 0.1;
    
    return vec4<f32>(vec3<f32>(nDotL + ambiance), 1.0);
    // return vec4<f32>(frag.Normal, 1.0);
}
