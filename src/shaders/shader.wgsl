struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) Color : vec3<f32>,
};

@vertex fn vertex_main(
    @builtin(vertex_index) VertexIndex : u32
) -> VertexOutput {
    var pos = array<vec2<f32>, 6>(
        vec2<f32>( 0.5,  0.5),
        vec2<f32>(-0.5, -0.5),
        vec2<f32>( 0.5, -0.5),
        
        vec2<f32>(-0.5,  0.5),
        vec2<f32>(-0.5, -0.5),
        vec2<f32>( 0.5,  0.5)
    );
    var col = array<vec3<f32>, 6>(
        vec3<f32>(1,0,0),
        vec3<f32>(0,1,0),
        vec3<f32>(0,0,1),
        
        
        vec3<f32>(0,1,1),
        vec3<f32>(1,0,1),
        vec3<f32>(1,1,0),
    );

    var output : VertexOutput;
    output.Position = vec4<f32>(pos[VertexIndex], 0.0, 1.0);
    output.Color = col[VertexIndex];
    return output;
}

@fragment fn frag_main(@location(0) Color: vec3<f32>) -> @location(0) vec4<f32> {
    return vec4<f32>(Color, 1.0);
}
