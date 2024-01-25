const builtin = @import("builtin");
const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const m3d = @import("model3d");

const m = @import("math.zig");
const Model = @import("model.zig");
const Camera = @import("camera.zig");

pub const App = @This();

gpa: std.heap.GeneralPurposeAllocator(.{}),
allocator: std.mem.Allocator,

timer: core.Timer,
title_timer: core.Timer,

pipeline: *gpu.RenderPipeline,
pipieline_wireframe: *gpu.RenderPipeline,

vertex_buffer: *gpu.Buffer,
index_buffer: *gpu.Buffer,
uniform_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,

depth_texture: *gpu.Texture,
depth_texture_view: *gpu.TextureView,

model: Model,
camera: Camera,
prev_mouse_pos: core.Position,

wireframe_visible: bool = false,

const UniformBufferObject = struct {
    model: m.Mat4,
    view: m.Mat4,
    proj: m.Mat4,
    normal: m.Mat3,
    cam: m.Vec3,
};

pub const std_options = struct {
    pub const log_level = .debug;
};

pub fn init(app: *App) !void {
    try core.init(.{});

    app.gpa = .{};
    app.allocator = app.gpa.allocator();

    const model = try Model.load(app.allocator, "assets/test.obj");

    const bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(UniformBufferObject)),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, model.vertices.len * @sizeOf(Model.Vertex)),
            gpu.BindGroupLayout.Entry.buffer(2, .{ .vertex = true }, .read_only_storage, false, model.indices.len * @sizeOf(u32)),
        },
    }));
    defer bind_group_layout.release();
    const pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &.{bind_group_layout},
    }));
    defer pipeline_layout.release();

    const color_target_state: gpu.ColorTargetState = .{
        .format = core.descriptor.format,
        .blend = &.{},
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const depth_stencil_state: gpu.DepthStencilState = .{
        .format = .depth24_plus,
        .depth_write_enabled = .true,
        .depth_compare = .less,
    };

    const pipeline = b: {
        const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("shaders/shader.wgsl"));
        defer shader_module.release();

        break :b core.device.createRenderPipeline(&.{
            .label = "Solid Model Pipeline",
            .layout = pipeline_layout,
            .primitive = .{
                .cull_mode = if (builtin.mode == .Debug) .none else .back,
            },
            .fragment = &gpu.FragmentState.init(.{
                .module = shader_module,
                .entry_point = "frag_main",
                .targets = &.{color_target_state},
            }),
            .vertex = gpu.VertexState.init(.{
                .module = shader_module,
                .entry_point = "vertex_main",
                .buffers = &.{},
            }),
            .depth_stencil = &depth_stencil_state,
        });
    };

    const pipeline_wireframe = b: {
        const shader_module = core.device.createShaderModuleWGSL("wireframe.wgsl", @embedFile("shaders/wireframe.wgsl"));
        defer shader_module.release();

        break :b core.device.createRenderPipeline(&.{
            .label = "Wireframe Model Pipeline",
            .layout = pipeline_layout,
            .primitive = .{
                .topology = .line_list,
            },
            .fragment = &gpu.FragmentState.init(.{
                .module = shader_module,
                .entry_point = "frag_main",
                .targets = &.{color_target_state},
            }),
            .vertex = gpu.VertexState.init(.{
                .module = shader_module,
                .entry_point = "vertex_main",
                .buffers = &.{},
            }),
            .depth_stencil = &depth_stencil_state,
        });
    };

    const vertex_buffer = core.device.createBuffer(&.{
        .usage = .{ .vertex = true, .storage = true },
        .size = @sizeOf(Model.Vertex) * model.vertices.len,
        .mapped_at_creation = .true,
    });
    const vertex_mapped = vertex_buffer.getMappedRange(Model.Vertex, 0, model.vertices.len);
    std.mem.copyForwards(Model.Vertex, vertex_mapped.?, model.vertices);
    vertex_buffer.unmap();

    const index_buffer = core.device.createBuffer(&.{
        .usage = .{ .index = true, .storage = true },
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

    const bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = bind_group_layout,
        .entries = &.{
            gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
            gpu.BindGroup.Entry.buffer(1, vertex_buffer, 0, model.vertices.len * @sizeOf(Model.Vertex)),
            gpu.BindGroup.Entry.buffer(2, index_buffer, 0, model.indices.len * @sizeOf(u32)),
        },
    }));

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
        .pipieline_wireframe = pipeline_wireframe,

        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .uniform_buffer = uniform_buffer,
        .bind_group = bind_group,

        .depth_texture = depth_texture,
        .depth_texture_view = depth_texture_view,

        .model = model,
        .camera = Camera.init(90, 0, 0, m.vec3(0, 0, -5)),
        .prev_mouse_pos = .{ .x = 0, .y = 0 },
    };
    app.camera.pitch = 0;
    app.camera.yaw = -90;
    app.camera.updateVectors();
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
                    .one => core.setVSync(.none),
                    .two => core.setVSync(.double),
                    .three => core.setVSync(.triple),
                    .f3 => app.wireframe_visible = !app.wireframe_visible,

                    else => {},
                }
            },
            .mouse_press => |ev| {
                if (ev.button == .left) {
                    core.setCursorMode(.disabled);
                }
            },
            .mouse_release => |ev| {
                if (ev.button == .left) {
                    core.setCursorMode(.normal);
                }
            },
            .mouse_motion => |ev| {
                if (core.mousePressed(.left)) {
                    const delta: core.Position = .{
                        .x = ev.pos.x - app.prev_mouse_pos.x,
                        .y = ev.pos.y - app.prev_mouse_pos.y,
                    };
                    const camera_rotate_speed: f32 = 0.25;
                    app.camera.yaw -= @as(f32, @floatCast(delta.x)) * camera_rotate_speed;
                    app.camera.pitch -= @as(f32, @floatCast(delta.y)) * camera_rotate_speed;
                }
                app.prev_mouse_pos = ev.pos;
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

    // Camera movement
    const camera_move_speed: m.Vec3 = @splat(3 * core.delta_time);
    if (core.keyPressed(.w)) app.camera.position += app.camera.front * camera_move_speed;
    if (core.keyPressed(.s)) app.camera.position -= app.camera.front * camera_move_speed;
    if (core.keyPressed(.d)) app.camera.position += app.camera.right * camera_move_speed;
    if (core.keyPressed(.a)) app.camera.position -= app.camera.right * camera_move_speed;
    if (core.keyPressed(.space)) app.camera.position += Camera.world_up * camera_move_speed;
    if (core.keyPressed(.left_control)) app.camera.position -= Camera.world_up * camera_move_speed;
    if (core.keyPressed(.left)) app.camera.pitch -= 5;
    if (core.keyPressed(.right)) app.camera.pitch += 5;

    if (core.mousePressed(.left)) {}

    app.camera.pitch = @mod(app.camera.pitch, 360);
    app.camera.yaw = @mod(app.camera.yaw, 360);

    app.camera.updateVectors();

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
        const speed = 0.1;
        const time = app.timer.read();

        var ubo: UniformBufferObject = .{
            .model = m.mul(
                m.createRotateYMatrix(time * (std.math.pi * speed)),
                // m.mat4_ident,
                m.mat4_ident,
            ),
            .view = app.camera.getViewMatrix(),
            .proj = m.createPerspectiveMatrix(
                (std.math.pi / 4.0),
                @as(f32, @floatFromInt(core.descriptor.width)) / @as(f32, @floatFromInt(core.descriptor.height)),
                0.1,
                100,
            ),
            .normal = undefined,
            .cam = app.camera.position,
        };
        ubo.normal = m.mat3_from_mat4(m.transpose(m.inverse(ubo.model)));
        encoder.writeBuffer(app.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
    }

    const pass = encoder.beginRenderPass(&render_pass_info);

    pass.setPipeline(app.pipeline);
    pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Model.Vertex) * app.model.vertices.len);
    pass.setIndexBuffer(app.index_buffer, .uint32, 0, @sizeOf(u32) * app.model.indices.len);
    pass.setBindGroup(0, app.bind_group, &.{});
    pass.drawIndexed(@intCast(app.model.indices.len), 1, 0, 0, 0);

    if (app.wireframe_visible) {
        pass.setPipeline(app.pipieline_wireframe);
        pass.setVertexBuffer(0, app.vertex_buffer, 0, @sizeOf(Model.Vertex) * app.model.vertices.len);
        pass.setBindGroup(0, app.bind_group, &.{});
        pass.draw(@intCast(6 * app.model.indices.len), 1, 0, 0);
    }

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
