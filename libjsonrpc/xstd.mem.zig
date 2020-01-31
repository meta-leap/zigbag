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

pub inline fn zeroed(comptime T: type) T {
    var ret: T = undefined;
    switch (comptime @typeId(T)) {
        .Bool => ret = false,
        .Int => ret = 0,
        .Float => ret = 0.0,
        .Optional => ret = null,
        .Enum => ret = @intToEnum(T, 0),
        .Struct => {
            comptime var i = comptime @memberCount(T);
            inline while (i > 0) {
                comptime i -= 1;
                @field(ret, comptime @memberName(T, i)) = zeroed(comptime @memberType(T, i));
            }
        },
        .Pointer => {
            const type_info = comptime @typeInfo(T);
            if (type_info.Pointer.size != .Slice) {
                std.debug.warn("TODO-PTR:\t*{}\n", .{@typeName(type_info.Pointer.child)});
                unreachable;
            }
            ret = &[_]type_info.Pointer.child{};
        },
        else => {
            std.debug.warn("TODO!ZERO\t{}\n", .{@typeId(T)});
            unreachable;
        },
    }
    return ret;
}
