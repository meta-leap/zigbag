const std = @import("std");

pub fn main() !void {
    std.debug.warn("Ahoy", .{});
    return error.None;
}
