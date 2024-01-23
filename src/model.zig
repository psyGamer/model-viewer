const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const zm = @import("zmath");
const m3d = @import("model3d");

const VertexWriter = @import("vertex_writer.zig").VertexWriter;

const Model = @This();
pub const Vertex = struct {
    position: @Vector(3, f32),
    normal: @Vector(3, f32),

    pub const vertex_attributes = b: {
        var attrs: []const gpu.VertexAttribute = &.{};

        const info = @typeInfo(Vertex).Struct;
        for (info.fields, 0..) |f, i| {
            const format: gpu.VertexFormat = switch (f.type) {
                f32 => .float32,
                @Vector(2, f32) => .float32x2,
                @Vector(3, f32) => .float32x3,
                @Vector(4, f32) => .float32x4,
                else => @compileError("Invalid vertex attribute type: " ++ @typeName(f.type)),
            };

            const attribute: []const gpu.VertexAttribute = &.{.{ .format = format, .offset = @offsetOf(Vertex, f.name), .shader_location = i }};
            attrs = attrs ++ attribute;
        }

        break :b attrs;
    };
};

vertices: []Vertex,
indices: []u32,

pub fn loadM3D(allocator: std.mem.Allocator, path: [:0]const u8) !Model {
    std.log.info("Loading model: {s}", .{path});

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(data);

    std.log.debug("  Size: {} bytes", .{data.len});

    const m3d_model = m3d.load(data, null, null, null) orelse return error.LoadModel;

    const vertex_count = m3d_model.handle.numvertex;
    const face_count = m3d_model.handle.numface;

    const vertices = m3d_model.handle.vertex;
    const faces = m3d_model.handle.face;

    std.log.debug("  Vertices: {}", .{vertex_count});
    std.log.debug("  Faces: {}", .{face_count});

    var vertex_writer = try VertexWriter(Vertex, u32).init(allocator, face_count * 3, vertex_count, face_count * 3);
    defer vertex_writer.deinit(allocator);

    for (0..face_count) |i| {
        const face = faces[i];
        for (0..3) |x| {
            const vertex_index = face.vertex[x];
            const normal_index = face.normal[x];
            const vertex: Vertex = .{
                .position = .{ vertices[vertex_index].x, vertices[vertex_index].y, vertices[vertex_index].z },
                .normal = .{ vertices[normal_index].x, vertices[normal_index].y, vertices[normal_index].z },
            };
            vertex_writer.put(vertex, vertex_index);
        }
    }

    std.log.debug("  Packed Vertices: {}", .{vertex_writer.next_packed_index});
    std.log.debug("  Packed Indices: {}", .{vertex_writer.indices.len});

    return .{
        .vertices = try allocator.dupe(Vertex, vertex_writer.vertexBuffer()),
        .indices = try allocator.dupe(u32, vertex_writer.indexBuffer()),
    };
}

pub fn deinit(model: Model, allocator: std.mem.Allocator) void {
    allocator.free(model.vertices);
    allocator.free(model.indices);
}
