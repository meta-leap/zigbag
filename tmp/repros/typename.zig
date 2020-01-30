const std = @import("std");

const Group = .{
    .Type1 = enum{foo, bar, baz},
    .Type2 = union(enum) { a: u16, b: i16 },
};

pub fn main() void {
    std.debug.warn("{}\n", .{ @typeName(Group.Type1) });
    std.debug.warn("{}\n", .{ @typeName(Group.Type2) });
}
