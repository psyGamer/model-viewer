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
@binding(2) @group(0) var<storage, read> indices : array<u32>;

struct VertexInput {
    @builtin(vertex_index) VertexID : u32
};
struct VertexOutput {
    @builtin(position) BuiltinPosition : vec4<f32>,
    @location(0) Position : vec3<f32>,
    @location(1) Normal : vec3<f32>,
};

@vertex fn vertex_main(vertex: VertexInput) -> VertexOutput {
    let vertexID = indices[vertex.VertexID];
    var output : VertexOutput;
    output.Position = (uniforms.model * vec4<f32>(vertices[vertexID].Position, 1.0)).xyz;
    output.BuiltinPosition = uniforms.proj * uniforms.view * vec4<f32>(output.Position, 1.0);
    output.Normal = uniforms.normal * vertices[vertexID].Normal;
    return output;
}

@vertex fn vertex_main_wireframe(vertex : VertexInput) -> @builtin(position) vec4<f32> {
    // Determine the actual index into the vertex buffer
    var localToElement = array<u32, 6>(0u, 1u, 1u, 2u, 2u, 0u);
    var triangleIndex = vertex.VertexID / 6u;
    var localVertexIndex = vertex.VertexID % 6u;
    var elementIndexIndex = 3u * triangleIndex + localToElement[localVertexIndex];
    var elementIndex = indices[elementIndexIndex];
    
    return uniforms.proj * uniforms.view * uniforms.model * vec4<f32>(vertices[elementIndex].Position, 1.0);
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

@fragment fn frag_main_wireframe() -> @location(0) vec4<f32> {
    return vec4<f32>(1.0);
}
