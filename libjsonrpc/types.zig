const std = @import("std");

pub const String = []const u8;

pub const Spec = struct {
    newReqId: fn (owner: *std.mem.Allocator) anyerror!std.json.Value,
    RequestIn: type,
    RequestOut: type,
    NotifyIn: type,
    NotifyOut: type,
};

pub fn Req(comptime TParam: type, comptime TRet: type) type {
    return struct {
        param: TParam,

        /// fn (TCtx, Ret(TRet)) !void,
        then_fn_ptr: usize,
    };
}

fn WithRetType(comptime T: type) type {
    return @typeInfo(@typeInfo(std.meta.declarationInfo(T, "then").data.Fn.fn_type).Fn.args[1].arg_type.?).Union.fields[0].field_type;
}

pub fn With(in: var, comptime TThen: type) Req(@TypeOf(in), WithRetType(TThen)) {
    return WithRet(in, WithRetType(TThen), TThen);
}

pub fn WithRet(in: var, comptime TRet: type, comptime TThen: type) Req(@TypeOf(in), TRet) {
    return Req(@TypeOf(in), TRet){
        .param = in,
        .then_fn_ptr = @ptrToInt(TThen.then),
    };
}

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
            },
            with_error: struct {
                id: @TypeOf(id),
                error__: ResponseError,
            },
        } {
            return switch (self) {
                .ok => |ok| .{ .with_result = .{ .id = id, .result = ok } },
                .err => |err| .{ .with_error = .{ .id = id, .error__ = err } },
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
    data: std.json.Value = std.json.Value{ .Null = {} },
};
