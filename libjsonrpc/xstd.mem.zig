const std = @import("std");

pub inline fn replaceScalar(comptime T: type, slice: []T, old: T, new: T) void {
    for (slice) |value, i|
        if (value == old)
            slice[i] = new;
}

pub inline fn replaceScalars(comptime T: type, slice: []T, old: []const T, new: T) void {
    for (slice) |value, i| {
        if (std.mem.indexOfScalar(T, old, value)) |_|
            slice[i] = new;
    }
}

pub inline fn zeroed(comptime T: type) T {
    var ret: T = undefined;
    switch (comptime @typeId(T)) {
        .Bool => ret = false,
        .Int => ret = @intCast(T, 0),
        .Float => ret = @floatCast(T, 0.0),
        .Optional => ret = null,
        .Enum => @ptrCast(@TagType(T), &ret).* = 0,
        .Struct => {
            comptime var i = comptime @memberCount(T);
            inline while (i > 0) {
                comptime i -= 1;
                @field(ret, comptime @memberName(T, i)) = zeroed(comptime @memberType(T, i));
            }
        },
        .Pointer => {
            const type_info = comptime @typeInfo(T);
            if (type_info.Pointer.size == .Slice)
                ret = &[_]type_info.Pointer.child{}
            else
                ret.* = zeroed(type_info.Pointer.child);
        },
        else => @compileError(@typeName(T)),
    }
    return ret;
}
