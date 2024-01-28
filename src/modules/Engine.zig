const builtin = @import("builtin");
const std = @import("std");
const core = @import("mach-core");
const ecs = @import("ecs");

const Engine = @This();

title_timer: core.Timer,

const log = std.log.scoped(.engine);

pub fn init(_: std.mem.Allocator) !Engine {
    log.info("Initializing Engine...", .{});
    return .{
        .title_timer = try core.Timer.start(),
    };
}

pub fn deinit(engine: *Engine, _: std.mem.Allocator) void {
    _ = engine; // autofix
    log.info("Deinitializing Engine...", .{});
}

pub fn handleEvent(engine: *Engine, event: core.Event) !void {
    _ = engine; // autofix
    switch (event) {
        .key_press => |ev| {
            switch (ev.key) {
                .one => core.setVSync(.none),
                .two => core.setVSync(.double),
                .three => core.setVSync(.triple),
                else => {},
            }
        },
        else => {},
    }
}

pub fn update(engine: *Engine, _: *ecs.Registry, _: std.mem.Allocator) !void {
    // Update the window title every second
    if (engine.title_timer.read() >= 1.0) {
        engine.title_timer.reset();
        try core.printTitle("Triangle [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }
}
