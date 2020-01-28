const std = @import("std");

pub const ErrorCodes = enum(i32) {
    ParseError = -32700,
    InvalidRequest = -32600,
    MethodNotFound = -32601,
    InvalidParams = -32602,
    InternalError = -32603,
    serverErrorStart = -32099,
    serverErrorEnd = -32000,
    ServerNotInitialized = -32002,
    UnknownErrorCode = -32001,
};

pub fn In(comptime T: type) type {
    return struct {
        it: T,
        mem: *std.mem.Allocator,
    };
}

pub fn Out(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ResponseError,

        fn toJsonRpcResponse(self: @This(), id: IntOrString) ?union(enum) {
            with_result: struct {
                id: IntOrString,
                result: T,
            },
            with_error: struct {
                id: IntOrString,
                error__: ResponseError,
            },
        } {
            return switch (self) {
                .ok => |it| .{ .with_result = .{ .id = id, .result = it } },
                .err => |e| .{ .with_error = .{ .id = id, .error__ = e } },
            };
        }
    };
}

pub const JsonAny = union(enum) {
    string: String,
    boolean: bool,
    int: i64,
    float: f64,
    array: []JsonAny,
    object: ?*std.StringHashMap(JsonAny),
};

pub const Spec = struct {
    TRequestIn: type,
    TResponseOut: type,
    TRequestOut: type,
    TResponseIn: type,
    TNotifyIn: type,
    TNotifyOut: type,
};

pub fn Protocol(comptime spec: Spec) type {
    return struct {
        mem_alloc_for_arenas: *std.mem.Allocator,

        handlers_requests: [@memberCount(spec.TRequestIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.TRequestIn),
        handlers_notifies: [@memberCount(spec.TNotifyIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.TNotifyIn),

        pub fn on(self: *Protocol, comptime handler: var) void {
            const T = @TypeOf(handler);
            if (T != spec.TRequestIn and T != spec.TNotifyIn)
                @compileError(@typeName(T));

            const idx = comptime @enumToInt(std.meta.activeTag(handler));
            const fn_ptr = @ptrToInt(@field(handler, @memberName(T, idx)));
            const arr = &(comptime if (T == spec.TRequestIn) self.handlers_requests else self.handlers_notifies);
            if (arr[idx]) |_|
                @panic("jsonrpc2.Protocol.on(" ++ @memberName(T, idx) ++ ") already subscribed-to, cannot overwrite existing subscriber");
            arr[idx] = fn_ptr;
        }

        pub fn in(self: *Protocol, msg: *std.json.Value) void {}

        pub fn out(self: *Protocol) void {}
    };
}
