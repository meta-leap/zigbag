const std = @import("std");

usingnamespace @import("./types.zig");
const json = @import("./json.zig");

test "demo" {
    var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer mem.deinit();

    const time_now = @intCast(i64, std.time.timestamp()); // want something guaranteed to be runtime-not-comptime

    const IncomingRequest = union(enum) {
        envVarValue: fn (In(String)) Out(String),
        neg: fn (In(i64)) Out(i64),
        hostName: fn (In(void)) Out(String),
    };
    const OutgoingRequest = union(enum) {
        add: Req(struct {
            a: i64,
            b: i64,
        }, i64),
        pow2: Req(i64, i64),
        rnd: Req(void, f32),
    };
    const IncomingNotification = union(enum) {
        timeInfo: fn (In(TimeInfo)) void,
    };
    const OutgoingNotification = union(enum) {
        envVarNames: []String,
    };

    const OurApi = @import("./engine.zig").Engine(Spec{
        .ReqId = String,
        .RequestIn = IncomingRequest,
        .RequestOut = OutgoingRequest,
        .NotifyIn = IncomingNotification,
        .NotifyOut = OutgoingNotification,
    });

    var our_api = OurApi{
        .mem_alloc_for_arenas = std.heap.page_allocator,
    };
    defer our_api.deinit();

    our_api.on(IncomingNotification{ .timeInfo = on_timeInfo });
    our_api.on(IncomingRequest{ .neg = on_neg });
    our_api.on(IncomingRequest{ .envVarValue = on_envVarValue });
    our_api.on(IncomingRequest{ .hostName = on_hostName });

    var jsonstr = our_api.out(OutgoingNotification{
        .envVarNames = envVarNames(&mem.allocator),
    }) catch unreachable;
    std.debug.warn("\n\n===NotifyOut===\n{}\n\n", .{jsonstr});
}

fn on_timeInfo(in: In(TimeInfo)) void {
    std.debug.warn("\n\n===NotifyIn===\nonTimeInfo: start={}, now={}\n\n", .{ in.it.start, in.it.now });
}

fn on_neg(in: In(i64)) Out(i64) {
    return .{ .ok = -in.it };
}

fn on_hostName(in: In(void)) Out(String) {
    var buf_hostname: [std.os.HOST_NAME_MAX]u8 = undefined;
    if (std.os.gethostname(&buf_hostname)) |host|
        return .{ .ok = host }
    else |err|
        return .{ .err = .{ .code = 54321, .message = @errorName(err) } };
}

fn on_envVarValue(in: In(String)) Out(String) {
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (pair.len > in.it.len and std.mem.startsWith(u8, pair, in.it) and pair[in.it.len] == '=')
            return .{ .ok = pair[in.it.len + 1 .. pair.len - 1] };
    }
    return .{ .err = .{ .code = 12345, .message = in.it } };
}

fn envVarNames(mem: *std.mem.Allocator) []String {
    var ret = std.ArrayList(String).initCapacity(mem, std.os.environ.len) catch unreachable;
    for (std.os.environ) |name_value_pair, i| {
        const pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (std.mem.indexOfScalar(u8, pair, '=')) |pos|
            ret.append(pair[0..pos]) catch unreachable;
    }
    return ret.toSlice();
}

const TimeInfo = struct {
    start: i64,
    now: u64,
};
