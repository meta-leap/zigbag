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

pub fn Req(comptime TParam: type, comptime TRet: type) type {
    return struct {
        t_ret: ?*TRet = null, // never "used" (as a value), always null: just carries the req/resp return-type info for unmarshal-result-on-response
        param: TParam,
        then_fn_ptr: usize, // fn (TCtx, Ret(TRet)) void
    };
}

fn RetType(comptime T: type) type {
    const TArg = @typeInfo(std.meta.declarationInfo(T, "then").data.Fn.fn_type).Fn.args[1].arg_type.?;
    return @typeInfo(TArg).Union.fields[std.meta.fieldIndex(TArg, "ok").?].field_type;
}

pub fn With(in: var, comptime TThenStruct: type) Req(@TypeOf(in), RetType(TThenStruct)) {
    return WithRet(in, RetType(TThenStruct), TThenStruct);
}

pub fn WithRet(in: var, comptime TRet: type, comptime TThenStruct: type) Req(@TypeOf(in), TRet) {
    // comptime var TFunc: type = @TypeOf(TThenStruct.then); // fn([]const u8, types.Ret(f32)) void
    // var fn_ref: TFunc = TThenStruct.then;
    // var fn_ptr = @ptrToInt(fn_ref);
    // var ret: Req(@TypeOf(in), TRet) = undefined;
    // ret.t_ret = null;
    // ret.param = in;
    // ret.then_fn_ptr = fn_ptr;
    return Req(@TypeOf(in), TRet){
        .param = in,
        .then_fn_ptr = @ptrToInt(TThenStruct.then),
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
