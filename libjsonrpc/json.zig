const std = @import("std");

usingnamespace @import("./zcomptime.zig");

pub const Options = struct {
    set_optionals_null_on_bad_inputs: bool = false,
    err_on_missing_nonvoid_nonoptional_fields: bool = true,

    isStructFieldEmbedded: ?fn (type, []const u8, type) bool = null,
    rewriteStructFieldNameToJsonObjectKey: ?fn (type, []const u8) []const u8 = null,
    rewriteUnionFieldNameToJsonRpcMethodName: ?fn (type, comptime_int, []const u8) []const u8 = null,
    rewriteJsonRpcMethodNameToUnionFieldName: ?fn (MsgKind, []const u8) []const u8 = null,

    pub const MsgKind = enum {
        notification,
        request,
        response,
    };
};

pub fn marshal(mem: *std.heap.ArenaAllocator, from: var, comptime options: *const Options) std.mem.Allocator.Error!std.json.Value {
    const T = comptime @TypeOf(from);
    const type_id = comptime @typeId(T);
    const type_info = comptime @typeInfo(T);
    _ = nestingDepth(T);
    if (T == std.json.Value)
        return from;
    if (T == *std.json.Value or T == *const std.json.Value)
        return from.*;
    if (T == []const u8 or T == []u8)
        return std.json.Value{ .String = from };
    if (type_id == .Bool)
        return std.json.Value{ .Bool = from };
    if (type_id == .Int or type_id == .ComptimeInt)
        return std.json.Value{ .Integer = @intCast(i64, from) };
    if (type_id == .Float or type_id == .ComptimeFloat)
        return std.json.Value{ .Float = from };
    if (type_id == .Null or type_id == .Void)
        return std.json.Value{ .Null = .{} };
    if (type_id == .Enum)
        return std.json.Value{ .Integer = @enumToInt(from) };
    if (type_id == .Optional)
        return if (from) |it| try marshal(mem, it, options) else .{ .Null = .{} };
    if (type_id == .Pointer) {
        if (type_info.Pointer.size != .Slice)
            return try marshal(mem, from.*, options)
        else {
            var ret = std.json.Value{ .Array = try std.json.Array.initCapacity(&mem.allocator, from.len) };
            for (from) |item|
                try ret.Array.append(try marshal(mem, item, options));
            return ret;
        }
    }
    if (type_id == .Union) {
        comptime var i = @memberCount(T);
        inline while (i > 0) {
            i -= 1;
            if (@enumToInt(std.meta.activeTag(from)) == i) {
                return try marshal(mem, @field(from, @memberName(T, i)), options);
            }
        }
        unreachable;
    }
    if (type_id == .Struct) {
        const is_hashmap = comptime isTypeHashMapLikeDuckwise(T);

        var ret = std.json.Value{ .Object = std.json.ObjectMap.init(&mem.allocator) };
        try ret.Object.initCapacity(std.math.ceilPowerOfTwo(usize, (if (is_hashmap)
            from.count()
        else
            @memberCount(T)) * 5 / 3) catch return error.OutOfMemory);

        if (is_hashmap) {
            var iter = from.iterator();
            while (iter.next()) |pair|
                _ = try ret.Object.put(pair.key, pair.value);
        } else {
            comptime var i = @memberCount(T);
            inline while (i > 0) {
                i -= 1;
                comptime const field_type = comptime @memberType(T, i);
                comptime const field_type_id = comptime @typeId(field_type);
                const field_name = @memberName(T, i);
                const field_value = @field(from, field_name);
                comptime { // these to catch certain bugs / unintended-usages early that now probably no longer occur..
                    if (std.mem.indexOf(u8, @typeName(field_type), "ArrayList")) |_|
                        @compileError(@typeName(T) ++ "." ++ field_name);
                    if (std.mem.indexOf(u8, field_name, "lloc")) |_|
                        @compileError(@typeName(T) ++ "." ++ field_name);
                    if ((field_type_id == .Fn))
                        @compileError(@typeName(T) ++ "." ++ field_name);
                }
                if (comptime (field_type_id == .Struct and options.isStructFieldEmbedded.?(T, field_name, field_type))) {
                    var obj = try marshal(mem, field_value, options).Object.iterator();
                    while (obj.next()) |pair|
                        _ = try ret.Object.put(pair.key, pair.value);
                } else {
                    var should = if (field_type_id == .Optional) (field_value != null) else true;
                    if (should) // TODO! check "control flow attempts to use compile-time variable at runtime" if above var is either const or directly inside the `if`-cond
                        _ = try ret.Object.put(options.rewriteStructFieldNameToJsonObjectKey.?(T, field_name), try marshal(mem, field_value, options));
                }
            }
        }
        return ret;
    }
    @compileError("please file an issue to support JSON-marshaling of: " ++ @typeName(T));
}

pub fn unmarshal(comptime T: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value, comptime options: *const Options) error{
    MissingField,
    UnexpectedInputValueFormat,
    OutOfMemory,
}!T {
    const type_id = comptime @typeId(T);
    const type_info = comptime @typeInfo(T);
    if (T == *const std.json.Value)
        return from;
    if (T == std.json.Value)
        return from.*;
    if (T == []const u8 or T == []u8)
        return switch (from.*) {
            .String => |jstr| jstr,
            else => error.UnexpectedInputValueFormat,
        };
    if (T == bool)
        return switch (from.*) {
            .Bool => |jbool| jbool,
            .String => |jstr| if (std.mem.eql(u8, "true", jstr)) true else (if (std.mem.eql(u8, "false", jstr)) false else error.UnexpectedInputValueFormat),
            else => error.UnexpectedInputValueFormat,
        };
    if (type_id == .Int)
        return switch (from.*) {
            .Integer => |jint| @intCast(T, jint),
            .Float => |jfloat| if (jfloat < @intToFloat(f64, std.math.minInt(T)) or jfloat > @intToFloat(f64, std.math.maxInt(T)))
                error.UnexpectedInputValueFormat
            else
                @intCast(T, @floatToInt(T, jfloat)),
            .String => |jstr| if (std.fmt.parseInt(T, jstr, 10)) |ok| @intCast(T, ok) else |_| error.UnexpectedInputValueFormat,
            else => error.UnexpectedInputValueFormat,
        };
    if (type_id == .Float)
        return switch (from.*) {
            .Float => |jfloat| @floatCast(T, jfloat),
            .Integer => |jint| @floatCast(T, @intToFloat(T, jint)),
            .String => |jstr| if (std.fmt.parseFloat(T, jstr)) |ok| @floatCast(T, ok) else |_| error.UnexpectedInputValueFormat,
            else => error.UnexpectedInputValueFormat,
        };
    if (type_id == .Enum) {
        const TEnum = std.meta.TagType(T);
        return switch (from.*) {
            .Integer => |jint| std.meta.intToEnum(T, jint) catch error.UnexpectedInputValueFormat,
            .String => |jstr| std.meta.stringToEnum(T, jstr) orelse (if (std.fmt.parseInt(TEnum, jstr, 10)) |i| (std.meta.intToEnum(T, i) catch error.UnexpectedInputValueFormat) else |_| error.UnexpectedInputValueFormat),
            .Float => |jfloat| if (jfloat < @intToFloat(f64, std.math.minInt(TEnum)) or jfloat > @intToFloat(f64, std.math.maxInt(TEnum)))
                error.UnexpectedInputValueFormat
            else
                std.meta.intToEnum(T, @floatToInt(TEnum, jfloat)) catch error.UnexpectedInputValueFormat,
            else => error.UnexpectedInputValueFormat,
        };
    }
    if (type_id == .Void)
        return switch (from.*) {
            .Null => {},
            else => error.UnexpectedInputValueFormat,
        };
    if (type_id == .Optional) switch (from.*) {
        .Null => return null,
        else => if (unmarshal(type_info.Optional.child, mem, from, options)) |ok|
            return ok
        else |err| if (err == error.UnexpectedInputValueFormat and comptime options.set_optionals_null_on_bad_inputs)
            return null
        else
            return err,
    };
    if (type_id == .Pointer) {
        if (type_info.Pointer.size != .Slice) {
            const copy = try unmarshal(type_info.Pointer.child, mem, from, options);
            return try @import("./xstd.mem.zig").enHeap(&mem.allocator, copy);
        }
        switch (from.*) {
            .Array => |jarr| {
                var ret = try mem.allocator.alloc(type_info.Pointer.child, jarr.len);
                for (jarr.items[0..jarr.len]) |*jval, i|
                    ret[i] = try unmarshal(type_info.Pointer.child, mem, jval, options);
                return ret;
            },
            else => return error.UnexpectedInputValueFormat,
        }
    }
    if (type_id == .Struct) {
        switch (from.*) {
            .Object => |*jmap| {
                if (comptime isTypeHashMapLikeDuckwise(T))
                    @compileError("TODO: support JSON-unmarshaling into: " ++ @typeName(T));

                var ret = @import("./xstd.mem.zig").zeroed(T);
                comptime var i = @memberCount(T);
                inline while (i > 0) {
                    i -= 1;
                    const field_name = @memberName(T, i);
                    const field_type = @memberType(T, i);
                    const field_embed = comptime (@typeId(field_type) == .Struct and options.isStructFieldEmbedded.?(T, field_name, field_type));
                    if (field_embed)
                        @field(ret, field_name) = try unmarshal(field_type, mem, from, options)
                    else if (jmap.getValue(options.rewriteStructFieldNameToJsonObjectKey.?(T, field_name))) |*jval|
                        @field(ret, field_name) = try unmarshal(field_type, mem, jval, options)
                    else if (options.err_on_missing_nonvoid_nonoptional_fields) {
                        // return error.MissingField; // TODO! Zig currently segfaults here, check back later
                    }
                }
                return ret;
            },
            else => return error.UnexpectedInputValueFormat,
        }
    }
    @compileError("please file an issue to support JSON-unmarshaling into: " ++ @typeName(T));
}

pub fn nestingDepth(comptime T: type) comptime_int {
    comptime {
        const type_id = @typeId(T);
        const type_info = @typeInfo(T);
        if (T == std.json.Value or T == *std.json.Value or T == *const std.json.Value)
            return 32;
        if (type_id == .Optional)
            return nestingDepth(type_info.Optional.child);
        if (type_id == .Pointer)
            return (if (type_info.Pointer.size == .One) 0 else 1) + nestingDepth(type_info.Pointer.child);
        if (type_id == .Union) {
            var max = 0;
            inline for (type_info.Union.fields) |*field|
                max = std.math.max(max, nestingDepth(field.field_type));
            return max;
        }
        if (type_id == .Struct) {
            var max = 0;
            if (isTypeHashMapLikeDuckwise(T)) {
                Key = @typeInfo(T.KV).Struct.fields[std.meta.fieldIndex(T.KV, "key")].field_type;
                Value = @typeInfo(T.KV).Struct.fields[std.meta.fieldIndex(T.KV, "value")].field_type;
                max = std.math.max(nestingDepth(Key), nestingDepth(Value));
            } else inline for (type_info.Struct.fields) |*field|
                max = std.math.max(max, nestingDepth(field.field_type));
            return 1 + max;
        }
        return 0;
    }
}
