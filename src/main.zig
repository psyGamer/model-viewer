const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const zm = @import("zmath");
const m3d = @import("model3d");

const Model = @import("model.zig");

pub const App = @This();

gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,

timer: core.Timer,
title_timer: core.Timer,
pipeline: *gpu.RenderPipeline,

model: Model,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
uniform_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,

depth_texture: *gpu.Texture,
depth_texture_view: *gpu.TextureView,

const UniformBufferObject = struct {
    mat: zm.Mat,
};

pub fn init(app: *App) !void {
    try core.init(.{});

    app.gpa = .{};
    app.allocator = app.gpa.allocator();

    const model = try Model.loadM3D(app.allocator, "assets/test.m3d");

    const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shaders/shader.wgsl"));
    defer shader_module.release();

    const vertex_buffer_layout = gpu.VertexBufferLayout.init(.{
        .array_stride = @sizeOf(Model.Vertex),
        .attributes = Model.Vertex.vertex_attributes,
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
        .size = @sizeOf(Model.Vertex) * model.vertices.len,
        .mapped_at_creation = .true,
    });
    const vertex_mapped = vertex_buffer.getMappedRange(Model.Vertex, 0, model.vertices.len);
    std.mem.copyForwards(Model.Vertex, vertex_mapped.?, model.vertices);
    vertex_buffer.unmap();

    const index_buffer = core.device.createBuffer(&.{
        .usage = .{ .index = true },
        .size = @sizeOf(u32) * model.indices.len,
        .mapped_at_creation = .true,
    });
    const index_mapped = index_buffer.getMappedRange(u32, 0, model.indices.len);
    std.mem.copyForwards(u32, index_mapped.?, model.indices);
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
        .gpa = app.gpa,
        .allocator = app.allocator,

        .timer = try core.Timer.start(),
        .title_timer = try core.Timer.start(),
        .pipeline = pipeline,

        .model = model,

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
    app.model.deinit(app.allocator);
    std.debug.assert(app.gpa.detectLeaks() == false);
}

pub fn update(app: *App) !bool {
    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .space => return true,
                    .one => core.setVSync(.none),
                    .two => core.setVSync(.double),
                    .three => core.setVSync(.triple),
                    else => {},
                }
                std.debug.print("vsync mode changed to {s}\n", .{@tagName(core.vsync())});
            },
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
        const speed = 0.5;

        const time = app.timer.read();
        const model = zm.mul(zm.rotationX(time * (std.math.pi * speed)), zm.rotationZ(time * (std.math.pi * speed)));
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
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Model.Vertex) * app.model.vertices.len);
    pass.setIndexBuffer(app.index_buffer, .uint32, 0, @sizeOf(u32) * app.model.indices.len);
    pass.setBindGroup(0, app.bind_group, &.{});
    pass.drawIndexed(@intCast(app.model.indices.len), 1, 0, 0, 0);
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
