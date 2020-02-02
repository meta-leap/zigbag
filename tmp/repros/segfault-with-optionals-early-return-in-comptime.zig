const std = @import("std");

const TimeInfo = struct {
    start: i64,
    now: ?u64,
};

pub const OptionsRepro = struct {
    err_on_missing_nonvoid_nonoptional_fields: bool = true,
    isStructFieldEmbedded: fn (type, []const u8, type) bool,
};

test "" {
    try main();
}

pub fn main() !void {
    var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer mem.deinit();

    var jval = std.json.Value{ .Object = std.json.ObjectMap.init(&mem.allocator) };
    _ = try jval.Object.put("start", std.json.Value{ .Integer = 123 });
    _ = try jval.Object.put("now", std.json.Value{ .Integer = 321 });

    var timeinfo = try unmarshalRepro(TimeInfo, &mem, &jval, &OptionsRepro{
        .isStructFieldEmbedded = defaultIsStructFieldEmbedded,
    });
    std.debug.warn("\n\nYUP:\t{}\n\n", .{timeinfo});
}

pub fn unmarshalRepro(comptime T: type, mem: *std.heap.ArenaAllocator, from: *const std.json.Value, comptime options: *const OptionsRepro) error{
    MissingField,
    UnexpectedInputValueFormat,
    OutOfMemory,
}!T {
    const type_id = comptime @typeId(T);
    const type_info = comptime @typeInfo(T);
    if (type_id == .Int)
        return switch (from.*) {
            .Integer => |jint| @intCast(T, jint),
            else => error.UnexpectedInputValueFormat,
        };
    if (type_id == .Optional) switch (from.*) {
        .Null => return null,
        else => if (unmarshalRepro(type_info.Optional.child, mem, from, options)) |ok|
            return ok
        else |err|
            return err,
    };
    if (type_id == .Struct) {
        switch (from.*) {
            .Object => |*jmap| {
                var ret: T = undefined;
                comptime var i = @memberCount(T);
                inline while (i > 0) {
                    i -= 1;
                    const field_name = @memberName(T, i);
                    const field_type = @memberType(T, i);
                    const field_embed = comptime (@typeId(field_type) == .Struct and options.isStructFieldEmbedded(T, field_name, field_type));
                    if (field_embed)
                        @field(ret, field_name) = try unmarshalRepro(field_type, mem, from, options)
                    else if (jmap.getValue(field_name)) |*jval|
                        @field(ret, field_name) = try unmarshalRepro(field_type, mem, jval, options)
                    else if (options.err_on_missing_nonvoid_nonoptional_fields) {
                        return error.MissingField; // TODO! Zig currently segfaults here
                    }
                }
                return ret;
            },
            else => return error.UnexpectedInputValueFormat,
        }
    }
    @compileError(@typeName(T));
}

fn defaultIsStructFieldEmbedded(comptime struct_type: type, field_name: []const u8, comptime field_type: type) bool {
    return false; // std.mem.eql(u8, field_name, @typeName(field_type));
}
