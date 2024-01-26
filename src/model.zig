const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const zm = @import("zmath");
const m3d = @import("model3d");

const m = @import("math");
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

vertex_count: usize,
index_count: usize,
vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Model {
    std.log.info("Loading model: {s}", .{path});

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(data);

    std.log.debug("  Size: {} bytes", .{data.len});

    const extension = std.fs.path.extension(path);
    var vertex_writer = if (std.mem.eql(u8, extension, ".m3d"))
        try loadM3D(allocator, data)
    else if (std.mem.eql(u8, extension, ".obj"))
        try loadOBJ(allocator, data)
    else {
        std.log.err("Unsupported model format: {s}", .{extension});
        return error.InvalidModelFormat;
    };
    defer vertex_writer.deinit(allocator);

    const vertices = vertex_writer.vertexBuffer();
    const indices = vertex_writer.indexBuffer();

    const vertex_buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true, .storage = true },
        .size = @sizeOf(Vertex) * vertices.len,
        .mapped_at_creation = .true,
    });
    const vertex_mapped = vertex_buffer.getMappedRange(Model.Vertex, 0, vertices.len).?;
    @memcpy(vertex_mapped, vertices);
    // std.mem.copyForwards(Vertex, vertex_mapped, vertices);
    vertex_buffer.unmap();

    const index_buffer = core.device.createBuffer(&.{
        .usage = .{ .index = true, .storage = true },
        .size = @sizeOf(u32) * indices.len,
        .mapped_at_creation = .true,
    });
    const index_mapped = index_buffer.getMappedRange(u32, 0, indices.len).?;
    @memcpy(index_mapped, indices);
    // std.mem.copyForwards(u32, index_mapped, indices);
    index_buffer.unmap();

    return .{
        .vertex_count = vertices.len,
        .index_count = indices.len,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
    };
}

fn loadM3D(allocator: std.mem.Allocator, data: [:0]const u8) !VertexWriter(Vertex, u32) {
    const m3d_model = m3d.load(data, null, null, null) orelse return error.LoadModel;

    const vertex_count = m3d_model.handle.numvertex;
    const face_count = m3d_model.handle.numface;

    const vertices = m3d_model.handle.vertex;
    const faces = m3d_model.handle.face;

    std.log.debug("  Vertices: {}", .{vertex_count});
    std.log.debug("  Faces: {}", .{face_count});

    var vertex_writer = try VertexWriter(Vertex, u32).init(allocator, face_count * 3, vertex_count, face_count * 3);

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

    return vertex_writer;
}

fn loadOBJ(allocator: std.mem.Allocator, data: [:0]const u8) !VertexWriter(Vertex, u32) {
    const Node = struct {
        vertex_index: u32,
        texture_index: u32,
        normal_index: u32,
    };

    var vertices = std.ArrayList(m.Vec3).init(allocator);
    defer vertices.deinit();
    var textures = std.ArrayList(m.Vec2).init(allocator);
    defer textures.deinit();
    var normals = std.ArrayList(m.Vec3).init(allocator);
    defer normals.deinit();
    var faces = std.ArrayList([3]Node).init(allocator);
    defer faces.deinit();

    var iter = std.mem.tokenizeAny(u8, data, "\n\r");
    while (iter.next()) |line| {
        // Comment
        if (line[0] == '#') continue;

        var command_iter = std.mem.splitScalar(u8, line, ' ');
        const command = command_iter.next().?;

        // Vertex
        if (std.mem.eql(u8, command, "v")) {
            try vertices.append(.{
                try std.fmt.parseFloat(f32, command_iter.next().?),
                try std.fmt.parseFloat(f32, command_iter.next().?),
                try std.fmt.parseFloat(f32, command_iter.next().?),
            });

            std.debug.assert(command_iter.next() == null);
        }
        // Vertex UV
        if (std.mem.eql(u8, command, "vt")) {
            try textures.append(.{
                try std.fmt.parseFloat(f32, command_iter.next().?),
                try std.fmt.parseFloat(f32, command_iter.next().?),
            });

            std.debug.assert(command_iter.next() == null);
        }
        // Vertex Normal
        if (std.mem.eql(u8, command, "vn")) {
            try normals.append(.{
                try std.fmt.parseFloat(f32, command_iter.next().?),
                try std.fmt.parseFloat(f32, command_iter.next().?),
                try std.fmt.parseFloat(f32, command_iter.next().?),
            });

            std.debug.assert(command_iter.next() == null);
        }
        // Face
        if (std.mem.eql(u8, command, "f")) {
            var face: [3]Node = undefined;
            for (0..3) |face_idx| {
                var inner_count: u8 = 0;
                var element_iter = std.mem.splitScalar(u8, command_iter.next().?, '/');
                while (element_iter.next()) |element| : (inner_count += 1) {
                    if (element.len == 0) continue;

                    const idx = try std.fmt.parseInt(u32, element, 10);
                    switch (inner_count) {
                        0 => face[face_idx].vertex_index = idx,
                        1 => face[face_idx].texture_index = idx,
                        2 => face[face_idx].normal_index = idx,
                        else => unreachable,
                    }
                }
            }
            try faces.append(face);

            std.debug.assert(command_iter.next() == null);
        }
        // Line
        if (std.mem.eql(u8, command, "l")) continue; // TODO
        // Group
        if (std.mem.eql(u8, command, "g")) continue; // TODO
        // Object
        if (std.mem.eql(u8, command, "o")) continue; // TODO
        // Smooth Shading
        if (std.mem.eql(u8, command, "s")) continue; // TODO

        // mtllib
        if (std.mem.eql(u8, command, "mtllib")) continue; // TODO
        // usemtl
        if (std.mem.eql(u8, command, "usemtl")) continue; // TODO
    }

    std.log.debug("  Vertices: {}", .{vertices.items.len});
    std.log.debug("  Texture Coords: {}", .{textures.items.len});
    std.log.debug("  Normals: {}", .{normals.items.len});
    std.log.debug("  Faces: {}", .{faces.items.len});

    var vertex_writer = try VertexWriter(Vertex, u32).init(allocator, @intCast(faces.items.len * 3), @intCast(vertices.items.len), @intCast(faces.items.len * 3));

    for (faces.items) |face| {
        for (0..3) |x| {
            const vertex_index = face[x].vertex_index;
            const normal_index = face[x].normal_index;
            const vertex: Vertex = .{
                // Why are OBJ models 1 indexed...
                .position = vertices.items[vertex_index - 1],
                .normal = normals.items[normal_index - 1],
            };
            vertex_writer.put(vertex, vertex_index);
        }
    }

    std.log.debug("  Packed Vertices: {}", .{vertex_writer.next_packed_index});
    std.log.debug("  Packed Indices: {}", .{vertex_writer.indices.len});

    return vertex_writer;
}

pub fn deinit(model: Model, allocator: std.mem.Allocator) void {
    _ = allocator; // autofix
    model.vertex_buffer.release();
    model.index_buffer.release();
}
