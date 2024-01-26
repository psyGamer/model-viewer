const builtin = @import("builtin");
const std = @import("std");
const ecs = @import("ecs");
const core = @import("mach-core");
const gpu = core.gpu;
const m = @import("math");

const Camera = @import("../camera.zig");

const Transform = @import("../components/Transform.zig");
const Mesh = @import("../components/Mesh.zig");

const World = @import("Engine.zig").World;
const MeshRenderer = ecs.Module(@This());

pub const name = .mesh_renderer;
pub const components = struct {
    pub const transform = Transform;
    pub const mesh = Mesh;
};
const log = std.log.scoped(name);

fn self(world: *World) *@This() {
    return @ptrCast(&@field(world.mod, @tagName(name)).state);
}

const MeshCache = struct {
    vertex_buffer: *gpu.Buffer,
    index_buffer: *gpu.Buffer,
    bind_group: *gpu.BindGroup,
};
const MeshCacheMap = std.HashMap(Mesh, MeshCache, Mesh.HashmapContext, std.hash_map.default_max_load_percentage);

const UniformBufferObject = struct {
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

uniform_buffer: *gpu.Buffer,
uniform_bind_group: *gpu.BindGroup,
mesh_bind_group_layout: *gpu.BindGroupLayout,
mesh_cache: MeshCacheMap,

camera: Camera,
wireframe_visible: bool = false,

pub fn init(world: *World, allocator: std.mem.Allocator) !void {
    log.info("Initializing Mesh Renderer...", .{});
    const mesh_renderer = self(world);

    const uniform_bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true, .fragment = true }, .uniform, false, @sizeOf(UniformBufferObject)),
        },
    }));
    defer uniform_bind_group_layout.release();
    const mesh_bind_group_layout = core.device.createBindGroupLayout(&gpu.BindGroupLayout.Descriptor.init(.{
        .entries = &.{
            gpu.BindGroupLayout.Entry.buffer(0, .{ .vertex = true }, .read_only_storage, false, @sizeOf(Mesh.Vertex)),
            gpu.BindGroupLayout.Entry.buffer(1, .{ .vertex = true }, .read_only_storage, false, @sizeOf(u32)),
        },
    }));

    const pipeline_layout = core.device.createPipelineLayout(&gpu.PipelineLayout.Descriptor.init(.{
        .bind_group_layouts = &.{ uniform_bind_group_layout, mesh_bind_group_layout },
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
        const shader_module = core.device.createShaderModuleWGSL("shader.wgsl", @embedFile("../shaders/shader.wgsl"));
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
        const shader_module = core.device.createShaderModuleWGSL("wireframe.wgsl", @embedFile("../shaders/wireframe.wgsl"));
        defer shader_module.release();

        break :b core.device.createRenderPipeline(&.{
            .label = "Wireframe Mesh Renderer",
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

    const uniform_buffer = core.device.createBuffer(&.{
        .usage = .{ .uniform = true, .copy_dst = true },
        .size = @sizeOf(UniformBufferObject),
        .mapped_at_creation = .false,
    });
    const uniform_bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
        .layout = uniform_bind_group_layout,
        .entries = &.{
            gpu.BindGroup.Entry.buffer(0, uniform_buffer, 0, @sizeOf(UniformBufferObject)),
        },
    }));

    mesh_renderer.* = .{
        .pipeline = pipeline,
        .pipieline_wireframe = pipeline_wireframe,

        .depth_texture = depth_texture,
        .depth_texture_view = depth_texture_view,

        .uniform_buffer = uniform_buffer,
        .uniform_bind_group = uniform_bind_group,
        .mesh_bind_group_layout = mesh_bind_group_layout,
        .mesh_cache = MeshCacheMap.init(allocator),

        .camera = Camera.init(90, 0, 0, m.vec3(0, 0, -5)),
    };

    mesh_renderer.camera.pitch = 0;
    mesh_renderer.camera.yaw = -90;
    mesh_renderer.camera.updateVectors();
}

pub fn deinit(world: *World, allocator: std.mem.Allocator) !void {
    log.info("Deinitializing Mesh Renderer...", .{});
    const mesh_renderer = self(world);

    mesh_renderer.pipeline.release();
    mesh_renderer.mesh_cache.deinit();
    _ = allocator; // autofix
}

pub fn draw(world: *World, encoder: *gpu.CommandEncoder) !void {
    const mesh_renderer = self(world);

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

    var query = world.entities.query(.{ .all = &.{.{
        .mesh_renderer = &.{ .transform, .mesh },
    }} });
    while (query.next()) |archetype| {
        const transforms: []Transform = archetype.slice(.mesh_renderer, .transform);
        const meshes: []Mesh = archetype.slice(.mesh_renderer, .mesh);

        for (transforms, meshes) |transform, mesh| {
            // Create vertex/index buffers for a mesh, if they don't already exist
            const gop = try mesh_renderer.mesh_cache.getOrPut(mesh);
            var mesh_cache: *MeshCache = gop.value_ptr;
            if (!gop.found_existing) {
                mesh_cache.vertex_buffer = core.device.createBuffer(&.{
                    .usage = .{ .vertex = true, .storage = true },
                    .size = mesh.vertices.len * @sizeOf(Mesh.Vertex),
                    .mapped_at_creation = .true,
                });
                const vertex_mapped = mesh_cache.vertex_buffer.getMappedRange(Mesh.Vertex, 0, mesh.vertices.len).?;
                @memcpy(vertex_mapped, mesh.vertices);
                mesh_cache.vertex_buffer.unmap();

                mesh_cache.index_buffer = core.device.createBuffer(&.{
                    .usage = .{ .index = true, .storage = true },
                    .size = mesh.indices.len * @sizeOf(u32),
                    .mapped_at_creation = .true,
                });
                const index_mapped = mesh_cache.index_buffer.getMappedRange(u32, 0, mesh.indices.len).?;
                @memcpy(index_mapped, mesh.indices);
                mesh_cache.index_buffer.unmap();

                mesh_cache.bind_group = core.device.createBindGroup(&gpu.BindGroup.Descriptor.init(.{
                    .layout = mesh_renderer.mesh_bind_group_layout,
                    .entries = &.{
                        gpu.BindGroup.Entry.buffer(0, mesh_cache.vertex_buffer, 0, mesh.vertices.len * @sizeOf(Mesh.Vertex)),
                        gpu.BindGroup.Entry.buffer(1, mesh_cache.index_buffer, 0, mesh.indices.len * @sizeOf(u32)),
                    },
                }));
            }

            // Create the uniform buffer
            // TODO: Maybe cache this too for some meshes?
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
            encoder.writeBuffer(mesh_renderer.uniform_buffer, 0, &[_]UniformBufferObject{ubo});

            // Render the mesh
            // TODO: Don't create a new render pass for every mesh?
            const pass = encoder.beginRenderPass(&render_pass_info);
            defer pass.release();

            pass.setPipeline(mesh_renderer.pipeline);
            pass.setBindGroup(0, mesh_renderer.uniform_bind_group, &.{});

            pass.setVertexBuffer(0, mesh_cache.vertex_buffer, 0, mesh.vertices.len * @sizeOf(Mesh.Vertex));
            pass.setIndexBuffer(mesh_cache.index_buffer, .uint32, 0, mesh.indices.len * @sizeOf(u32));
            pass.setBindGroup(1, mesh_cache.bind_group, &.{});
            pass.drawIndexed(@intCast(mesh.indices.len), 1, 0, 0, 0);

            if (mesh_renderer.wireframe_visible) {
                pass.setPipeline(mesh_renderer.pipieline_wireframe);
                pass.draw(@intCast(6 * mesh.indices.len), 1, 0, 0);
                pass.setPipeline(mesh_renderer.pipeline);
            }

            pass.end();
        }
    }
}
