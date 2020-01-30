const std = @import("std");

usingnamespace @import("./types.zig");

const fmt_ritzy = "\n\n==={}===\n{}\n\n";
var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator); // outside of `zig test` should of course `defer .deinit()`...

pub const IncomingRequest = union(enum) {
    negate: fn (Arg(i64)) Ret(i64),
    hostName: fn (Arg(void)) Ret(String),
    envVarValue: fn (Arg(String)) Ret(String),
};
pub const OutgoingRequest = union(enum) {
    pow2: Req(i64, i64),
    rnd: Req(void, f32),
    add: Req(struct {
        a: i64,
        b: i64,
    }, i64),
};
pub const IncomingNotification = union(enum) {
    timeInfo: fn (Arg(TimeInfo)) void,
    shuttingDown: fn (Arg(void)) void,
};
pub const OutgoingNotification = union(enum) {
    envVarNames: []String,
    shoutOut: bool,
};

test "misc" {
    std.debug.assert(@import("zcomptime.zig").isTypeHashMapLikeDuckwise(std.StringHashMap([][]u8)));
}

test "demo" {
    const time_now = @intCast(i64, std.time.timestamp()); // want something guaranteed to be runtime-not-comptime

    const OurApi = @import("./engine.zig").Engine(Spec{
        .newReqId = nextReqId,
        .RequestIn = IncomingRequest,
        .RequestOut = OutgoingRequest,
        .NotifyIn = IncomingNotification,
        .NotifyOut = OutgoingNotification,
    });

    var our_api = OurApi{
        .mem_alloc_for_arenas = std.heap.page_allocator,
    };
    defer our_api.deinit();

    // that was the setup, now some use-cases!

    var json_out_str: []const u8 = undefined;

    our_api.on(IncomingNotification{ .timeInfo = on_timeInfo });
    our_api.on(IncomingRequest{ .negate = on_negate });
    our_api.on(IncomingRequest{ .envVarValue = on_envVarValue });
    our_api.on(IncomingRequest{ .hostName = on_hostName });

    json_out_str = try our_api.out(OutgoingRequest, .rnd, @intCast(i16, 123), With({}, struct {
        pub fn then(ctx: String, in: Ret(f32)) anyerror!void {
            std.debug.warn(fmt_ritzy, .{ ctx, in });
        }
    }));
    printJson(OutgoingRequest, json_out_str); // in reality, send it over your conn to counterparty

    json_out_str = try our_api.out(OutgoingRequest, .pow2, "pow2 ret: ", With(time_now, struct {
        pub fn then(ctx: String, in: Ret(i64)) anyerror!void {
            std.debug.warn(fmt_ritzy, .{ ctx, in });
        }
    }));
    printJson(OutgoingRequest, json_out_str);

    json_out_str = try our_api.out(OutgoingNotification, .envVarNames, {}, try envVarNames());
    printJson(OutgoingNotification, json_out_str);
}

fn printJson(comptime T: type, json_bytes: []const u8) void {
    std.debug.warn(fmt_ritzy, .{ @typeName(T), json_bytes });
}

fn on_timeInfo(in: Arg(TimeInfo)) void {
    std.debug.warn(fmt_ritzy, .{ @typeName(IncomingNotification), in.it });
}

fn on_negate(in: Arg(i64)) Ret(i64) {
    return .{ .ok = -in.it };
}

fn on_hostName(in: Arg(void)) Ret(String) {
    var buf_hostname: [std.os.HOST_NAME_MAX]u8 = undefined;
    if (std.os.gethostname(&buf_hostname)) |host|
        return .{ .ok = host }
    else |err|
        return .{ .err = .{ .code = 54321, .message = @errorName(err) } };
}

fn on_envVarValue(in: Arg(String)) Ret(String) {
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (pair.len > in.it.len and std.mem.startsWith(u8, pair, in.it) and pair[in.it.len] == '=')
            return .{ .ok = pair[in.it.len + 1 .. pair.len - 1] };
    }
    return .{ .err = .{ .code = 12345, .message = in.it } };
}

fn envVarNames() ![]String {
    var ret = try std.ArrayList(String).initCapacity(&mem.allocator, std.os.environ.len);
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (std.mem.indexOfScalar(u8, pair, '=')) |pos|
            try ret.append(pair[0..pos]);
    }
    return ret.toOwnedSlice();
}

fn nextReqId(owner: *std.mem.Allocator) !std.json.Value {
    const counter = struct {
        var req_id: isize = 0;
    };
    counter.req_id += 1;
    var buf = try std.Buffer.init(owner, "demo_req_id_"); // no defer-deinit! would destroy our return value
    try std.fmt.formatIntValue(counter.req_id, "", std.fmt.FormatOptions{}, &buf, @TypeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append);
    return std.json.Value{ .String = buf.toOwnedSlice() };
}

const TimeInfo = struct {
    start: i64,
    now: u64,
};
