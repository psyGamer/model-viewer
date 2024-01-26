///! Creates a struct-of-arrays instead of an array-of-structs
const std = @import("std");

pub fn MultiArray(comptime T: type) type {
    comptime var fields: []const std.builtin.Type.StructField = &.{};
    for (std.meta.fields(T)) |field| {
        fields = fields ++ [_]std.builtin.Type.StructField{.{
            .name = field.name,
            .type = []field.type,
            .default_value = &.{},
            .is_comptime = false,
            .alignment = @alignOf([]field.type),
        }};
    }
    return @Type(.{
        .Struct = .{
            .layout = .Auto,
            .is_tuple = false,
            .fields = fields,
            .decls = &[_]std.builtin.Type.Declaration{},
        },
    });
}
