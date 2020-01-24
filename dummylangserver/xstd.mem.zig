const std = @import("std");

pub fn replaceScalar(comptime T: type, slice: []T, old: []const T, new: T) []T {
    for (slice) |value, i| {
        if (std.mem.indexOfScalar(T, old, value)) |_|
            slice[i] = new;
    }
    return slice;
}
