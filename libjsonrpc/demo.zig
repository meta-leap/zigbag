const std = @import("std");

usingnamespace @import("./types.zig");
const json = @import("./json.zig");

var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator); // outside of `zig test` should of course `defer .deinit()`...

test "demo" {
    const time_now = @intCast(i64, std.time.timestamp()); // want something guaranteed to be runtime-not-comptime

    const IncomingRequest = union(enum) {
        envVarValue: fn (In(String)) Ret(String),
        neg: fn (In(i64)) Ret(i64),
        hostName: fn (In(void)) Ret(String),
    };
    const OutgoingRequest = union(enum) {
        add: Req(struct {
            a: i64,
            b: i64,
        }, i64, void),
        rnd: Req(void, f32, String),
        pow2: Req(i64, i64, void),
    };
    const IncomingNotification = union(enum) {
        timeInfo: fn (In(TimeInfo)) void,
        shuttingDown: fn (In(void)) void,
    };
    const OutgoingNotification = union(enum) {
        envVarNames: []String,
        shoutOut: bool,
    };

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

    our_api.on(IncomingNotification{ .timeInfo = on_timeInfo });
    our_api.on(IncomingRequest{ .neg = on_neg });
    our_api.on(IncomingRequest{ .envVarValue = on_envVarValue });
    our_api.on(IncomingRequest{ .hostName = on_hostName });

    var jsonstr: []const u8 = undefined;

    // jsonstr = our_api.out(OutgoingRequest, .pow2, Req(i64, i64){
    //     .it = time_now,
    //     .then = .{ .foo = 123 },
    // }) catch unreachable;
    // printJson(OutgoingRequest, jsonstr);

    const RndResp = struct {
        fn then(ctx: String, in: Ret(f32)) void {
            std.debug.warn("\n\n==={s}===\n{}\n\n", .{ ctx, in });
        }
    };
    jsonstr = our_api.out(OutgoingRequest, .rnd, Req(void, f32, String){
        .it = {},
        .then = RndResp.then,
    }) catch unreachable;
    printJson(OutgoingRequest, jsonstr);

    jsonstr = our_api.out(OutgoingNotification, .envVarNames, envVarNames()) catch unreachable;
    printJson(OutgoingNotification, jsonstr);
}

fn printJson(comptime T: type, jsonstr: []const u8) void {
    std.debug.warn("\n\n===" ++ @typeName(T) ++ "===\n{}\n\n", .{jsonstr});
}

fn on_timeInfo(in: In(TimeInfo)) void {
    std.debug.warn("\n\n===NotifyIn===\nonTimeInfo: start={}, now={}\n\n", .{ in.it.start, in.it.now });
}

fn on_neg(in: In(i64)) Ret(i64) {
    return .{ .ok = -in.it };
}

fn on_hostName(in: In(void)) Ret(String) {
    var buf_hostname: [std.os.HOST_NAME_MAX]u8 = undefined;
    if (std.os.gethostname(&buf_hostname)) |host|
        return .{ .ok = host }
    else |err|
        return .{ .err = .{ .code = 54321, .message = @errorName(err) } };
}

fn on_envVarValue(in: In(String)) Ret(String) {
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (pair.len > in.it.len and std.mem.startsWith(u8, pair, in.it) and pair[in.it.len] == '=')
            return .{ .ok = pair[in.it.len + 1 .. pair.len - 1] };
    }
    return .{ .err = .{ .code = 12345, .message = in.it } };
}

fn envVarNames() []String {
    var ret = std.ArrayList(String).initCapacity(&mem.allocator, std.os.environ.len) catch unreachable;
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (std.mem.indexOfScalar(u8, pair, '=')) |pos|
            ret.append(pair[0..pos]) catch unreachable;
    }
    return ret.toOwnedSlice();
}

var req_id: isize = 0;

fn nextReqId() !std.json.Value {
    req_id += 1;
    var buf = try std.Buffer.init(&mem.allocator, "fooya");
    defer buf.deinit();
    try std.fmt.formatIntValue(req_id, "", std.fmt.FormatOptions{}, &buf, @TypeOf(std.Buffer.append).ReturnType.ErrorSet, std.Buffer.append);
    return std.json.Value{ .String = buf.toOwnedSlice() };
}

const TimeInfo = struct {
    start: i64,
    now: u64,
};
