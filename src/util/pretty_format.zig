const std = @import("std");

// This ANY const is a workaround for: https://github.com/ziglang/zig/issues/7948
const ANY = "any";

const max_format_args = @typeInfo(std.fmt.ArgSetType).Int.bits;

/// Renders fmt string with args, calling `writer` with slices of bytes.
/// If `writer` returns an error, the error is returned from `format` and
/// `writer` is not called again.
///
/// The format string must be comptime-known and may contain placeholders following
/// this format:
/// `{[argument][specifier]:[fill][alignment][width].[precision]}`
///
/// Above, each word including its surrounding [ and ] is a parameter which you have to replace with something:
///
/// - *argument* is either the numeric index or the field name of the argument that should be inserted
///   - when using a field name, you are required to enclose the field name (an identifier) in square
///     brackets, e.g. {[score]...} as opposed to the numeric index form which can be written e.g. {2...}
/// - *specifier* is a type-dependent formatting option that determines how a type should formatted (see below)
/// - *fill* is a single character which is used to pad the formatted text
/// - *alignment* is one of the three characters `<`, `^`, or `>` to make the text left-, center-, or right-aligned, respectively
/// - *width* is the total width of the field in characters
/// - *precision* specifies how many decimals a formatted number should have
///
/// Note that most of the parameters are optional and may be omitted. Also you can leave out separators like `:` and `.` when
/// all parameters after the separator are omitted.
/// Only exception is the *fill* parameter. If *fill* is required, one has to specify *alignment* as well, as otherwise
/// the digits after `:` is interpreted as *width*, not *fill*.
///
/// The *specifier* has several options for types:
/// - `x` and `X`: output numeric value in hexadecimal notation
/// - `s`:
///   - for pointer-to-many and C pointers of u8, print as a C-string using zero-termination
///   - for slices of u8, print the entire slice as a string without zero-termination
/// - `e`: output floating point value in scientific notation
/// - `d`: output numeric value in decimal notation
/// - `b`: output integer value in binary notation
/// - `o`: output integer value in octal notation
/// - `c`: output integer as an ASCII character. Integer type must have 8 bits at max.
/// - `u`: output integer as an UTF-8 sequence. Integer type must have 21 bits at max.
/// - `?`: output optional value as either the unwrapped value, or `null`; may be followed by a format specifier for the underlying value.
/// - `!`: output error union value as either the unwrapped value, or the formatted error value; may be followed by a format specifier for the underlying value.
/// - `*`: output the address of the value instead of the value itself.
/// - `any`: output a value of any type using its default format.
///
/// If a formatted user type contains a function of the type
/// ```
/// pub fn format(value: ?, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) anyerror!void
/// ```
/// with `?` being the type formatted, this function will be called instead of the default implementation.
/// This allows user types to be formatted in a logical manner instead of dumping all fields of the type.
///
/// A user type may be a `struct`, `vector`, `union` or `enum` type.
///
/// To print literal curly braces, escape them by writing them twice, e.g. `{{` or `}}`.
pub fn prettyFormat(
    writer: anytype,
    comptime fmt: []const u8,
    args: anytype,
) anyerror!void {
    const ArgsType = @TypeOf(args);
    const args_type_info = @typeInfo(ArgsType);
    if (args_type_info != .Struct) {
        @compileError("expected tuple or struct argument, found " ++ @typeName(ArgsType));
    }

    const fields_info = args_type_info.Struct.fields;
    if (fields_info.len > max_format_args) {
        @compileError("32 arguments max are supported per format call");
    }

    @setEvalBranchQuota(2000000);
    comptime var arg_state: std.fmt.ArgState = .{ .args_len = fields_info.len };
    comptime var i = 0;
    inline while (i < fmt.len) {
        const start_index = i;

        inline while (i < fmt.len) : (i += 1) {
            switch (fmt[i]) {
                '{', '}' => break,
                else => {},
            }
        }

        comptime var end_index = i;
        comptime var unescape_brace = false;

        // Handle {{ and }}, those are un-escaped as single braces
        if (i + 1 < fmt.len and fmt[i + 1] == fmt[i]) {
            unescape_brace = true;
            // Make the first brace part of the literal...
            end_index += 1;
            // ...and skip both
            i += 2;
        }

        // Write out the literal
        if (start_index != end_index) {
            try writer.writeAll(fmt[start_index..end_index]);
        }

        // We've already skipped the other brace, restart the loop
        if (unescape_brace) continue;

        if (i >= fmt.len) break;

        if (fmt[i] == '}') {
            @compileError("missing opening {");
        }

        // Get past the {
        comptime std.debug.assert(fmt[i] == '{');
        i += 1;

        const fmt_begin = i;
        // Find the closing brace
        inline while (i < fmt.len and fmt[i] != '}') : (i += 1) {}
        const fmt_end = i;

        if (i >= fmt.len) {
            @compileError("missing closing }");
        }

        // Get past the }
        comptime std.debug.assert(fmt[i] == '}');
        i += 1;

        const placeholder = comptime std.fmt.Placeholder.parse(fmt[fmt_begin..fmt_end].*);
        const arg_pos = comptime switch (placeholder.arg) {
            .none => null,
            .number => |pos| pos,
            .named => |arg_name| std.meta.fieldIndex(ArgsType, arg_name) orelse
                @compileError("no argument with name '" ++ arg_name ++ "'"),
        };

        const width = switch (placeholder.width) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime std.meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const precision = switch (placeholder.precision) {
            .none => null,
            .number => |v| v,
            .named => |arg_name| blk: {
                const arg_i = comptime std.meta.fieldIndex(ArgsType, arg_name) orelse
                    @compileError("no argument with name '" ++ arg_name ++ "'");
                _ = comptime arg_state.nextArg(arg_i) orelse @compileError("too few arguments");
                break :blk @field(args, arg_name);
            },
        };

        const arg_to_print = comptime arg_state.nextArg(arg_pos) orelse
            @compileError("too few arguments");

        try prettyFormatType(
            @field(args, fields_info[arg_to_print].name),
            placeholder.specifier_arg,
            std.fmt.FormatOptions{
                .fill = placeholder.fill,
                .alignment = placeholder.alignment,
                .width = width,
                .precision = precision,
            },
            writer,
            0,
            std.options.fmt_max_depth,
        );
    }

    if (comptime arg_state.hasUnusedArgs()) {
        const missing_count = arg_state.args_len - @popCount(arg_state.used_args);
        switch (missing_count) {
            0 => unreachable,
            1 => @compileError("unused argument in '" ++ fmt ++ "'"),
            else => @compileError(std.fmt.comptimePrint("{d}", .{missing_count}) ++ " unused arguments in '" ++ fmt ++ "'"),
        }
    }
}

pub fn prettyFormatType(value: anytype, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: std.fs.File.Writer, depth: usize, max_depth: usize) anyerror!void {
    const T = @TypeOf(value);
    const actual_fmt = comptime if (std.mem.eql(u8, fmt, ANY))
        std.fmt.defaultSpec(@TypeOf(value))
    else if (fmt.len != 0 and (fmt[0] == '?' or fmt[0] == '!')) switch (@typeInfo(T)) {
        .Optional, .ErrorUnion => fmt,
        else => stripOptionalOrErrorUnionSpec(fmt),
    } else fmt;

    if (comptime std.mem.eql(u8, actual_fmt, "*")) {
        return std.fmt.formatAddress(value, options, writer);
    }

    if (comptime std.meta.hasFn(T, "format")) {
        return try value.format(actual_fmt, options, writer);
    }

    switch (@typeInfo(T)) {
        .Int, .ComptimeInt, .Float, .ComptimeFloat => {
            return formatValue(value, actual_fmt, options, writer);
        },
        .Void => {
            if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
            return std.fmt.formatBuf("void", options, writer);
        },
        .Bool => {
            if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
            return std.fmt.formatBuf(if (value) "true" else "false", options, writer);
        },
        .Optional => {
            if (actual_fmt.len == 0 or actual_fmt[0] != '?')
                @compileError("cannot format optional without a specifier (i.e. {?} or {any})");
            const remaining_fmt = comptime stripOptionalOrErrorUnionSpec(actual_fmt);
            if (value) |payload| {
                return prettyFormatType(payload, remaining_fmt, options, writer, depth, max_depth);
            } else {
                return std.fmt.formatBuf("null", options, writer);
            }
        },
        .ErrorUnion => {
            if (actual_fmt.len == 0 or actual_fmt[0] != '!')
                @compileError("cannot format error union without a specifier (i.e. {!} or {any})");
            const remaining_fmt = comptime stripOptionalOrErrorUnionSpec(actual_fmt);
            if (value) |payload| {
                return prettyFormatType(payload, remaining_fmt, options, writer, depth, max_depth);
            } else |err| {
                return prettyFormatType(err, "", options, writer, depth, max_depth);
            }
        },
        .ErrorSet => {
            if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
            try writer.writeAll("error.");
            return writer.writeAll(@errorName(value));
        },
        .Enum => |enumInfo| {
            try writer.writeAll(@typeName(T));
            if (enumInfo.is_exhaustive) {
                if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
                try writer.writeAll(".");
                try writer.writeAll(@tagName(value));
                return;
            }

            // Use @tagName only if value is one of known fields
            @setEvalBranchQuota(3 * enumInfo.fields.len);
            inline for (enumInfo.fields) |enumField| {
                if (@intFromEnum(value) == enumField.value) {
                    try writer.writeAll(".");
                    try writer.writeAll(@tagName(value));
                    return;
                }
            }

            try writer.writeAll("(");
            try prettyFormatType(@intFromEnum(value), actual_fmt, options, writer, depth, max_depth);
            try writer.writeAll(")");
        },
        .Union => |info| {
            if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
            try writer.writeAll(@typeName(T));
            if (max_depth == 0) {
                return writer.writeAll("{ ... }");
            }
            if (info.tag_type) |UnionTagType| {
                try writer.writeAll("{ .");
                try writer.writeAll(@tagName(@as(UnionTagType, value)));
                try writer.writeAll(" = ");
                inline for (info.fields) |u_field| {
                    if (value == @field(UnionTagType, u_field.name)) {
                        try prettyFormatType(@field(value, u_field.name), ANY, options, writer, depth + 1, max_depth);
                    }
                }
                try writer.writeAll(" }");
            } else {
                try std.fmt.format(writer, "@{x}", .{@intFromPtr(&value)});
            }
        },
        .Struct => |info| {
            if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
            if (info.is_tuple) {
                try writer.writeAll(@typeName(T));
                // Skip the type and field names when formatting tuples.
                if (max_depth == depth) {
                    return writer.writeAll("{ ... }");
                }
                try writer.writeAll("{");
                inline for (info.fields, 0..) |f, i| {
                    if (i == 0) {
                        try writer.writeAll(" ");
                    } else {
                        try writer.writeAll(", ");
                    }
                    try prettyFormatType(@field(value, f.name), ANY, options, writer, depth + 1, max_depth);
                }
                return writer.writeAll(" }");
            }

            // Detect a hashmap
            if (comptime std.mem.startsWith(u8, @typeName(T), "hash_map.HashMap")) {
                try writer.writeAll("{\n");
                var it = value.iterator();
                while (it.next()) |entry| {
                    try formatIndent(depth + 1, writer);
                    try prettyFormatType(entry.key_ptr.*, ANY, options, writer, depth + 1, max_depth);

                    try writer.writeAll(" => ");
                    try prettyFormatType(entry.value_ptr.*, ANY, options, writer, depth + 1, max_depth);
                    try writer.writeAll(",\n");
                }
                try formatIndent(depth, writer);
                try writer.writeAll("}");
                return;
            }

            try writer.writeAll(@typeName(T));
            if (max_depth == depth) {
                return writer.writeAll("{ ... }");
            }
            try writer.writeAll("{\n");
            inline for (info.fields) |f| {
                try formatIndent(depth + 1, writer);
                try writer.writeAll(".");
                try writer.writeAll(f.name);
                try writer.writeAll(" = ");
                try prettyFormatType(@field(value, f.name), ANY, options, writer, depth + 1, max_depth);
                try writer.writeAll(",\n");
            }
            try formatIndent(depth, writer);
            try writer.writeAll("}");
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => switch (@typeInfo(ptr_info.child)) {
                .Array => |info| {
                    if (actual_fmt.len == 0)
                        @compileError("cannot format array ref without a specifier (i.e. {s} or {*})");
                    if (info.child == u8) {
                        switch (actual_fmt[0]) {
                            's', 'x', 'X', 'e', 'E' => {
                                comptime checkTextFmt(actual_fmt);
                                return std.fmt.formatBuf(value, options, writer);
                            },
                            else => {
                                if (std.mem.eql(u8, actual_fmt, "any")) {
                                    try writer.writeAll("\"");
                                    try std.fmt.formatBuf(value, options, writer);
                                    try writer.writeAll("\"");
                                }
                                return;
                            },
                        }
                    }
                    if (comptime std.meta.trait.isZigString(info.child)) {
                        for (value, 0..) |item, i| {
                            comptime checkTextFmt(actual_fmt);
                            if (i != 0) try std.fmt.formatBuf(", ", options, writer);
                            try std.fmt.formatBuf(item, options, writer);
                        }
                        return;
                    }
                    std.fmt.invalidFmtError(fmt, value);
                },
                .Enum, .Union, .Struct => {
                    return prettyFormatType(value.*, actual_fmt, options, writer, depth + 1, max_depth);
                },
                else => return std.fmt.format(writer, "{s}@{x}", .{ @typeName(ptr_info.child), @intFromPtr(value) }),
            },
            .Many, .C => {
                if (actual_fmt.len == 0)
                    @compileError("cannot format pointer without a specifier (i.e. {s} or {*})");
                if (ptr_info.sentinel) |_| {
                    return prettyFormatType(std.mem.span(value), actual_fmt, options, writer, depth, max_depth);
                }
                if (ptr_info.child == u8) {
                    switch (actual_fmt[0]) {
                        's', 'x', 'X', 'e', 'E' => {
                            comptime checkTextFmt(actual_fmt);
                            return std.fmt.formatBuf(std.mem.span(value), options, writer);
                        },
                        else => {
                            if (std.mem.eql(u8, actual_fmt, "any")) {
                                try writer.writeAll("\"");
                                try std.fmt.formatBuf(value, options, writer);
                                try writer.writeAll("\"");
                            }
                            return;
                        },
                    }
                }
                std.fmt.invalidFmtError(fmt, value);
            },
            .Slice => {
                if (actual_fmt.len == 0)
                    @compileError("cannot format slice without a specifier (i.e. {s} or {any})");
                if (max_depth == depth) {
                    return writer.writeAll("{ ... }");
                }
                if (ptr_info.child == u8) {
                    switch (actual_fmt[0]) {
                        's', 'x', 'X', 'e', 'E' => {
                            comptime checkTextFmt(actual_fmt);
                            return std.fmt.formatBuf(value, options, writer);
                        },
                        else => {
                            if (std.mem.eql(u8, actual_fmt, "any")) {
                                try writer.writeAll("\"");
                                try std.fmt.formatBuf(value, options, writer);
                                try writer.writeAll("\"");
                            }
                            return;
                        },
                    }
                }

                const child_info = @typeInfo(ptr_info.child);
                if (value.len == 0) {
                    try writer.writeAll("{ }");
                } else if ((child_info == .Int or child_info == .ComptimeInt or
                    child_info == .Float or child_info == .ComptimeFloat or
                    child_info == .Void or child_info == .Bool))
                {
                    try writer.writeAll("{ ");
                    for (value, 0..) |elem, i| {
                        try prettyFormatType(elem, actual_fmt, options, writer, depth, max_depth);
                        if (i != value.len - 1) {
                            try writer.writeAll(", ");
                        }
                    }
                    try writer.writeAll(" }");
                } else {
                    try writer.writeAll("{\n");
                    for (value, 0..) |elem, i| {
                        try formatIndent(depth + 1, writer);
                        try std.fmt.formatIntValue(i, "", .{}, writer);
                        try writer.writeAll(": ");
                        try prettyFormatType(elem, actual_fmt, options, writer, depth + 1, max_depth);
                        try writer.writeAll(",\n");
                    }
                    try formatIndent(depth, writer);
                    try writer.writeAll("}");
                }
            },
        },
        .Array => |info| {
            if (actual_fmt.len == 0)
                @compileError("cannot format array without a specifier (i.e. {s} or {any})");
            if (max_depth == depth) {
                return writer.writeAll("{ ... }");
            }
            if (info.child == u8) {
                switch (actual_fmt[0]) {
                    's', 'x', 'X', 'e', 'E' => {
                        comptime checkTextFmt(actual_fmt);
                        return std.fmt.formatBuf(&value, options, writer);
                    },
                    else => {},
                }
            }
            try writer.writeAll("{ ");
            for (value, 0..) |elem, i| {
                try prettyFormatType(elem, actual_fmt, options, writer, depth + 1, max_depth);
                if (i < value.len - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeAll(" }");
        },
        .Vector => |info| {
            try writer.writeAll("{ ");
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                try formatValue(value[i], actual_fmt, options, writer);
                if (i < info.len - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeAll(" }");
        },
        .Fn => @compileError("unable to format function body type, use '*const " ++ @typeName(T) ++ "' for a function pointer type"),
        .Type => {
            if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
            return std.fmt.formatBuf(@typeName(value), options, writer);
        },
        .EnumLiteral => {
            if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
            const buffer = [_]u8{'.'} ++ @tagName(value);
            return std.fmt.formatBuf(buffer, options, writer);
        },
        .Null => {
            if (actual_fmt.len != 0) std.fmt.invalidFmtError(fmt, value);
            return std.fmt.formatBuf("null", options, writer);
        },
        else => @compileError("unable to format type '" ++ @typeName(T) ++ "'"),
    }
}

fn checkTextFmt(comptime fmt: []const u8) void {
    if (fmt.len != 1)
        @compileError("unsupported format string '" ++ fmt ++ "' when formatting text");
    switch (fmt[0]) {
        // Example of deprecation:
        // '[deprecated_specifier]' => @compileError("specifier '[deprecated_specifier]' has been deprecated, wrap your argument in `std.some_function` instead"),
        'x' => @compileError("specifier 'x' has been deprecated, wrap your argument in std.fmt.fmtSliceHexLower instead"),
        'X' => @compileError("specifier 'X' has been deprecated, wrap your argument in std.fmt.fmtSliceHexUpper instead"),
        else => {},
    }
}

fn formatIndent(
    depth: usize,
    writer: anytype,
) anyerror!void {
    for (0..depth) |_| {
        try writer.writeAll("    ");
    }
}

fn stripOptionalOrErrorUnionSpec(comptime fmt: []const u8) []const u8 {
    return if (std.mem.eql(u8, fmt[1..], ANY))
        ANY
    else
        fmt[1..];
}

fn formatValue(
    value: anytype,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) anyerror!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Float, .ComptimeFloat => return formatFloatValue(value, fmt, options, writer),
        .Int, .ComptimeInt => return std.fmt.formatIntValue(value, fmt, options, writer),
        .Bool => return std.fmt.formatBuf(if (value) "true" else "false", options, writer),
        else => comptime unreachable,
    }
}

pub fn formatFloatValue(
    value: anytype,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) anyerror!void {
    // this buffer should be enough to display all decimal places of a decimal f64 number.
    var buf: [512]u8 = undefined;
    var buf_stream = std.io.fixedBufferStream(&buf);

    if (fmt.len == 0 or comptime std.mem.eql(u8, fmt, "d")) {
        std.fmt.formatFloatDecimal(value, options, buf_stream.writer()) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };
    } else if (comptime std.mem.eql(u8, fmt, "e")) {
        std.fmt.formatFloatScientific(value, options, buf_stream.writer()) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };
    } else if (comptime std.mem.eql(u8, fmt, "x")) {
        std.fmt.formatFloatHexadecimal(value, options, buf_stream.writer()) catch |err| switch (err) {
            error.NoSpaceLeft => unreachable,
        };
    } else {
        std.fmt.invalidFmtError(fmt, value);
    }

    return std.fmt.formatBuf(buf_stream.getWritten(), options, writer);
}
