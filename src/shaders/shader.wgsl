struct Uniforms {
    model : mat4x4<f32>,
    view : mat4x4<f32>,
    proj : mat4x4<f32>,
    normal: mat3x3<f32>,
    camPos: vec3<f32>,
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
    @builtin(position) BuiltinPosition : vec4<f32>,
    @location(0) Position : vec3<f32>,
    @location(1) Normal : vec3<f32>,
};

@vertex fn vertex_main(vertex: VertexInput) -> VertexOutput {
    var output : VertexOutput;
    output.Position = (uniforms.model * vec4<f32>(vertices[vertex.vertexID].Position, 1.0)).xyz;
    output.BuiltinPosition = uniforms.proj * uniforms.view * vec4<f32>(output.Position, 1.0);
    output.Normal = uniforms.normal * vertices[vertex.vertexID].Normal;
    return output;
}

struct FragmentInput {
    @location(0) Position : vec3<f32>,
    @location(1) Normal : vec3<f32>,
}

@fragment fn frag_main(frag: FragmentInput) -> @location(0) vec4<f32> {
    const lightPos = vec3<f32>(100.2, 100, 200);
    let lightDir = normalize(lightPos - frag.Position);

    let ambiance = 0.1;
    let diffuse = max(0, dot(frag.Normal, lightDir));
    
    let viewDir = normalize(uniforms.camPos - frag.Position);
    let halfwayDir = normalize(viewDir + lightDir);
    let specular = pow(max(0, dot(viewDir, halfwayDir)), 64);
    
    return vec4<f32>(vec3<f32>(ambiance + diffuse + specular * 0.25), 1.0);
}
