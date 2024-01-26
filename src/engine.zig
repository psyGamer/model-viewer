const builtin = @import("builtin");
const std = @import("std");
const core = @import("mach-core");
const gpu = core.gpu;
const m3d = @import("model3d");
const ecs = @import("ecs");

const m = @import("math");
const Model = @import("model.zig");
const Camera = @import("camera.zig");

const World = @import("main.zig").World;

const Module = ecs.Module(@This());

const UniformBufferObject = struct {
    model: m.Mat4,
    view: m.Mat4,
    proj: m.Mat4,
    normal: m.Mat3,
    cam: m.Vec3,
};

timer: core.Timer,
title_timer: core.Timer,

pipeline: *gpu.RenderPipeline,
pipieline_wireframe: *gpu.RenderPipeline,

uniform_buffer: *gpu.Buffer,
bind_group: *gpu.BindGroup,

depth_texture: *gpu.Texture,
depth_texture_view: *gpu.TextureView,

model: Model,
camera: Camera,
prev_mouse_pos: core.Position,

wireframe_visible: bool = false,

should_close: bool = false,

pub const name = .engine;
const log = std.log.scoped(name);

pub fn init(world: *World, allocator: std.mem.Allocator) !void {
    log.info("Initializing Engine...", .{});
    var engine = &world.mod.engine.state;

    const model = try Model.load(allocator, "assets/test.obj");

    const bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(UniformBufferObject)),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, model.vertex_count * @sizeOf(Model.Vertex)),
            gpu.BindGroupLayout.Entry.buffer(2, .{ .vertex = true }, .read_only_storage, false, model.index_count * @sizeOf(u32)),
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

    const uniform_buffer = core.device.createBuffer(&.{
        .usage = .{ .uniform = true, .copy_dst = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = .false,
    });

    const bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = bind_group_layout,
        .entries = &.{
            gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
            gpu.BindGroup.Entry.buffer(1, model.vertex_buffer, 0, model.vertex_count * @sizeOf(Model.Vertex)),
            gpu.BindGroup.Entry.buffer(2, model.index_buffer, 0, model.index_count * @sizeOf(u32)),
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

    engine.* = .{
        .timer = try core.Timer.start(),
        .title_timer = try core.Timer.start(),

        .pipeline = pipeline,
        .pipieline_wireframe = pipeline_wireframe,

        .uniform_buffer = uniform_buffer,
        .bind_group = bind_group,

        .depth_texture = depth_texture,
        .depth_texture_view = depth_texture_view,

        .model = model,
        .camera = Camera.init(90, 0, 0, m.vec3(0, 0, -5)),
        .prev_mouse_pos = .{ .x = 0, .y = 0 },
    };
    engine.camera.pitch = 0;
    engine.camera.yaw = -90;
    engine.camera.updateVectors();
}

pub fn deinit(world: *World, allocator: std.mem.Allocator) !void {
    log.info("Deinitializing Engine...", .{});
    var engine = world.mod.engine.state;

    engine.pipeline.release();
    engine.model.deinit(allocator);
}

pub fn update(world: *World) !void {
    var engine = &world.mod.engine.state;

    var iter = core.pollEvents();
    while (iter.next()) |event| {
        switch (event) {
            .key_press => |ev| {
                switch (ev.key) {
                    .one => core.setVSync(.none),
                    .two => core.setVSync(.double),
                    .three => core.setVSync(.triple),
                    .f3 => engine.wireframe_visible = !engine.wireframe_visible,

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
                        .x = ev.pos.x - engine.prev_mouse_pos.x,
                        .y = ev.pos.y - engine.prev_mouse_pos.y,
                    };
                    const camera_rotate_speed: f32 = 0.25;
                    engine.camera.yaw -= @as(f32, @floatCast(delta.x)) * camera_rotate_speed;
                    engine.camera.pitch -= @as(f32, @floatCast(delta.y)) * camera_rotate_speed;
                }
                engine.prev_mouse_pos = ev.pos;
            },
            .framebuffer_resize => |size| {
                engine.depth_texture.release();
                engine.depth_texture = core.device.createTexture(&gpu.Texture.Descriptor.init(.{
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

                engine.depth_texture_view.release();
                engine.depth_texture_view = engine.depth_texture.createView(&.{
                    .format = .depth24_plus,
                    .dimension = .dimension_2d,
                    .array_layer_count = 1,
                    .mip_level_count = 1,
                });
            },
            .close => {
                engine.should_close = true;
                return;
            },
            else => {},
        }
    }

    // Camera movement
    const camera_move_speed: m.Vec3 = @splat((@as(f32, if (core.keyPressed(.left_shift)) 10 else 3)) * core.delta_time);
    if (core.keyPressed(.w)) engine.camera.position += engine.camera.front * camera_move_speed;
    if (core.keyPressed(.s)) engine.camera.position -= engine.camera.front * camera_move_speed;
    if (core.keyPressed(.d)) engine.camera.position += engine.camera.right * camera_move_speed;
    if (core.keyPressed(.a)) engine.camera.position -= engine.camera.right * camera_move_speed;
    if (core.keyPressed(.space)) engine.camera.position += Camera.world_up * camera_move_speed;
    if (core.keyPressed(.left_control)) engine.camera.position -= Camera.world_up * camera_move_speed;
    if (core.keyPressed(.left)) engine.camera.pitch -= 5;
    if (core.keyPressed(.right)) engine.camera.pitch += 5;

    if (core.mousePressed(.left)) {}

    engine.camera.pitch = @mod(engine.camera.pitch, 360);
    engine.camera.yaw = @mod(engine.camera.yaw, 360);

    engine.camera.updateVectors();

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
            .view = engine.depth_texture_view,
            .depth_clear_value = 1.0,
            .depth_load_op = .clear,
            .depth_store_op = .store,
        },
    });

    {
        const speed = 0.1;
        const time = engine.timer.read();

        var ubo: UniformBufferObject = .{
            .model = m.mul(
                m.createRotateYMatrix(time * (std.math.pi * speed)),
                // m.mat4_ident,
                m.mat4_ident,
            ),
            .view = engine.camera.getViewMatrix(),
            .proj = m.createPerspectiveMatrix(
                (std.math.pi / 4.0),
                @as(f32, @floatFromInt(core.descriptor.width)) / @as(f32, @floatFromInt(core.descriptor.height)),
                0.1,
                100,
            ),
            .normal = undefined,
            .cam = engine.camera.position,
        };
        ubo.normal = m.mat3_from_mat4(m.transpose(m.inverse(ubo.model)));
        encoder.writeBuffer(engine.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
    }

    const pass = encoder.beginRenderPass(&render_pass_info);

    pass.setPipeline(engine.pipeline);
    pass.setVertexBuffer(0, engine.model.vertex_buffer, 0, @sizeOf(Model.Vertex) * engine.model.vertex_count);
    pass.setIndexBuffer(engine.model.index_buffer, .uint32, 0, @sizeOf(u32) * engine.model.index_count);
    pass.setBindGroup(0, engine.bind_group, &.{});
    pass.drawIndexed(@intCast(engine.model.index_count), 1, 0, 0, 0);

    if (engine.wireframe_visible) {
        pass.setPipeline(engine.pipieline_wireframe);
        pass.setVertexBuffer(0, engine.model.vertex_buffer, 0, @sizeOf(Model.Vertex) * engine.model.vertex_count);
        pass.setBindGroup(0, engine.bind_group, &.{});
        pass.draw(@intCast(6 * engine.model.index_count), 1, 0, 0);
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
    if (engine.title_timer.read() >= 1.0) {
        engine.title_timer.reset();
        try core.printTitle("Triangle [ {d}fps ] [ Input {d}hz ]", .{
            core.frameRate(),
            core.inputRate(),
        });
    }
}
