const std = @import("std");

const dbg = std.debug.warn;

const types = @import("./lsp_types.zig");

pub fn marshal(mem: *std.heap.ArenaAllocator, from: var) std.mem.Allocator.Error!std.json.Value {
    const T = comptime @TypeOf(from);
    const type_id = comptime @typeId(T);
    if (T == types.IntOrString)
        return switch (from) {
            .int => |it| .{ .Integer = it },
            .string => |it| .{ .String = it },
        }
    else if (T == types.String)
        return .{ .String = from }
    else if (type_id == .Bool)
        return .{ .Bool = from }
    else if (type_id == .Int or type_id == .ComptimeInt)
        return std.json.Value{ .Integer = @intCast(i64, from) }
    else if (type_id == .Float or type_id == .ComptimeFloat)
        return .{ .Float = from }
    else if (type_id == .Null)
        return .{ .Null = .{} }
    else if (type_id == .Enum)
        return .{ .Integer = @enumToInt(from) }
    else if (type_id == .Optional)
        return if (from) |it| try marshal(mem, it) else .{ .Null = .{} }
    else if (type_id == .Pointer) {
        if (type_info.Pointer.size != .Slice)
            return try marshal(mem, from.*)
        else {
            var ret: std.json.Value = .{
                .Array = std.json.Array.initCapacity(&mem.allocator, from.len),
            };
            return ret;
        }
    } else
        @compileError("unsupported type: " ++ @typeName(T));
}

pub fn unmarshal(comptime T: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value) std.mem.Allocator.Error!?T {
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
            else => null,
        }
    else if (T == bool)
        return switch (from.*) {
            .Bool => |jbool| jbool,
            .String => |jstr| if (std.mem.eql(u8, "true", jstr)) true else (if (std.mem.eql(u8, "false", jstr)) false else null),
            else => null,
        }
    else if (type_id == .Int)
        return switch (from.*) {
            .Integer => |jint| jint,
            .Float => |jfloat| if (jfloat < @intToFloat(f64, std.math.minInt(T)) or jfloat > @intToFloat(f64, std.math.maxInt(T)))
                null
            else
                @floatToInt(T, jfloat),
            .String => |jstr| std.fmt.parseInt(T, jstr, 10) catch null,
            else => null,
        }
    else if (type_id == .Float)
        return switch (from.*) {
            .Float => |jfloat| jfloat,
            .Integer => |jint| @intToFloat(T, jint),
            .String => |jstr| std.fmt.parseFloat(T, jstr) catch null,
            else => null,
        }
    else if (type_id == .Enum) {
        const TEnum = std.meta.TagType(T);
        return switch (from.*) {
            .Integer => |jint| std.meta.intToEnum(T, jint) catch null,
            .String => |jstr| std.meta.stringToEnum(T, jstr) orelse (if (std.fmt.parseInt(TEnum, jstr, 10)) |i| (std.meta.intToEnum(T, i) catch null) else |_| null),
            .Float => |jfloat| if (jfloat < @intToFloat(f64, std.math.minInt(TEnum)) or jfloat > @intToFloat(f64, std.math.maxInt(TEnum)))
                null
            else
                (std.meta.intToEnum(T, @floatToInt(TEnum, jfloat)) catch null),
            else => null,
        };
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
                    arr[i] = (try unmarshal(types.JsonAny, mem, item)) orelse return null;
                break :load_all .{ .array = &[_]types.JsonAny{} };
            },
            .Object => |jmap| load_all: {
                var obj = &std.StringHashMap(types.JsonAny).init(&mem.allocator);
                try obj.initCapacity(@intCast(usize, std.math.ceilPowerOfTwoPromote(usize, jmap.count())));
                var iter = jmap.iterator();
                while (iter.next()) |pair|
                    _ = try obj.put(pair.key, (try unmarshal(types.JsonAny, mem, &pair.value)) orelse return null);
                break :load_all .{ .array = &[_]types.JsonAny{} };
            },
        }
    else if (type_id == .Optional) switch (from.*) {
        .Null => return null,
        else => return (try unmarshal(type_info.Optional.child, mem, from)) orelse null,
    } else if (type_id == .Pointer) {
        if (type_info.Pointer.size != .Slice) {
            const copy = try unmarshal(type_info.Pointer.child, mem, from);
            return try @import("./xstd.mem.zig").enHeap(&mem.allocator, copy orelse return null);
        } else switch (from.*) {
            .Array => |jarr| {
                var ret = try mem.allocator.alloc(type_info.Pointer.child, jarr.len);
                for (jarr.items[0..jarr.len]) |*jval, i|
                    ret[i] = (try unmarshal(type_info.Pointer.child, mem, jval)) orelse return null;
                return ret;
            },
            else => return null,
        }
    } else if (type_id == .Struct) {
        switch (from.*) {
            .Object => |*jmap| {
                var ret = @import("./xstd.mem.zig").zeroed(T);
                comptime var i = @memberCount(T);
                inline while (i > 0) {
                    i -= 1;
                    const field_name = @memberName(T, i);
                    const field_type = @memberType(T, i);
                    if (comptime std.mem.eql(u8, field_name, @typeName(field_type))) {
                        if (try unmarshal(field_type, mem, from)) |it|
                            @field(ret, field_name) = it;
                    } else if (jmap.getValue(comptime std.mem.trimRight(u8, field_name, "_"))) |*jval| {
                        if (try unmarshal(field_type, mem, jval)) |it|
                            @field(ret, field_name) = it;
                    }
                }
                return ret;
            },
            else => return null,
        }
    } else {
        dbg("TID\t{}\n", .{type_id});
    }
    return null;
}

pub fn unmarshalUnion(comptime TUnion: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value, member_name: []const u8) std.mem.Allocator.Error!?usize {
    if (@typeId(TUnion) != .Union)
        @compileError("union type expected for 'TUnion'");
    comptime var i = @memberCount(TUnion);
    inline while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, @memberName(TUnion, i), member_name)) {
            const TMember = @memberType(TUnion, i);
            return if (@typeId(TMember) == .Void)
                0
            else if (try unmarshal(TMember, mem, from)) |ptr|
                @ptrToInt(ptr)
            else
                null;
        }
    }
    return null;
}
