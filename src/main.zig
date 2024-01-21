const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const zm = @import("zmath");

pub const App = @This();

timer: core.Timer,
title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
uniform_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,

depth_texture: *gpu.Texture,
depth_texture_view: *gpu.TextureView,

const Vertex = struct {
    pos: @Vector(3, f32),
    col: @Vector(3, f32) = .{ 1, 1, 1 },
};

// zig fmt: off
const cube_size = 0.25;
const vertices = [_]Vertex{
    .{ .pos = .{  cube_size,  cube_size, -cube_size }, .col = .{ 1.0, 0.0, 0.0 } }, // 0: Front Top Right
    .{ .pos = .{ -cube_size,  cube_size, -cube_size }, .col = .{ 0.0, 1.0, 0.0 } }, // 1: Front Top Left
    .{ .pos = .{  cube_size, -cube_size, -cube_size }, .col = .{ 0.0, 0.0, 1.0 } }, // 2: Front Bottom Right
    .{ .pos = .{ -cube_size, -cube_size, -cube_size }, .col = .{ 0.0, 1.0, 1.0 } }, // 3: Front Bottom Left
    .{ .pos = .{  cube_size,  cube_size,  cube_size }, .col = .{ 1.0, 0.0, 1.0 } }, // 4: Back Top Right
    .{ .pos = .{ -cube_size,  cube_size,  cube_size }, .col = .{ 1.0, 1.0, 0.0 } }, // 5: Back Top Left
    .{ .pos = .{  cube_size, -cube_size,  cube_size }, .col = .{ 0.0, 0.0, 0.0 } }, // 6: Back Bottom Right
    .{ .pos = .{ -cube_size, -cube_size,  cube_size }, .col = .{ 1.0, 1.0, 1.0 } }, // 7: Back Bottom Left
};
// zig fmt: on
const indices = [_]u32{
    // Front
    0, 3, 2,
    0, 1, 3,
    // Back
    4, 7, 6,
    4, 5, 7,
    // Left
    1, 7, 3,
    1, 5, 7,
    // Right
    0, 6, 2,
    0, 4, 6,
    // Top
    1, 0, 4,
    1, 4, 5,
    // Bottom
    3, 2, 6,
    3, 6, 7,
};

const UniformBufferObject = struct {
    mat: zm.Mat,
};

pub fn init(app: *App) !void {
    try core.init(.{});

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shaders/shader.wgsl"));
    defer shader_module.release();

    const vertex_attributes = [_]gpu.VertexAttribute{
        .{ .format = .float32x3, .offset = @offsetOf(Vertex, "pos"), .shader_location = 0 },
        .{ .format = .float32x3, .offset = @offsetOf(Vertex, "col"), .shader_location = 1 },
    };
    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Vertex),
        .attributes = &vertex_attributes,
    });

    // Fragment state
    const blend = gpu.BlendState{};
    const color_target = gpu.ColorTargetState{
        .format = core.descriptor.format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = shader_module,
        .entry_point = "frag_main",
        .targets = &.{color_target},
    });
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{ .fragment = &fragment, .vertex = gpu.VertexState.init(.{
        .module = shader_module,
        .entry_point = "vertex_main",
        .buffers = &.{vertex_buffer_layout},
    }), .depth_stencil = &.{
        .format = .depth24_plus,
        .depth_write_enabled = .true,
        .depth_compare = .less,
    } };
    const pipeline = core.device.createRenderPipeline(&pipeline_descriptor);

    const vertex_buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true },
        .size = @sizeOf(Vertex) * vertices.len,
        .mapped_at_creation = .true,
    });
    const vertex_mapped = vertex_buffer.getMappedRange(Vertex, 0, vertices.len);
    @memcpy(vertex_mapped.?, vertices[0..]);
    vertex_buffer.unmap();

    const index_buffer = core.device.createBuffer(&.{
        .usage = .{ .index = true },
        .size = @sizeOf(u32) * indices.len,
        .mapped_at_creation = .true,
    });
    const index_mapped = index_buffer.getMappedRange(u32, 0, indices.len);
    @memcpy(index_mapped.?, indices[0..]);
    index_buffer.unmap();

    const uniform_buffer = core.device.createBuffer(&.{
        .usage = .{ .uniform = true, .copy_dst = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = .false,
    });

    const bind_group_layout = pipeline.getBindGroupLayout(0);
    const bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = bind_group_layout,
        .entries = &.{
            gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
        },
    }));
    bind_group_layout.release();

    const depth_texture = core.device.createTexture(&gpu.Texture.Descriptor.init(.{
        .size = .{
            .width = core.descriptor.width,
            .height = core.descriptor.height,
        },
        .format = .depth24_plus,
        .usage = .{
            .render_attachment = true,
            .texture_binding = true,
        },
    }));
    const depth_texture_view = depth_texture.createView(&.{
        .format = .depth24_plus,
        .dimension = .dimension_2d,
        .array_layer_count = 1,
        .mip_level_count = 1,
    });

    app.* = .{
        .timer = try core.Timer.start(),
        .title_timer = try core.Timer.start(),
        .pipeline = pipeline,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .uniform_buffer = uniform_buffer,
        .bind_group = bind_group,

        .depth_texture = depth_texture,
        .depth_texture_view = depth_texture_view,
    };
}

pub fn deinit(app: *App) void {
    defer core.deinit();
    app.pipeline.release();
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .framebuffer_resize => |size| {
                app.depth_texture.release();
                app.depth_texture = core.device.createTexture(&gpu.Texture.Descriptor.init(.{
                    .size = .{
                        .width = size.width,
                        .height = size.height,
                    },
                    .format = .depth24_plus,
                    .usage = .{
                        .render_attachment = true,
                        .texture_binding = true,
                    },
                }));

                app.depth_texture_view.release();
                app.depth_texture_view = app.depth_texture.createView(&.{
                    .format = .depth24_plus,
                    .dimension = .dimension_2d,
                    .array_layer_count = 1,
                    .mip_level_count = 1,
                });
            },
            .close => return true,
            else => {},
        }
    }

    const queue = core.queue;
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = core.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = &.{
            .view = app.depth_texture_view,
            .depth_clear_value = 1.0,
            .depth_load_op = .clear,
            .depth_store_op = .store,
        },
    });

    {
        const time = app.timer.read();
        const model = zm.mul(zm.rotationX(time * (std.math.pi / 2.0)), zm.rotationZ(time * (std.math.pi / 2.0)));
        const view = zm.lookAtRh(
            zm.Vec{ 0, 4, 2, 1 },
            zm.Vec{ 0, 0, 0, 1 },
            zm.Vec{ 0, 0, 1, 0 },
        );
        const proj = zm.perspectiveFovRh(
            (std.math.pi / 4.0),
            @as(f32, @floatFromInt(core.descriptor.width)) / @as(f32, @floatFromInt(core.descriptor.height)),
            0.1,
            100,
        );
        const mvp = zm.mul(zm.mul(model, view), proj);
        const ubo = UniformBufferObject{
            .mat = zm.transpose(mvp),
        };
        encoder.writeBuffer(app.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
    }

    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Vertex) * vertices.len);
    pass.setIndexBuffer(app.index_buffer, .uint32, 0, @sizeOf(u32) * indices.len);
    pass.setBindGroup(0, app.bind_group, &.{});
    pass.drawIndexed(indices.len, 1, 0, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    queue.submit(&[_]*gpu.CommandBuffer{command});
    command.release();
    core.swap_chain.present();
    back_buffer_view.release();

    // update the window title every second
    if (app.title_timer.read() >= 1.0) {
        app.title_timer.reset();
        try core.printTitle("Triangle [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }

    return false;
}
