const std = @import("std");

const lspt = @import("./lsp_types.zig");

pub fn load(comptime T: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value) ?T {
    if (T == lspt.IntOrString)
        return switch (from.*) {
            .Integer => |int| T{ .int = int },
            .String => |str| T{ .string = str },
            else => null,
        }
    else if (T == lspt.String)
        return switch (from.*) {
            .String => |str| str,
            else => null,
        }
    else if (T == lspt.JsonAny)
        return switch (from.*) {
            .String => |str| T{ .string = str },
            .Null => T{ .object = null },
            .Bool => |b| T{ .boolean = b },
            .Integer => |int| T{ .int = int },
            .Float => |f| T{ .float = f },
            .Array => |list| load_all: {
                var arr = mem.allocator.alloc(lspt.JsonAny, list.len) catch return null;
                for (list.items[0..list.len]) |*item, i|
                    arr[i] = load(lspt.JsonAny, mem, item) orelse return null;
                break :load_all T{ .array = &[_]lspt.JsonAny{} };
            },
            .Object => |hashmap| load_all: {
                var obj = &std.StringHashMap(lspt.JsonAny).init(&mem.allocator);
                // obj.initCapacity(hashmap.count()) catch return null;
                var iter = hashmap.iterator();
                while (iter.next()) |pair|
                    _ = obj.put(pair.key, load(lspt.JsonAny, mem, &pair.value) orelse return null) catch return null;
                break :load_all T{ .array = &[_]lspt.JsonAny{} };
            },
        };
    return null;
}
