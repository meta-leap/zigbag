const std = @import("std");

const types = @import("./lsp_types.zig");

pub fn loadOther(comptime T: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value) std.mem.Allocator.Error!?T {
    const type_id = comptime @typeId(T);
    const type_info = comptime @typeInfo(T);
    if (T == types.IntOrString)
        return switch (from.*) {
            .Integer => |jint| .{ .int = jint },
            .String => |jstr| .{ .string = jstr },
            else => null,
        }
    else if (T == types.String)
        return switch (from.*) {
            .String => |jstr| jstr,
            else => "",
        }
    else if (T == bool)
        return switch (from.*) {
            .Bool => |jbool| jbool,
            .String => |jstr| std.mem.eql(u8, "true", jstr),
            else => false,
        }
    else if (type_id == .Enum) {
        @compileLog(@typeName(T));
    } else if (T == types.JsonAny)
        return switch (from.*) {
            .Null => .{ .object = null },
            .String => |jstr| .{ .string = jstr },
            .Bool => |jbool| .{ .boolean = jbool },
            .Integer => |jint| .{ .int = jint },
            .Float => |jfloat| .{ .float = jfloat },
            .Array => |jlist| load_all: {
                var arr = try mem.allocator.alloc(types.JsonAny, jlist.len);
                for (jlist.items[0..jlist.len]) |*item, i|
                    arr[i] = (try loadOther(types.JsonAny, mem, item)) orelse return null;
                break :load_all .{ .array = &[_]types.JsonAny{} };
            },
            .Object => |jmap| load_all: {
                var obj = &std.StringHashMap(types.JsonAny).init(&mem.allocator);
                try obj.initCapacity(@intCast(usize, std.math.ceilPowerOfTwoPromote(usize, jmap.count())));
                var iter = jmap.iterator();
                while (iter.next()) |pair|
                    _ = try obj.put(pair.key, (try loadOther(types.JsonAny, mem, &pair.value)) orelse return null);
                break :load_all .{ .array = &[_]types.JsonAny{} };
            },
        }
    else if (type_id == .Optional)
        return (try loadOther(type_info.Optional.child, mem, from)) orelse null
    else if (type_id == .Pointer) {
        if (type_info.Pointer.size == .Slice) switch (from.*) {
            .Array => |jarr| {
                var ret = try mem.allocator.alloc(type_info.Pointer.child, jarr.len);
                for (jarr.items[0..jarr.len]) |*jval, i|
                    ret[i] = (try loadOther(type_info.Pointer.child, mem, jval)) orelse return null;
                return ret;
            },
            else => return null,
        } else
            return try @import("./xstd.mem.zig").enHeap(
            &mem.allocator,
            (try loadOther(type_info.Pointer.child, mem, from)) orelse return null,
        );
    } else if (type_id == .Struct) {
        comptime if (std.mem.indexOf(u8, @typeName(T), "HashMap")) |_|
            @compileError(@typeName(T));
        switch (from.*) {
            .Object => |*jmap| {
                var ret: T = undefined;
                comptime var i = @memberCount(T);
                inline while (i > 0) {
                    i -= 1;
                    const field_name = @memberName(T, i);
                    const field_type = @memberType(T, i);
                    if (comptime std.mem.eql(u8, "__", field_name)) {} else if (comptime std.mem.indexOf(u8, @typeName(field_type), "HashMap")) |_|
                        @compileError(field_name ++ "\t" ++ @typeName(field_type))
                    else if (jmap.getValue(field_name)) |*jval| {
                        @field(ret, field_name) = (try loadOther(field_type, mem, jval)) orelse return null;
                    }
                }
                return ret;
            },
            else => return null,
        }
    } else {
        std.debug.warn("TID\t{}\n", .{type_id});
    }
    return null;
}

pub fn loadUnion(comptime TUnion: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value, member_name: []const u8) std.mem.Allocator.Error!?usize {
    if (@typeId(TUnion) != .Union)
        @compileError("union type expected for 'TUnion'");
    comptime var i = @memberCount(TUnion);
    @setEvalBranchQuota(2020);
    inline while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, @memberName(TUnion, i), member_name)) {
            const TMember = @memberType(TUnion, i);
            return if (@typeId(TMember) == .Void)
                0
            else if (try loadOther(TMember, mem, from)) |ptr|
                @ptrToInt(ptr)
            else
                null;
        }
    }
    return null;
}
