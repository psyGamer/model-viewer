const std = @import("std");
const ecs = @import("ecs");
const m3d = @import("model3d");
const m = @import("math");
const c = @cImport({
    // NOTE: You need to have this installed under /usr/include
    // For some unknown reason, specifying it in build.zig doesnt work
    @cInclude("m3d.h");
});

const VertexWriter = @import("vertex_writer.zig").VertexWriter;

const Mesh = @import("../components/Mesh.zig");
const Material = @import("../components/material.zig").Material;
const log = std.log.scoped(.model_loader);

/// Loads the model and adds the required components to the entity.
pub fn loadModel(reg: *ecs.Registry, entity: ecs.Entity, allocator: std.mem.Allocator, path: []const u8) !void {
    log.info("Loading model: {s}", .{path});

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const data = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(data);

    log.debug("  Size: {} bytes", .{data.len});

    const extension = std.fs.path.extension(path);
    if (std.mem.eql(u8, extension, ".m3d"))
        try loadM3D(reg, entity, allocator, data)
    else if (std.mem.eql(u8, extension, ".obj"))
        // try loadOBJ(allocator, data)
        unreachable // TODO
    else {
        log.err("Unsupported model format: {s}", .{extension});
        return error.InvalidModelFormat;
    }
}

fn loadM3D(reg: *ecs.Registry, entity: ecs.Entity, allocator: std.mem.Allocator, data: [:0]const u8) !void {
    const m3d_model = m3d.load(data, null, null, null) orelse return error.LoadModel;

    const vertex_count = m3d_model.handle.numvertex;
    const face_count = m3d_model.handle.numface;

    const vertices = m3d_model.handle.vertex;
    const faces = m3d_model.handle.face;

    log.debug("  Vertices: {}", .{vertex_count});
    log.debug("  Faces: {}", .{face_count});

    var vertex_writer = try VertexWriter(Mesh.Vertex, u32).init(allocator, face_count * 3, vertex_count, face_count * 3);
    defer vertex_writer.deinit(allocator);

    for (0..face_count) |i| {
        const face = faces[i];
        for (0..3) |x| {
            const vertex_index = face.vertex[x];
            const normal_index = face.normal[x];
            const vertex: Mesh.Vertex = .{
                .position = .{ vertices[vertex_index].x, vertices[vertex_index].y, vertices[vertex_index].z },
                .normal = .{ vertices[normal_index].x, vertices[normal_index].y, vertices[normal_index].z },
            };
            vertex_writer.put(vertex, vertex_index);
        }
    }

    log.debug("  Packed Vertices: {}", .{vertex_writer.next_packed_index});
    log.debug("  Packed Indices: {}", .{vertex_writer.indices.len});

    reg.add(entity, Mesh.init(
        try allocator.dupe(Mesh.Vertex, vertex_writer.vertexBuffer()),
        try allocator.dupe(u32, vertex_writer.indexBuffer()),
    ));

    if (m3d_model.handle.nummaterial == 0) {
        // Use a default material
        reg.add(entity, Material{
            .diffuse_color = m.vec4_one,
            .ambiant_color = m.vec4_one,
            .specular_color = m.vec4_one,
            .specular_exponent = 32,
            .dissolve = 0,
            .roughness = 0.5,
            .metallic = 0,
            .index_of_refraction = 1,
        });
        return;
    }

    for (m3d_model.handle.material[0..m3d_model.handle.nummaterial]) |m3d_material| {
        log.debug("  - Name: {s}", .{m3d_material.name});

        var material: Material = undefined;
        for (m3d_material.prop[0..m3d_material.numprop]) |property| {
            switch (property.type) {
                c.m3dp_Kd => {
                    log.debug("    * Base Color: 0x{s}", .{std.fmt.fmtSliceHexUpper(std.mem.asBytes(&property.value.color))});
                    material.diffuse_color = packedColorToVec4(property.value.color);
                },
                c.m3dp_Ka => {
                    log.debug("    * Ambiant Color: 0x{s}", .{std.fmt.fmtSliceHexUpper(std.mem.asBytes(&property.value.color))});
                    material.ambiant_color = packedColorToVec4(property.value.color);
                },
                c.m3dp_Ks => {
                    log.debug("    * Specular Color: 0x{s}", .{std.fmt.fmtSliceHexUpper(std.mem.asBytes(&property.value.color))});
                    material.specular_color = packedColorToVec4(property.value.color);
                },
                c.m3dp_d => {
                    log.debug("    * Dissolve: {d}", .{property.value.fnum});
                    material.dissolve = property.value.fnum;
                },
                c.m3dp_il => {
                    log.debug("    * Illumination: {d}", .{property.value.num});
                    // TODO
                    // material.dissolve = property.value.fnum;
                },
                c.m3dp_Pr => {
                    log.debug("    * Roughness: {d}", .{property.value.fnum});
                    material.roughness = property.value.fnum;
                },
                c.m3dp_Pm => {
                    log.debug("    * Metallic: {d}", .{property.value.fnum});
                    material.metallic = property.value.fnum;
                },
                c.m3dp_Ni => {
                    log.debug("    * Index of Refaction: {d}", .{property.value.fnum});
                    material.index_of_refraction = property.value.fnum;
                },
                else => {
                    log.debug("    * {} = {}", .{ property.type, property.value });
                },
            }
        }

        reg.add(entity, material);
        break; // TODO: Support multiple materials?
    }
}

/// Converts a packed ABGR color into a float vector
fn packedColorToVec4(packed_color: u32) m.Vec4 {
    return .{
        @as(f32, @floatFromInt((packed_color & 0x000000FF) >> 0)) / 255.0,
        @as(f32, @floatFromInt((packed_color & 0x0000FF00) >> 8)) / 255.0,
        @as(f32, @floatFromInt((packed_color & 0x00FF0000) >> 16)) / 255.0,
        @as(f32, @floatFromInt((packed_color & 0xFF000000) >> 24)) / 255.0,
    };
}
