const std = @import("std");

var rng: std.rand.Xoshiro256 = undefined;

pub fn init() !void {
    var seed: u64 = undefined;
    try std.os.getrandom(std.mem.asBytes(&seed));

    rng = std.rand.Xoshiro256.init(seed);
}

/// Generates a random integer based of a self-feeding internal seed.
/// The range includes
pub fn randomInt(comptime T: type) T {
    const bits = @typeInfo(T).Int.bits;
    const Uint = std.meta.Int(.unsigned, bits);

    return @bitCast(@as(Uint, @truncate(rng.next())));
}
