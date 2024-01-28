const m = @import("math");

pub const Material = extern struct {
    diffuse_color: m.Vec4,
    ambiant_color: m.Vec4,
    specular_color: m.Vec4,
    specular_exponent: f32,

    // emission_color: m.Vec3,
    // transmission_color: m.Vec3,

    // bump_strength: f32,
    dissolve: f32,

    roughness: f32,
    metallic: f32,
    // sheen: f32,
    index_of_refraction: f32,
    // thickness_of_face_mm: f32,

    // bump_map
    // normal_map
    // reflection_map
};
