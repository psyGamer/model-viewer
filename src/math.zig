const std = @import("std");

pub usingnamespace specialize_on(f32);

pub fn specialize_on(comptime T: type) type {
    return struct {
        // Vector Types
        pub const Vec2 = @Vector(2, T);
        pub const Vec3 = @Vector(3, T);
        pub const Vec4 = @Vector(4, T);

        pub const VecSwizzle = enum { x, y, z, w };

        pub const vec2_zero: Vec2 = .{ 0, 0 };
        pub const vec2_one: Vec2 = .{ 1, 1 };
        pub const vec2_pos_x: Vec2 = .{ 1, 0 };
        pub const vec2_neg_x: Vec2 = .{ -1, 0 };
        pub const vec2_pos_y: Vec2 = .{ 0, 1 };
        pub const vec2_neg_y: Vec2 = .{ 0, -1 };

        pub const vec3_zero: Vec3 = .{ 0, 0, 0 };
        pub const vec3_one: Vec3 = .{ 1, 1, 1 };
        pub const vec3_pos_x: Vec3 = .{ 1, 0, 0 };
        pub const vec3_neg_x: Vec3 = .{ -1, 0, 0 };
        pub const vec3_pos_y: Vec3 = .{ 0, 1, 0 };
        pub const vec3_neg_y: Vec3 = .{ 0, -1, 0 };
        pub const vec3_pos_z: Vec3 = .{ 0, 0, 1 };
        pub const vec3_neg_z: Vec3 = .{ 0, 0, -1 };

        pub const vec4_zero: Vec4 = .{ 0, 0, 0, 0 };
        pub const vec4_one: Vec4 = .{ 1, 1, 1, 1 };
        pub const vec4_neg_x: Vec4 = .{ -1, 0, 0, 0 };
        pub const vec4_pos_y: Vec4 = .{ 0, 1, 0, 0 };
        pub const vec4_neg_y: Vec4 = .{ 0, -1, 0, 0 };
        pub const vec4_pos_z: Vec4 = .{ 0, 0, 1, 0 };
        pub const vec4_neg_z: Vec4 = .{ 0, 0, -1, 0 };
        pub const vec4_pos_w: Vec4 = .{ 0, 0, 0, 1 };
        pub const vec4_neg_w: Vec4 = .{ 0, 0, 0, -1 };

        pub fn vec2(x: T, y: T) Vec2 {
            return .{ x, y };
        }
        pub fn vec3(x: T, y: T, z: T) Vec3 {
            return .{ x, y, z };
        }
        pub fn vec4(x: T, y: T, z: T, w: T) Vec4 {
            return .{ x, y, z, w };
        }

        pub fn splat2(value: T) Vec2 {
            return @splat(value);
        }
        pub fn splat3(value: T) Vec3 {
            return @splat(value);
        }
        pub fn splat4(value: T) Vec4 {
            return @splat(value);
        }

        // Matrix Types
        pub const Mat2 = [2]Vec2;
        pub const Mat3 = [3]Vec3;
        pub const Mat4 = [4]Vec4;

        pub const mat2_ident: Mat2 = .{
            .{ 1, 0 },
            .{ 0, 1 },
        };
        pub const mat3_ident: Mat3 = .{
            .{ 1, 0, 0 },
            .{ 0, 1, 0 },
            .{ 0, 0, 1 },
        };
        pub const mat4_ident: Mat4 = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        };

        pub fn mat3_from_mat4(mat: Mat4) Mat3 {
            return .{
                .{ mat[0][0], mat[0][1], mat[0][2] },
                .{ mat[1][0], mat[1][1], mat[1][2] },
                .{ mat[2][0], mat[2][1], mat[2][2] },
            };
        }

        // Vector Functions
        fn assertValidVector(comptime TVec: type, arg_name: []const u8) void {
            if (@typeInfo(TVec) != .Vector or @typeInfo(TVec).Vector.child != T)
                @compileError("Argument \"" ++ arg_name ++ "\" must be of type @Vector(n, " ++ @typeName(T) ++ "), found " ++ @typeName(TVec));
        }

        fn getVectorLength(comptime TVec: type) comptime_int {
            return @typeInfo(TVec).Vector.len;
        }
        fn GetVectorType(comptime TVec: type, comptime arg_name: []const u8) type {
            assertValidVector(TVec, arg_name);
            return @typeInfo(TVec).Vector.child;
        }

        pub fn swizzle(vec: anytype, comptime components: anytype) @TypeOf(vec) {
            comptime assertValidVector(@TypeOf(vec), "vec");
            const vec_info = @typeInfo(@TypeOf(vec));
            const components_info = @typeInfo(@TypeOf(components));
            const len = vec_info.Vector.len;

            if (components_info != .Struct or !components_info.Struct.is_tuple or components_info.Struct.fields.len != len)
                @compileError("Argument \"components\" must be a tuple with a length of " ++ len ++ ", found " ++ @typeName(@TypeOf(components)));

            comptime var mask: [len]i32 = undefined;
            inline for (0..len) |i| {
                mask[i] = @intFromEnum(@as(VecSwizzle, components[i]));
            }

            return @shuffle(f32, vec, undefined, mask);
        }

        pub fn swizzleAll(vec: anytype, comptime component: VecSwizzle) @TypeOf(vec) {
            comptime assertValidVector(@TypeOf(vec), "vec");
            const vec_info = @typeInfo(@TypeOf(vec));
            const len = vec_info.Vector.len;

            const mask: [len]i32 = @intFromEnum(@as(VecSwizzle, component)) ** len;
            return @shuffle(f32, vec, undefined, mask);
        }

        /// Multiplies all components by a scalar value.
        pub fn scale(vec: anytype, scalar: T) @TypeOf(vec) {
            comptime assertValidVector(@TypeOf(vec), "vec");
            return vec * @as(@TypeOf(vec), @splat(scalar));
        }

        /// Divides all components by a scalar value.
        pub fn divide(vec: anytype, scalar: T) @TypeOf(vec) {
            comptime assertValidVector(@TypeOf(vec), "vec");
            return vec / @as(@TypeOf(vec), @splat(scalar));
        }

        /// Returns the dot product of two vectors.
        /// This is the sum of products of all components.
        pub fn dot(a: anytype, b: @TypeOf(a)) T {
            comptime assertValidVector(@TypeOf(a), "a");
            var result: T = undefined;
            inline for (0..getVectorLength(@TypeOf(a))) |i| {
                result += a[i] * b[i];
            }
            return result;
        }

        /// Calculates the cross product. result will be perpendicular to `a` and `b`.
        /// See: https://registry.khronos.org/OpenGL-Refpages/gl4/html/cross.xhtml
        pub fn cross(a: Vec3, b: Vec3) Vec3 {
            return .{
                a[1] * b[2] - a[2] * b[1],
                a[2] * b[0] - a[0] * b[2],
                a[0] * b[1] - a[1] * b[0],
            };
        }

        /// Returns the magnitude of the vector.
        pub fn length(vec: anytype) T {
            comptime assertValidVector(@TypeOf(vec), "vec");
            return @sqrt(lengthSquared(vec));
        }

        /// Returns the squared magnitude of the vector.
        pub fn lengthSquared(vec: anytype) T {
            comptime assertValidVector(@TypeOf(vec), "vec");
            return dot(vec, vec);
        }

        /// Returns the distance between `a` and `b`.
        pub fn distance(a: anytype, b: @TypeOf(a)) T {
            comptime assertValidVector(@TypeOf(a), "a");
            return @sqrt(distanceSquared(a, b));
        }

        /// Returns the squared distance between `a` and `b`.
        pub fn distanceSquared(a: anytype, b: @TypeOf(a)) T {
            comptime assertValidVector(@TypeOf(a), "a");
            return lengthSquared(a - b);
        }

        /// Returns a normalized vector (`length() == 1`).
        /// **Note:** This causes a division by zero, if the vector has length 0!
        ///           Consider using `normalizeSafe` to specifically account for that case.
        pub fn normalize(vec: anytype) @TypeOf(vec) {
            comptime assertValidVector(@TypeOf(vec), "vec");
            const len = length(vec);
            std.debug.assert(len != 0);
            return vec / @as(@TypeOf(vec), @splat(len));
        }

        /// Returns either a normalized vector (`length() == 1`) or `zero` if the vector has length 0.
        pub fn normalizeSafe(vec: anytype) @TypeOf(vec) {
            comptime assertValidVector(@TypeOf(vec), "vec");
            const len = length(vec);
            if (len == 0) return 0;
            return vec / @as(@TypeOf(vec), @splat(len));
        }

        // Matrix Functions
        fn assertValidMatrix(comptime TMat: type, arg_name: []const u8) void {
            if (@typeInfo(TMat) != .Array or @typeInfo(@typeInfo(TMat).Array.child) != .Vector or @typeInfo(@typeInfo(TMat).Array.child).Vector.child != T)
                @compileError("Argument \"" ++ arg_name ++ "\" must be of type []@Vector(n, " ++ @typeName(T) ++ ") (matrix), found " ++ @typeName(TMat));
        }
        fn GetMatrixRowVector(comptime TMat: type) type {
            return @typeInfo(TMat).Array.child;
        }
        fn getMatrixRows(comptime TMat: type) comptime_int {
            return @typeInfo(TMat).Array.len;
        }
        fn getMatrixColumns(comptime TMat: type) comptime_int {
            return getVectorLength(GetMatrixRowVector(TMat));
        }
        fn GetMatrixType(comptime TMat: type, comptime arg_name: []const u8) type {
            assertValidMatrix(TMat, arg_name);
            return GetVectorType(@typeInfo(TMat).Vector.child, undefined);
        }

        pub fn identityMatrix(comptime TMat: type) TMat {
            const rows = getMatrixRows(TMat);
            const cols = getMatrixColumns(TMat);
            if (rows != cols) @compileError("Identity matrix requires rows == cols");
            var result: TMat = undefined;
            for (0..rows) |row| {
                for (0..cols) |col| {
                    result[row][col] = if (row == col) 1 else 0;
                }
            }
            return result;
        }

        pub fn mul(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
            const TMat = @TypeOf(a);
            const TVec = GetMatrixRowVector(TMat);

            var result: TMat = undefined;
            switch (TMat) {
                inline Mat4 => {
                    inline for (0..4) |row| {
                        const vx = swizzle(a[row], .{ .x, .x, .x, .x });
                        const vy = swizzle(a[row], .{ .y, .y, .y, .y });
                        const vz = swizzle(a[row], .{ .z, .z, .z, .z });
                        const vw = swizzle(a[row], .{ .w, .w, .w, .w });
                        result[row] = @mulAdd(TVec, vx, b[0], vz * b[2]) + @mulAdd(TVec, vy, b[1], vw * b[3]);
                    }
                },
                else => @compileError("Unsupported matrix type: " ++ @typeName(TMat)),
            }
            return result;
        }

        fn BatchMulElement(comptime TMat: type) type {
            switch (@typeInfo(TMat)) {
                .Array => |info| return info.child,
                .Pointer => |info| switch (info.size) {
                    .One => switch (@typeInfo(info.child)) {
                        .Array => |array_info| return array_info.child,
                        else => {},
                    },
                    .Slice => return info.child,
                },
                .Struct => |info| {
                    if (info.fields.len == 0) @compileError("Can't batch multiply an empty tuple");
                    return info.fields[0].type;
                },
                else => {},
            }
            @compileError("Expected tuple, pointer, slice or array, found '" ++ @typeName(TMat) ++ "'");
        }

        /// Batch matrix multiplication. Will multiply all matrices from "first" to "last".
        pub fn batchMul(items: anytype) BatchMulElement(@TypeOf(items)) {
            switch (@typeInfo(@TypeOf(items))) {
                .Array => |info| switch (info.len) {
                    0 => return identityMatrix(info.child),
                    1 => return items[0],
                    else => {
                        var value = items[0];
                        for (1..items.len) |i| {
                            value = mul(value, items[i]);
                        }
                        return value;
                    },
                },
                .Pointer => |info| switch (info.size) {
                    .One => switch (@typeInfo(info.child)) {
                        .Array => |array_info| switch (array_info.len) {
                            0 => return identityMatrix(info.child),
                            1 => return items.*[0],
                            else => {
                                var value = items.*[0];
                                for (1..items.len) |i| {
                                    value = mul(value, items.*[i]);
                                }
                                return value;
                            },
                        },
                        else => {},
                    },
                    .Slice => switch (items.len) {
                        0 => return identityMatrix(info.child),
                        else => {
                            var value = items.*[0];
                            for (1..items.len) |i| {
                                value = mul(value, items.*[i]);
                            }
                            return value;
                        },
                    },
                },
                .Struct => |info| {
                    if (info.fields.len == 0) @compileError("Can't batch multiply an empty tuple");
                    if (info.fields.len == 1) @compileError("Batch multiplying a single matrix is a no-op");

                    var value = items[0];
                    inline for (0..info.fields.len) |i| {
                        value = mul(value, items[i]);
                    }
                    return value;
                },
                else => {},
            }
            @compileError("Expected tuple, pointer, slice or array, found '" ++ @typeName(@TypeOf(items)) ++ "'");
        }

        pub fn transpose(mat: Mat4) Mat4 {
            const temp1 = @shuffle(f32, mat[0], mat[1], [4]i32{ 0, 1, ~@as(i32, 0), ~@as(i32, 1) });
            const temp3 = @shuffle(f32, mat[0], mat[1], [4]i32{ 2, 3, ~@as(i32, 2), ~@as(i32, 3) });
            const temp2 = @shuffle(f32, mat[2], mat[3], [4]i32{ 0, 1, ~@as(i32, 0), ~@as(i32, 1) });
            const temp4 = @shuffle(f32, mat[2], mat[3], [4]i32{ 2, 3, ~@as(i32, 2), ~@as(i32, 3) });
            return .{
                @shuffle(f32, temp1, temp2, [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) }),
                @shuffle(f32, temp1, temp2, [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) }),
                @shuffle(f32, temp3, temp4, [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) }),
                @shuffle(f32, temp3, temp4, [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) }),
            };
        }

        pub fn inverse(mat: Mat4) Mat4 {
            const mt = transpose(mat);
            var v0: [4]Vec4 = undefined;
            var v1: [4]Vec4 = undefined;

            v0[0] = swizzle(mt[2], .{ .x, .x, .y, .y });
            v1[0] = swizzle(mt[3], .{ .z, .w, .z, .w });
            v0[1] = swizzle(mt[0], .{ .x, .x, .y, .y });
            v1[1] = swizzle(mt[1], .{ .z, .w, .z, .w });
            v0[2] = @shuffle(f32, mt[2], mt[0], [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) });
            v1[2] = @shuffle(f32, mt[3], mt[1], [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) });

            var d0 = v0[0] * v1[0];
            var d1 = v0[1] * v1[1];
            var d2 = v0[2] * v1[2];

            v0[0] = swizzle(mt[2], .{ .z, .w, .z, .w });
            v1[0] = swizzle(mt[3], .{ .x, .x, .y, .y });
            v0[1] = swizzle(mt[0], .{ .z, .w, .z, .w });
            v1[1] = swizzle(mt[1], .{ .x, .x, .y, .y });
            v0[2] = @shuffle(f32, mt[2], mt[0], [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) });
            v1[2] = @shuffle(f32, mt[3], mt[1], [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) });

            d0 = @mulAdd(Vec4, -v0[0], v1[0], d0);
            d1 = @mulAdd(Vec4, -v0[1], v1[1], d1);
            d2 = @mulAdd(Vec4, -v0[2], v1[2], d2);

            v0[0] = swizzle(mt[1], .{ .y, .z, .x, .y });
            v1[0] = @shuffle(f32, d0, d2, [4]i32{ ~@as(i32, 1), 1, 3, 0 });
            v0[1] = swizzle(mt[0], .{ .z, .x, .y, .x });
            v1[1] = @shuffle(f32, d0, d2, [4]i32{ 3, ~@as(i32, 1), 1, 2 });
            v0[2] = swizzle(mt[3], .{ .y, .z, .x, .y });
            v1[2] = @shuffle(f32, d1, d2, [4]i32{ ~@as(i32, 3), 1, 3, 0 });
            v0[3] = swizzle(mt[2], .{ .z, .x, .y, .x });
            v1[3] = @shuffle(f32, d1, d2, [4]i32{ 3, ~@as(i32, 3), 1, 2 });

            var c0 = v0[0] * v1[0];
            var c2 = v0[1] * v1[1];
            var c4 = v0[2] * v1[2];
            var c6 = v0[3] * v1[3];

            v0[0] = swizzle(mt[1], .{ .z, .w, .y, .z });
            v1[0] = @shuffle(f32, d0, d2, [4]i32{ 3, 0, 1, ~@as(i32, 0) });
            v0[1] = swizzle(mt[0], .{ .w, .z, .w, .y });
            v1[1] = @shuffle(f32, d0, d2, [4]i32{ 2, 1, ~@as(i32, 0), 0 });
            v0[2] = swizzle(mt[3], .{ .z, .w, .y, .z });
            v1[2] = @shuffle(f32, d1, d2, [4]i32{ 3, 0, 1, ~@as(i32, 2) });
            v0[3] = swizzle(mt[2], .{ .w, .z, .w, .y });
            v1[3] = @shuffle(f32, d1, d2, [4]i32{ 2, 1, ~@as(i32, 2), 0 });

            c0 = @mulAdd(Vec4, -v0[0], v1[0], c0);
            c2 = @mulAdd(Vec4, -v0[1], v1[1], c2);
            c4 = @mulAdd(Vec4, -v0[2], v1[2], c4);
            c6 = @mulAdd(Vec4, -v0[3], v1[3], c6);

            v0[0] = swizzle(mt[1], .{ .w, .x, .w, .x });
            v1[0] = @shuffle(f32, d0, d2, [4]i32{ 2, ~@as(i32, 1), ~@as(i32, 0), 2 });
            v0[1] = swizzle(mt[0], .{ .y, .w, .x, .z });
            v1[1] = @shuffle(f32, d0, d2, [4]i32{ ~@as(i32, 1), 0, 3, ~@as(i32, 0) });
            v0[2] = swizzle(mt[3], .{ .w, .x, .w, .x });
            v1[2] = @shuffle(f32, d1, d2, [4]i32{ 2, ~@as(i32, 3), ~@as(i32, 2), 2 });
            v0[3] = swizzle(mt[2], .{ .y, .w, .x, .z });
            v1[3] = @shuffle(f32, d1, d2, [4]i32{ ~@as(i32, 3), 0, 3, ~@as(i32, 2) });

            const c1 = @mulAdd(Vec4, -v0[0], v1[0], c0);
            const c3 = @mulAdd(Vec4, v0[1], v1[1], c2);
            const c5 = @mulAdd(Vec4, -v0[2], v1[2], c4);
            const c7 = @mulAdd(Vec4, v0[3], v1[3], c6);

            c0 = @mulAdd(Vec4, v0[0], v1[0], c0);
            c2 = @mulAdd(Vec4, -v0[1], v1[1], c2);
            c4 = @mulAdd(Vec4, v0[2], v1[2], c4);
            c6 = @mulAdd(Vec4, -v0[3], v1[3], c6);

            var mr: Mat4 = .{
                .{ c0[0], c1[1], c0[2], c1[3] },
                .{ c2[0], c3[1], c2[2], c3[3] },
                .{ c4[0], c5[1], c4[2], c5[3] },
                .{ c6[0], c7[1], c6[2], c7[3] },
            };

            const det = dot(mr[0], mt[0]);

            if (std.math.approxEqAbs(f32, det, 0.0, std.math.floatEps(f32))) {
                return .{
                    .{ 0.0, 0.0, 0.0, 0.0 },
                    .{ 0.0, 0.0, 0.0, 0.0 },
                    .{ 0.0, 0.0, 0.0, 0.0 },
                    .{ 0.0, 0.0, 0.0, 0.0 },
                };
            }

            const scalar: Vec4 = @splat(1.0 / det);
            mr[0] *= scalar;
            mr[1] *= scalar;
            mr[2] *= scalar;
            mr[3] *= scalar;
            return mr;
        }

        /// Creates a look matrix.
        /// The matrix will create a transformation that can be used as a camera transform.
        /// The camera is located at `eye` and will look into `dir`.
        /// `up` is the direction from the screen center to the upper screen border.
        pub fn createLookMatrix(eye: Vec3, dir: Vec3, up: Vec3) Mat4 {
            const f = normalize(dir);
            const s = normalize(cross(up, f));
            const u = normalize(cross(f, s));

            return .{
                .{ s[0], u[0], f[0], 0 },
                .{ s[1], u[1], f[1], 0 },
                .{ s[2], u[2], f[2], 0 },
                .{ -dot(s, eye), -dot(u, eye), -dot(f, eye), 1 },
            };
        }

        /// Creates a look-at matrix.
        /// The matrix will create a transformation that can be used as a camera transform.
        /// The camera is located at `eye` and will look at `center`.
        /// `up` is the direction from the screen center to the upper screen border.
        pub fn createLookAtMatrix(eye: Vec3, center: Vec3, up: Vec3) Mat4 {
            return createLookMatrix(eye, eye - center, up);
        }

        /// Creates a perspective transformation matrix.
        /// `fov` is the field of view in radians,
        /// `aspect` is the screen aspect ratio (width / height)
        /// `near` is the distance of the near clip plane, whereas `far` is the distance to the far clip plane.
        pub fn createPerspectiveMatrix(fov: T, aspect: T, near: T, far: T) Mat4 {
            std.debug.assert(@abs(aspect - 0.001) > 0);
            std.debug.assert(near > 0);
            std.debug.assert(far > 0);
            const tanHalfFovy = @tan(fov / 2);

            return .{
                .{ 1 / (aspect * tanHalfFovy), 0, 0, 0 },
                .{ 0, 1 / tanHalfFovy, 0, 0 },
                .{ 0, 0, far / (near - far), -1 },
                .{ 0, 0, far / (near - far) * near, 0 },
            };
        }

        /// Creates an orthogonal projection matrix.
        /// `left`, `right`, `bottom` and `top` are the borders of the screen whereas `near` and `far` define the distance of the near and far clipping planes.
        pub fn createOrthogonalMatrix(left: T, right: T, bottom: T, top: T, near: T, far: T) Mat4 {
            return .{
                .{ 2 / (right - left), 0, 0, 0 },
                .{ 0, 2 / (top - bottom), 0, 0 },
                .{ 0, 0, 1 / (far - near), 0 },
                .{ -(right + left) / (right - left), -(top + bottom) / (top - bottom), -near / (far - near), 1 },
            };
        }

        /// Creates a rotation matrix around a certain axis.
        pub fn createAngleAxisMatrix(axis: Vec3, angle: T) Mat4 {
            const cos = @cos(angle);
            const sin = @sin(angle);
            const x = axis.x;
            const y = axis.y;
            const z = axis.z;

            return .{
                .{ cos + x * x * (1 - cos), x * y * (1 - cos) - z * sin, x * z * (1 - cos) + y * sin, 0 },
                .{ y * x * (1 - cos) + z * sin, cos + y * y * (1 - cos), y * z * (1 - cos) - x * sin, 0 },
                .{ z * x * (1 * cos) - y * sin, z * y * (1 - cos) + x * sin, cos + z * z * (1 - cos), 0 },
                .{ 0, 0, 0, 1 },
            };
        }

        /// Creates a rotation matrix around the X axis.
        pub fn createRotateXMatrix(angle: T) Mat4 {
            const cos = @cos(angle);
            const sin = @sin(angle);

            return .{
                .{ 1, 0, 0, 0 },
                .{ 0, cos, sin, 0 },
                .{ 0, -sin, cos, 0 },
                .{ 0, 0, 0, 1 },
            };
        }

        /// Creates a rotation matrix around the Y axis.
        pub fn createRotateYMatrix(angle: T) Mat4 {
            const cos = @cos(angle);
            const sin = @sin(angle);

            return .{
                .{ cos, 0, -sin, 0 },
                .{ 0, 1, 0, 0 },
                .{ sin, 0, cos, 0 },
                .{ 0, 0, 0, 1 },
            };
        }

        /// Creates a rotation matrix around the Z axis.
        pub fn createRotateZMatrix(angle: T) Mat4 {
            const cos = @cos(angle);
            const sin = @sin(angle);

            return .{
                .{ cos, sin, 0, 0 },
                .{ -sin, cos, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ 0, 0, 0, 1 },
            };
        }

        /// Creates matrix that will scale a homogeneous matrix.
        pub fn createUniformScaleMatrix(scalar: T) Mat4 {
            return createScaleMatrix(scalar, scalar, scalar);
        }

        /// Creates a non-uniform scaling matrix
        pub fn createScaleMatrix(x: T, y: T, z: T) Mat4 {
            return .{
                .{ x, 0, 0, 0 },
                .{ 0, y, 0, 0 },
                .{ 0, 0, z, 0 },
                .{ 0, 0, 0, 1 },
            };
        }

        /// Creates matrix that will scale a homogeneous matrix.
        pub fn createTranslationMatrix(vec: Vec3) Mat4 {
            return createTranslationXYZMatrix(vec[0], vec[1], vec[2]);
        }

        pub fn createTranslationXYZMatrix(x: T, y: T, z: T) Mat4 {
            return .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ x, y, z, 1 },
            };
        }
    };
}

comptime {
    // Local copy, since usingnamespace only works when importing this
    const Vec2 = @Vector(2, f32);
    const Vec3 = @Vector(3, f32);
    const Vec4 = @Vector(4, f32);

    const Mat2 = [2]Vec2;
    const Mat3 = [3]Vec3;
    const Mat4 = [4]Vec4;

    // Ensure GPU compatability
    // See: https://www.w3.org/TR/WGSL/#alignment-and-size

    // Vector
    std.debug.assert(@alignOf(Vec2) == 8);
    std.debug.assert(@sizeOf(Vec2) == 8);

    std.debug.assert(@alignOf(Vec3) == 16);
    std.debug.assert(@sizeOf(Vec3) == 16);

    std.debug.assert(@alignOf(Vec4) == 16);
    std.debug.assert(@sizeOf(Vec4) == 16);

    // Matrix
    std.debug.assert(@alignOf(Mat2) == 8);
    std.debug.assert(@sizeOf(Mat2) == 16);

    std.debug.assert(@alignOf(Mat3) == 16);
    std.debug.assert(@sizeOf(Mat3) == 48);

    std.debug.assert(@alignOf(Mat4) == 16);
    std.debug.assert(@sizeOf(Mat4) == 64);
}
