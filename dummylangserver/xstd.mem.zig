const std = @import("std");

pub inline fn replaceScalar(comptime T: type, slice: []T, old: []const T, new: T) []T {
    for (slice) |value, i| {
        if (std.mem.indexOfScalar(T, old, value)) |_|
            slice[i] = new;
    }
    return slice;
}

pub inline fn enHeap(mem: *std.mem.Allocator, it: var) !*@TypeOf(it) {
    var ret = try mem.create(@TypeOf(it));
    ret.* = it;
    return ret;
}
