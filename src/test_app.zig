const std = @import("std");
const ecs = @import("ecs");

const TestApp = @This();

const Transform = @import("components/Transform.zig");
const Mesh = @import("components/Mesh.zig");
const model_loader = @import("util/model_loader.zig");

// Template to set up other modules. To be moved to somewhere else.
// pub fn init(allocator: std.mem.Allocator) !TestApp {
//     _ = allocator; // autofix
// }
// pub fn deinit(test_app: *TestApp, allocator: std.mem.Allocator) TestApp {
//     _ = test_app; // autofix
//     _ = allocator; // autofix
// }

// pub fn update(test_app: *TestApp, reg: *ecs.Registry, arena: std.mem.Allocator) !TestApp {
//     _ = test_app; // autofix
//     _ = reg; // autofix
//     _ = arena; // autofix
// }

// pub fn draw(test_app: *TestApp, reg: *ecs.Registry, arena: std.mem.Allocator) !TestApp {
//     _ = test_app; // autofix
//     _ = reg; // autofix
//     _ = arena; // autofix
// }

cubes: [4]ecs.Entity,
plane: ecs.Entity,

pub fn init(reg: *ecs.Registry, allocator: std.mem.Allocator) !TestApp {
    var test_app: TestApp = undefined;

    for (&test_app.cubes) |*cube| {
        cube.* = reg.create();
        try model_loader.loadModel(reg, cube.*, allocator, "assets/cube.m3d");
    }
    reg.add(test_app.cubes[0], Transform{
        .position = .{ 0, 0, 0 },
    });
    reg.add(test_app.cubes[1], Transform{
        .position = .{ 2, 4, 3 },
        .scale = .{ 3, 2, 1 },
    });
    reg.add(test_app.cubes[2], Transform{
        .position = .{ 6, 9, 4.20 },
        .rotation = .{ 30, 20, 10 },
    });
    reg.add(test_app.cubes[3], Transform{
        .position = .{ 2, 2, 2 },
        .scale = .{ 3, 2, 1 },
        .rotation = .{ 30, 20, 10 },
    });

    test_app.plane = reg.create();
    reg.add(test_app.plane, Transform{
        .position = .{ 0, 0, 0 },
        .scale = .{ 3, 3, 3 },
    });
    try model_loader.loadModel(reg, test_app.plane, allocator, "assets/plane.m3d");

    return test_app;
}
pub fn deinit(test_app: *TestApp, reg: *ecs.Registry, allocator: std.mem.Allocator) void {
    for (test_app.cubes) |cube| {
        reg.getConst(Mesh, cube).deinit(allocator);
    }
    reg.getConst(Mesh, test_app.plane).deinit(allocator);
}

pub fn update(test_app: *TestApp, reg: *ecs.Registry, arena: std.mem.Allocator) !void {
    _ = test_app; // autofix
    _ = reg; // autofix
    _ = arena; // autofix
}

pub fn draw(test_app: *TestApp, reg: *ecs.Registry, arena: std.mem.Allocator) !void {
    _ = test_app; // autofix
    _ = reg; // autofix
    _ = arena; // autofix
}
