const std = @import("std");

usingnamespace @import("./types.zig");

const String = []const u8;

const fmt_ritzy = "\n\n=== {} ===\n{}\n";
var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator); // outside of `zig test` should of course `defer .deinit()`...

const our_api = Spec{
    .newReqId = nextReqId,

    .RequestIn = union(enum) {
        negate: fn (Arg(i64)) Ret(i64),
        hostName: fn (Arg(void)) Ret([]u8),
        envVarValue: fn (Arg(String)) Ret(String),
    },

    .RequestOut = union(enum) {
        pow2: Req(i64, i64),
        rnd: Req(bool, f32),
        // add: Req(struct {
        //     a: i64,
        //     b: i64,
        // }, i64),
    },

    .NotifyIn = union(enum) {
        timeInfo: fn (Arg(TimeInfo)) void,
        shuttingDown: fn (Arg(void)) void,
    },

    .NotifyOut = union(enum) {
        envVarNames: []String,
        shoutOut: bool,
    },
};

test "demo" {
    const time_now = @intCast(i64, std.time.milliTimestamp()); // want something guaranteed to be runtime-not-comptime

    const Engine = @import("./engine.zig").
        Engine(our_api, @import("./json.zig").Options{});

    var our_rpc = Engine{
        .onOutgoing = onOutput,
        .mem_alloc_for_arenas = std.heap.page_allocator,
    };
    defer our_rpc.deinit();

    // that was the SETUP, now some USAGE:

    var json_out_str: []const u8 = undefined;

    our_rpc.on(our_api.NotifyIn{ .timeInfo = on_timeInfo });
    our_rpc.on(our_api.NotifyIn{ .shuttingDown = on_shuttingDown });
    our_rpc.on(our_api.RequestIn{ .negate = on_negate });
    our_rpc.on(our_api.RequestIn{ .envVarValue = on_envVarValue });
    our_rpc.on(our_api.RequestIn{ .hostName = on_hostName });

    try our_rpc.incoming("{ \"id\": 1, \"method\": \"envVarValue\", \"params\": \"GOPATH\" }");
    try our_rpc.incoming("{ \"id\": 2, \"method\": \"hostName\" }");
    try our_rpc.incoming("{ \"id\": 3, \"method\": \"negate\", \"params\": 42.42 }");

    try our_rpc.request(.rnd, @intCast(i16, 12321), With(true, struct {
        pub fn then(ctx: i16, in: Ret(f32)) void {
            std.debug.warn(fmt_ritzy, .{ ctx, in });
        }
    }));

    try our_rpc.incoming("{ \"method\": \"timeInfo\", \"params\": {\"start\": 123, \"now\": 321} }");
    try our_rpc.incoming("{ \"id\": \"demo_req_id_1\", \"result\": 123.456 }");

    try our_rpc.request(.pow2, @intCast(i16, 12121), With(time_now, struct {
        pub fn then(ctx: i16, in: Ret(i64)) void {
            std.debug.warn(fmt_ritzy, .{ ctx, in });
        }
    }));

    try our_rpc.notify(.shoutOut, true);
    try our_rpc.notify(.envVarNames, try demo_envVarNames());

    try our_rpc.incoming("{ \"id\": \"demo_req_id_2\", \"error\": { \"code\": 12345, \"message\": \"No pow2 to you!\" } }");
    try our_rpc.incoming("{ \"method\": \"shuttingDown\" }");
}

fn onOutput(json_bytes: []const u8) void {
    std.debug.warn(fmt_ritzy, .{ "Outgoing JSON", json_bytes });
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
    now: ?u64,
};

fn on_timeInfo(in: Arg(TimeInfo)) void {
    std.debug.warn(fmt_ritzy, .{ "on_timeInfo", in.it });
}

fn on_shuttingDown(in: Arg(void)) void {
    std.debug.warn(fmt_ritzy, .{ "on_shuttingDown", in.it });
}

fn on_negate(in: Arg(i64)) Ret(i64) {
    return .{ .ok = -in.it };
}

fn on_hostName(in: Arg(void)) Ret([]u8) {
    var buf_hostname: [std.os.HOST_NAME_MAX]u8 = undefined;
    if (std.os.gethostname(&buf_hostname)) |host| {
        return .{ .ok = std.mem.dupe(in.mem, u8, host) catch unreachable }; // TODO!
    } else |err|
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

fn demo_envVarNames() ![]String {
    var ret = try std.ArrayList(String).initCapacity(&mem.allocator, std.os.environ.len);
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (std.mem.indexOfScalar(u8, pair, '=')) |pos|
            try ret.append(pair[0..pos]);
    }
    return ret.toOwnedSlice();
}

test "misc" {
    std.testing.expect(@import("zcomptime.zig").isTypeHashMapLikeDuckwise(std.StringHashMap([][]u8)));
}
