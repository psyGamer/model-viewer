struct Uniforms {
  modelViewProjectionMatrix : mat4x4<f32>,
};
@binding(0) @group(0) var<uniform> uniforms : Uniforms;

struct VertexOutput {
    @builtin(position) Position : vec4<f32>,
    @location(0) Color : vec3<f32>,
};

@vertex fn vertex_main(
    @location(0) pos : vec3<f32>,
    @location(1) col : vec3<f32>,
) -> VertexOutput {
    var output : VertexOutput;
    output.Position = vec4<f32>(pos, 1.0) * uniforms.modelViewProjectionMatrix;
    output.Color = col;
    return output;
}

@fragment fn frag_main(@location(0) Color: vec3<f32>) -> @location(0) vec4<f32> {
    return vec4<f32>(Color, 1.0);
}