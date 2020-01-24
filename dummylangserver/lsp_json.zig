const std = @import("std");

const types = @import("./lsp_types.zig");

pub fn loadBasic(comptime T: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value) std.mem.Allocator.Error!?T {
    if (T == types.IntOrString)
        return switch (from.*) {
            .Integer => |int| .{ .int = int },
            .String => |str| .{ .string = str },
            else => null,
        }
    else if (T == types.String)
        return switch (from.*) {
            .String => |str| str,
            else => null,
        }
    else if (T == types.JsonAny)
        return switch (from.*) {
            .Null => .{ .object = null },
            .String => |jstr| .{ .string = jstr },
            .Bool => |jbool| .{ .boolean = jbool },
            .Integer => |jint| .{ .int = jint },
            .Float => |jfloat| .{ .float = jfloat },
            .Array => |jlist| load_all: {
                var arr = try mem.allocator.alloc(types.JsonAny, jlist.len);
                for (jlist.items[0..jlist.len]) |*item, i|
                    arr[i] = (try loadBasic(types.JsonAny, mem, item)) orelse return null;
                break :load_all .{ .array = &[_]types.JsonAny{} };
            },
            .Object => |jmap| load_all: {
                var obj = &std.StringHashMap(types.JsonAny).init(&mem.allocator);
                try obj.initCapacity(@intCast(usize, std.math.ceilPowerOfTwoPromote(usize, jmap.count())));
                var iter = jmap.iterator();
                while (iter.next()) |pair|
                    _ = try obj.put(pair.key, (try loadBasic(types.JsonAny, mem, &pair.value)) orelse return null);
                break :load_all .{ .array = &[_]types.JsonAny{} };
            },
        };
    return null;
}

pub fn loadUnion(comptime T: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value, memberName: []const u8) ?T {
    return null;
}
