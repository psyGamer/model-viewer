const std = @import("std");

const pretty_fmt = @import("pretty_format.zig");

pub fn colorizedLogging(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = comptime formatPrefix(level, scope);
    const text = comptime foramtText(level, format);

    std.debug.getStderrMutex().lock();
    defer std.debug.getStderrMutex().unlock();

    const stderr = std.io.getStdErr().writer();

    // pretty_fmt tries to do multiline printing. Might not always working and is therefore not currently enabled.
    //nosuspend pretty_fmt.prettyFormat(stderr, prefix ++ text ++ "\n", args) catch return;
    nosuspend std.fmt.format(stderr, prefix ++ text ++ "\n", args) catch return;
}

fn formatPrefix(comptime level: std.log.Level, comptime scope: @TypeOf(.EnumLiteral)) []const u8 {
    const escape_seq = "\x1b";
    const gray_color = escape_seq ++ "[90m";

    const color = switch (level) {
        .debug => escape_seq ++ "[34m",
        .info => escape_seq ++ "[32m",
        .warn => escape_seq ++ "[33m",
        .err => escape_seq ++ "[31m",
    };

    const level_text = switch (level) {
        .debug => "Debug",
        .info => "Info",
        .warn => "Warn",
        .err => "Error",
    };
    // Used to align all log messages
    const padding = switch (level) {
        .debug => " ",
        .info => "  ",
        .warn => "  ",
        .err => " ",
    };

    if (scope == .default) {
        return gray_color ++ "[" ++ color ++ level_text ++ gray_color ++ "]:" ++ padding;
    } else {
        const scope_text = gray_color ++ "[" ++ color ++ @tagName(scope) ++ gray_color ++ "]: ";
        return gray_color ++ "[" ++ color ++ level_text ++ gray_color ++ "]" ++ padding ++ scope_text;
    }
}

fn foramtText(comptime level: std.log.Level, comptime text: []const u8) []const u8 {
    const escape_seq = "\x1b";
    const clear_color = escape_seq ++ "[0m";
    const text_color = switch (level) {
        .debug => escape_seq ++ "[94m",
        .info => escape_seq ++ "[92m",
        .warn => escape_seq ++ "[93m",
        .err => escape_seq ++ "[91m",
    };
    return text_color ++ text ++ clear_color;
}
