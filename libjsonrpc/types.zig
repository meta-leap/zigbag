usingnamespace @import("std");

pub const String = []const u8;

pub const JsonAny = union(enum) {
    string: String,
    boolean: bool,
    int: i64,
    float: f64,
    array: []JsonAny,
    object: ?*StringHashMap(JsonAny),
};

pub const Spec = struct {
    ReqId: type,
    RequestIn: type,
    RequestOut: type,
    NotifyIn: type,
    NotifyOut: type,
};

pub fn Req(comptime TParam: type, comptime TRet: type) type {
    return struct {
        it: TParam = undefined,
        then: var,
    };
}

pub fn In(comptime T: type) type {
    return struct {
        it: T,
        mem: *mem.Allocator,
    };
}

pub fn Out(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ResponseError,

        fn toJsonRpcResponse(self: @This(), id: var) union(enum) {
            with_result: struct {
                id: @TypeOf(id),
                result: T,
            },
            with_error: struct {
                id: @TypeOf(id),
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

pub const ResponseError = struct {
    /// see `ErrorCodes` enumeration
    code: isize,
    message: String,
    data: ?JsonAny = null,
};
