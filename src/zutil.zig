const std = @import("std");

pub fn fmtTo(buf: *std.Buffer, comptime fmt: []const u8, args: var) !void {
    return std.fmt.format(buf, @TypeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append, fmt, args);
}

pub inline fn copy(mem: *std.mem.Allocator, it: var) !*@TypeOf(it) {
    var ret = try mem.create(@TypeOf(it));
    ret.* = it;
    return ret;
}

pub inline fn asP(comptime tag: var, scrutinee: var) !*const std.meta.TagPayloadType(std.json.Value, tag) {
    switch (scrutinee.*) {
        tag => |*ok| return ok,
        else => return error.BadJsonSrc,
    }
}

pub inline fn asV(comptime tag: var, scrutinee: var) !std.meta.TagPayloadType(std.json.Value, tag) {
    switch (scrutinee.*) {
        tag => |ok| return ok,
        else => return error.BadJsonSrc,
    }
}

pub inline fn uIs(comptime TUnion: type, comptime tag: var, it: TUnion) ?std.meta.TagPayloadType(TUnion, tag) {
    switch (it) {
        tag => |ok| return ok,
        else => return null,
    }
}

pub inline fn uIsnt(comptime TUnion: type, comptime tag: var, it: TUnion) bool {
    return switch (it) {
        tag => false,
        else => true,
    };
}
