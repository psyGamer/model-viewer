const builtin = @import("builtin");
const std = @import("std");
const ecs = @import("ecs");
const core = @import("mach-core");
const gpu = core.gpu;
const m = @import("math");

const Camera = @import("../camera.zig");

const Transform = @import("../components/Transform.zig");
const Mesh = @import("../components/Mesh.zig");
const Material = @import("../components/material.zig").Material;

const Engine = @import("engine");
const MeshRenderer = @This();

const log = std.log.scoped(.mesh_renderer);

const MeshCache = struct {
    vertex_buffers: [@typeInfo(Mesh.Vertex).Struct.fields.len]*gpu.Buffer,
    index_buffer: *gpu.Buffer,
    uniform_buffer: *gpu.Buffer,
    material_buffer: *gpu.Buffer,
    bind_group: *gpu.BindGroup,
};
const MeshCacheMap = std.HashMap(Mesh, MeshCache, Mesh.HashmapContext, std.hash_map.default_max_load_percentage);

const UniformBufferObject = extern struct {
    model: m.Mat4,
    view: m.Mat4,
    proj: m.Mat4,
    normal: m.Mat3,
    cam: m.Vec3,
};

pipeline: *gpu.RenderPipeline,
pipieline_wireframe: *gpu.RenderPipeline,

depth_texture: *gpu.Texture,
depth_texture_view: *gpu.TextureView,

bind_group_layout: *gpu.BindGroupLayout,
mesh_cache: MeshCacheMap,

// TODO: Should this be part of MeshRenderer? Probably not..
camera: Camera,
prev_mouse_pos: core.Position,
wireframe_visible: bool,

pub fn init(allocator: std.mem.Allocator) !MeshRenderer {
    log.info("Initializing Mesh Renderer...", .{});

    comptime var entries: []const gpu.BindGroupLayout.Entry = &.{
        gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(UniformBufferObject)),
        gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(Material)),
        gpu.BindGroupLayout.Entry.buffer(2, .{ .vertex = true }, .read_only_storage, false, @sizeOf(u32)),
    };
    inline for (@typeInfo(Mesh.Vertex).Struct.fields) |field| {
        entries = entries ++ comptime [_]gpu.BindGroupLayout.Entry{
            gpu.BindGroupLayout.Entry.buffer(entries.len, .{ .vertex = true }, .read_only_storage, false, @sizeOf(field.type)),
        };
    }
    const bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .entries = entries,
    }));

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

    const file = try std.fs.cwd().openFile("assets/internal/shaders/mesh.wgsl", .{});
    defer file.close();

    const data = try file.readToEndAllocOptions(allocator, std.math.maxInt(usize), null, @alignOf(u8), 0);
    defer allocator.free(data);

    const pipeline = b: {
        const shader_module = core.device.createShaderModuleWGSL("Solid Mesh", data);
        defer shader_module.release();

        break :b core.device.createRenderPipeline(&.{
            .label = "Solid Mesh Renderer",
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
        const shader_module = core.device.createShaderModuleWGSL("Wireframe Mesh", data);
        defer shader_module.release();

        break :b core.device.createRenderPipeline(&.{
            .label = "Wireframe Mesh Renderer",
            .layout = pipeline_layout,
            .primitive = .{
                .topology = .line_list,
            },
            .fragment = &gpu.FragmentState.init(.{
                .module = shader_module,
                .entry_point = "frag_main_wireframe",
                .targets = &.{color_target_state},
            }),
            .vertex = gpu.VertexState.init(.{
                .module = shader_module,
                .entry_point = "vertex_main_wireframe",
                .buffers = &.{},
            }),
            .depth_stencil = &depth_stencil_state,
        });
    };

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

    return .{
        .pipeline = pipeline,
        .pipieline_wireframe = pipeline_wireframe,

        .depth_texture = depth_texture,
        .depth_texture_view = depth_texture_view,

        .bind_group_layout = bind_group_layout,
        .mesh_cache = MeshCacheMap.init(allocator),

        .camera = b: {
            var cam = Camera.init(90, 0, 0, m.vec3(0, 0, -5));
            cam.pitch = 0;
            cam.yaw = -90;
            cam.updateVectors();
            break :b cam;
        },
        .prev_mouse_pos = .{ .x = 0, .y = 0 },
        .wireframe_visible = false,
    };
}

pub fn deinit(mesh_renderer: *MeshRenderer) void {
    log.info("Deinitializing Mesh Renderer...", .{});

    mesh_renderer.pipeline.release();
    mesh_renderer.pipieline_wireframe.release();

    mesh_renderer.depth_texture.destroy();
    mesh_renderer.depth_texture.release();
    mesh_renderer.depth_texture_view.release();

    // TODO: Figure out why this segfaults
    // mesh_renderer.bind_group_layout.release();

    var iter = mesh_renderer.mesh_cache.valueIterator();
    while (iter.next()) |cache| {
        inline for (0..@typeInfo(Mesh.Vertex).Struct.fields.len) |i| {
            cache.vertex_buffers[i].destroy();
            cache.vertex_buffers[i].release();
        }

        cache.index_buffer.destroy();
        cache.uniform_buffer.destroy();

        cache.index_buffer.release();
        cache.bind_group.release();
    }
    mesh_renderer.mesh_cache.deinit();
}

pub fn handleEvent(mesh_renderer: *MeshRenderer, event: core.Event) void {
    switch (event) {
        .key_press => |ev| {
            switch (ev.key) {
                .f3 => mesh_renderer.wireframe_visible = !mesh_renderer.wireframe_visible,
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
                    .x = ev.pos.x - mesh_renderer.prev_mouse_pos.x,
                    .y = ev.pos.y - mesh_renderer.prev_mouse_pos.y,
                };
                const camera_rotate_speed: f32 = 0.25;
                mesh_renderer.camera.yaw -= @as(f32, @floatCast(delta.x)) * camera_rotate_speed;
                mesh_renderer.camera.pitch -= @as(f32, @floatCast(delta.y)) * camera_rotate_speed;
            }
            mesh_renderer.prev_mouse_pos = ev.pos;
        },
        .framebuffer_resize => |size| {
            mesh_renderer.depth_texture.destroy();
            mesh_renderer.depth_texture.release();
            mesh_renderer.depth_texture = core.device.createTexture(&gpu.Texture.Descriptor.init(.{
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

            mesh_renderer.depth_texture_view.release();
            mesh_renderer.depth_texture_view = mesh_renderer.depth_texture.createView(&.{
                .format = .depth24_plus,
                .dimension = .dimension_2d,
                .array_layer_count = 1,
                .mip_level_count = 1,
            });
        },
        else => {},
    }
}

pub fn update(mesh_renderer: *MeshRenderer, _: *Engine) !void {
    // Camera movement
    const camera_move_speed: m.Vec3 = @splat((@as(f32, if (core.keyPressed(.f)) 10 else 3)) * core.delta_time);
    if (core.keyPressed(.w)) mesh_renderer.camera.position += mesh_renderer.camera.front * camera_move_speed;
    if (core.keyPressed(.s)) mesh_renderer.camera.position -= mesh_renderer.camera.front * camera_move_speed;
    if (core.keyPressed(.d)) mesh_renderer.camera.position += mesh_renderer.camera.right * camera_move_speed;
    if (core.keyPressed(.a)) mesh_renderer.camera.position -= mesh_renderer.camera.right * camera_move_speed;
    if (core.keyPressed(.space)) mesh_renderer.camera.position += Camera.world_up * camera_move_speed;
    if (core.keyPressed(.left_control)) mesh_renderer.camera.position -= Camera.world_up * camera_move_speed;
    if (core.keyPressed(.left)) mesh_renderer.camera.pitch -= 5;
    if (core.keyPressed(.right)) mesh_renderer.camera.pitch += 5;

    if (core.mousePressed(.left)) {}

    mesh_renderer.camera.yaw = @mod(mesh_renderer.camera.yaw, 360);
    mesh_renderer.camera.pitch = std.math.clamp(mesh_renderer.camera.pitch, -89.9, 89.9);
    mesh_renderer.camera.updateVectors();
}

pub fn draw(mesh_renderer: *MeshRenderer, engine: *Engine) !void {
    const back_buffer_view = core.swap_chain.getCurrentTextureView().?;
    defer back_buffer_view.release();

    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
        .depth_stencil_attachment = &.{
            .view = mesh_renderer.depth_texture_view,
            .depth_clear_value = 1.0,
            .depth_load_op = .clear,
            .depth_store_op = .store,
        },
    });

    const encoder = core.device.createCommandEncoder(null);
    defer encoder.release();

    // Update all mesh caches as required
    var view = engine.reg.view(.{ Transform, Mesh, Material }, .{});
    var iter = view.entityIterator();
    while (iter.next()) |entity| {
        const transform = view.getConst(Transform, entity);
        const mesh = view.getConst(Mesh, entity);
        const material = view.getConst(Material, entity);

        var ubo: UniformBufferObject = .{
            .model = m.batchMul(.{
                m.createScaleMatrix(transform.scale[0], transform.scale[1], transform.scale[2]),

                m.createRotateXMatrix(transform.rotation[0]),
                m.createRotateYMatrix(transform.rotation[1]),
                m.createRotateZMatrix(transform.rotation[2]),

                m.createTranslationMatrix(transform.position),
            }),
            .view = mesh_renderer.camera.getViewMatrix(),
            .proj = m.createPerspectiveMatrix(
                (std.math.pi / 4.0),
                @as(f32, @floatFromInt(core.descriptor.width)) / @as(f32, @floatFromInt(core.descriptor.height)),
                0.1,
                100,
            ),
            .normal = undefined,
            .cam = mesh_renderer.camera.position,
        };
        ubo.normal = m.mat3_from_mat4(m.transpose(m.inverse(ubo.model)));

        // Create vertex/index/uniform buffers for a mesh, if they don't already exist
        const gop = try mesh_renderer.mesh_cache.getOrPut(mesh);
        var mesh_cache: *MeshCache = gop.value_ptr;
        if (!gop.found_existing) {
            inline for (@typeInfo(Mesh.Vertex).Struct.fields, 0..) |field, i| {
                mesh_cache.vertex_buffers[i] = core.device.createBuffer(&.{
                    .usage = .{ .vertex = true, .storage = true },
                    .size = mesh.vertices.len * @sizeOf(field.type),
                    .mapped_at_creation = .true,
                });
                const vertex_mapped = mesh_cache.vertex_buffers[i].getMappedRange(field.type, 0, mesh.vertices.len).?;
                // Can't memcpy, because the source is still an array-of-structs
                // @memcpy(vertex_mapped, mesh.vertices);
                for (mesh.vertices, vertex_mapped) |vertex, *mapped| {
                    mapped.* = @field(vertex, field.name);
                }
                mesh_cache.vertex_buffers[i].unmap();
            }

            mesh_cache.index_buffer = core.device.createBuffer(&.{
                .usage = .{ .index = true, .storage = true },
                .size = mesh.indices.len * @sizeOf(u32),
                .mapped_at_creation = .true,
            });
            const index_mapped = mesh_cache.index_buffer.getMappedRange(u32, 0, mesh.indices.len).?;
            @memcpy(index_mapped, mesh.indices);
            mesh_cache.index_buffer.unmap();

            mesh_cache.uniform_buffer = core.device.createBuffer(&.{
                .usage = .{ .uniform = true, .copy_dst = true },
                .size = @sizeOf(UniformBufferObject),
                .mapped_at_creation = .true,
            });
            const uniform_mapped = mesh_cache.uniform_buffer.getMappedRange(UniformBufferObject, 0, 1).?;
            @memcpy(uniform_mapped, &[_]UniformBufferObject{ubo});
            mesh_cache.uniform_buffer.unmap();

            mesh_cache.material_buffer = core.device.createBuffer(&.{
                .usage = .{ .uniform = true, .copy_dst = true },
                .size = @sizeOf(Material),
                .mapped_at_creation = .true,
            });
            const material_mapped = mesh_cache.material_buffer.getMappedRange(Material, 0, 1).?;
            @memcpy(material_mapped, &[_]Material{material});
            mesh_cache.material_buffer.unmap();

            var entries: [3 + @typeInfo(Mesh.Vertex).Struct.fields.len]gpu.BindGroup.Entry = undefined;
            entries[0] = gpu.BindGroup.Entry.buffer(0, mesh_cache.uniform_buffer, 0, @sizeOf(UniformBufferObject));
            entries[1] = gpu.BindGroup.Entry.buffer(1, mesh_cache.material_buffer, 0, @sizeOf(Material));
            entries[2] = gpu.BindGroup.Entry.buffer(2, mesh_cache.index_buffer, 0, mesh.indices.len * @sizeOf(u32));
            inline for (@typeInfo(Mesh.Vertex).Struct.fields, 0..) |field, i| {
                entries[3 + i] = gpu.BindGroup.Entry.buffer(3 + i, mesh_cache.vertex_buffers[i], 0, mesh.vertices.len * @sizeOf(field.type));
            }
            mesh_cache.bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
                .layout = mesh_renderer.bind_group_layout,
                .entries = &entries,
            }));
        } else {
            // Update existing uniform buffer
            encoder.writeBuffer(mesh_cache.uniform_buffer, 0, &[_]UniformBufferObject{ubo});
        }
    }

    const pass = encoder.beginRenderPass(&render_pass_info);
    defer pass.release();

    // Render all solid meshes
    pass.setPipeline(mesh_renderer.pipeline);
    iter.reset();
    while (iter.next()) |entity| {
        const mesh = view.getConst(Mesh, entity);
        const mesh_cache = mesh_renderer.mesh_cache.get(mesh).?; // Must exist, see above
        pass.setBindGroup(0, mesh_cache.bind_group, &.{});
        pass.draw(@intCast(mesh.indices.len), 1, 0, 0);
    }

    // Render wireframes
    if (mesh_renderer.wireframe_visible) {
        pass.setPipeline(mesh_renderer.pipieline_wireframe);
        iter.reset();
        while (iter.next()) |entity| {
            const mesh = view.getConst(Mesh, entity);
            const mesh_cache = mesh_renderer.mesh_cache.get(mesh).?; // Must exist, see above
            pass.setBindGroup(0, mesh_cache.bind_group, &.{});
            pass.draw(@intCast(6 * mesh.indices.len), 1, 0, 0);
        }
    }

    pass.end();

    const command = encoder.finish(null);
    defer command.release();

    core.queue.submit(&.{command});
}
