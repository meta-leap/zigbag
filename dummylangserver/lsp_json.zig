const std = @import("std");

const types = @import("./lsp_types.zig");

pub fn unmarshalUnion(comptime TUnion: type, mem: *std.heap.ArenaAllocator, member_name: []const u8, from: *const std.json.Value) std.mem.Allocator.Error!?usize {
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
                while (iter.next()) |item|
                    _ = try obj.put(item.key, (try unmarshal(types.JsonAny, mem, &item.value)) orelse return null);
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
                        // else return null; // TODO: compiler segfaults with this currently (January 2020), not an issue until we begin seeing the below stderr print in the wild though
                    } else if (jmap.getValue(comptime std.mem.trimRight(u8, field_name, "_"))) |*jval| {
                        if (try unmarshal(field_type, mem, jval)) |it|
                            @field(ret, field_name) = it
                        else if (@typeId(field_type) != .Optional)
                        // return null; // TODO: see segfault note above, same here
                            std.debug.warn("MISSING:\t{}.{}\n", .{ @typeName(T), field_name });
                    }
                }
                return ret;
            },
            else => return null,
        }
    } else {
        std.debug.warn("TID\t{}\n", .{type_id});
        unreachable;
    }
    return null;
}

pub fn marshal(mem: *std.heap.ArenaAllocator, from: var) std.mem.Allocator.Error!std.json.Value {
    const T = comptime @TypeOf(from);
    const type_id = comptime @typeId(T);
    const type_info = comptime @typeInfo(T);
    if (T == types.IntOrString)
        return switch (from) {
            .int => |it| .{ .Integer = it },
            .string => |it| .{ .String = it },
        }
    else if (T == types.String)
        return std.json.Value{ .String = from }
    else if (type_id == .Bool)
        return std.json.Value{ .Bool = from }
    else if (type_id == .Int or type_id == .ComptimeInt)
        return std.json.Value{ .Integer = @intCast(i64, from) }
    else if (type_id == .Float or type_id == .ComptimeFloat)
        return std.json.Value{ .Float = from }
    else if (type_id == .Null)
        return std.json.Value{ .Null = .{} }
    else if (type_id == .Enum)
        return std.json.Value{ .Integer = @enumToInt(from) }
    else if (type_id == .Optional)
        return if (from) |it| try marshal(mem, it) else .{ .Null = .{} }
    else if (type_id == .Struct) {
        const is_hash_map = comptime if (std.mem.indexOf(u8, @typeName(T), "ash")) |_| true else false;
        if (is_hash_map) {
            std.debug.warn("HASH_MAP:\t{}\n", .{@typeName(T)});
            return std.json.Value{ .Object = std.json.ObjectMap.init(&mem.allocator) };
        } else {
            var ret = std.json.Value{ .Object = std.json.ObjectMap.init(&mem.allocator) };
            comptime var i = @memberCount(T);
            inline while (i > 0) {
                i -= 1;
                const field_type = @memberType(T, i);
                const field_name = @memberName(T, i);
                const field_value = @field(from, field_name);
                var field_is_null = false;
                if (comptime (@typeId(field_type) == .Optional))
                    field_is_null = (field_value == null);
                if (comptime std.mem.eql(u8, field_name, @typeName(field_type))) {
                    var obj = (try marshal(mem, field_value)).Object.iterator();
                    while (obj.next()) |item|
                        _ = try ret.Object.put(item.key, item.value);
                } else if (!field_is_null) {
                    _ = try ret.Object.put(field_name, try marshal(mem, field_value));
                }
            }
            return ret;
        }
    } else if (type_id == .Pointer) {
        if (type_info.Pointer.size != .Slice)
            return try marshal(mem, from.*)
        else {
            var ret = std.json.Value{ .Array = std.json.Array.init(&mem.allocator) }; // TODO: use initCapacity once zig compiler's "broken LLVM module found" bug goes away
            for (from) |item|
                try ret.Array.append(try marshal(mem, item));
            return ret;
        }
    } else if (T == types.JsonAny)
        return switch (from) {
            .string => std.json.Value{ .String = from.string },
            .boolean => std.json.Value{ .Bool = from.boolean },
            .int => std.json.Value{ .Integer = from.int },
            .float => std.json.Value{ .Float = from.float },
            .array => try marshal(mem, from.array),
            .object => try marshal(mem, from.object),
        }
    else
        @compileError("unsupported type: " ++ @typeName(T));
}
