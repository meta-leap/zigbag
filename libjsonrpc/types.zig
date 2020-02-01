const std = @import("std");

pub const ErrorCodes = enum(isize) {
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

pub const ResponseError = struct {
    /// see `ErrorCodes` enumeration
    code: isize,
    message: []const u8,
    data: ?*std.json.Value = null,
};

pub const Spec = struct {
    newReqId: fn (owner: *std.mem.Allocator) anyerror!std.json.Value,
    RequestIn: type,
    RequestOut: type,
    NotifyIn: type,
    NotifyOut: type,
};

pub fn Arg(comptime T: type) type {
    return struct {
        it: T,
        mem: *std.mem.Allocator,
    };
}

pub fn Ret(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ResponseError,

        fn toJsonRpcResponse(self: @This(), id: var) union(enum) {
            with_result: struct {
                id: @TypeOf(id),
                result: T,
                jsonrpc: []const u8 = "2.0",
            },
            with_error: struct {
                id: @TypeOf(id),
                error__: ResponseError,
                jsonrpc: []const u8 = "2.0",
            },
        } {
            return switch (self) {
                .ok => |ok| .{ .with_result = .{ .id = id, .result = ok } },
                .err => |err| .{ .with_error = .{ .id = id, .error__ = err } },
            };
        }
    };
}
