const m = @import("math");

pub const name = .common;
pub const components = struct {
    pub const position = m.Vec3;
    pub const rotation = m.Vec3;
    pub const scale = m.Vec3;
};
