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

    var engine = OurApi{
        .mem_alloc_for_arenas = std.heap.page_allocator,
    };
    defer engine.deinit();

    engine.on(IncomingNotification{ .timeInfo = on_timeInfo });
    engine.on(IncomingRequest{ .neg = on_neg });
    engine.on(IncomingRequest{ .envVarValue = on_envVarValue });
    engine.on(IncomingRequest{ .hostName = on_hostName });
}

fn on_timeInfo(in: In(TimeInfo)) void {
    std.debug.warn("[NotifyIn]\nonTimeInfo: start={}, now={}\n", .{ in.it.start, in.it.now });
}

fn on_neg(in: In(i64)) Out(i64) {
    return .{ .ok = -in.it };
}

fn on_envVarValue(in: In(String)) Out(String) {
    var i: usize = 0;

    while (i < std.os.environ.len) : (i += 1) {
        const name_value_pair = std.mem.toSlice(u8, std.os.environ[i]);
        if (name_value_pair.len > in.it.len and std.mem.startsWith(u8, name_value_pair, in.it) and name_value_pair[in.it.len] == '=')
            return .{ .ok = name_value_pair[in.it.len + 1 .. name_value_pair.len - 1] };
    }
    return .{ .err = .{ .code = 12345, .message = in.it } };
}

fn on_hostName(in: In(void)) Out(String) {
    var buf_hostname: [std.os.HOST_NAME_MAX]u8 = undefined;
    if (std.os.gethostname(&buf_hostname)) |host|
        return .{ .ok = host }
    else |err|
        return .{ .err = .{ .code = 54321, .message = @errorName(err) } };
}

const TimeInfo = struct {
    start: i64,
    now: u64,
};
