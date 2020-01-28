const std = @import("std");

pub const String = []const u8;

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
    data: ?JsonAny,
};

pub fn Req(comptime TParam: type, comptime TRet: type) type {
    return struct {
        it: TParam = undefined,
        state: var,
    };
}

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

        fn toJsonRpcResponse(self: @This(), id: var) ?union(enum) {
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

pub const JsonAny = union(enum) {
    string: String,
    boolean: bool,
    int: i64,
    float: f64,
    array: []JsonAny,
    object: ?*std.StringHashMap(JsonAny),
};

pub const Spec = struct {
    TRequestId: type,
    TRequestIn: type,
    TRequestOut: type,
    TNotifyIn: type,
    TNotifyOut: type,
};

pub fn Protocol(comptime spec: Spec) type {
    return struct {
        mem_alloc_for_arenas: *std.mem.Allocator,

        handlers_requests: [@memberCount(spec.TRequestIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.TRequestIn),
        handlers_notifies: [@memberCount(spec.TNotifyIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.TNotifyIn),
        // handlers_responses: [@memberCount(spec.TResponseIn)]

        pub fn on(self: *@This(), comptime handler: var) void {
            const T = @TypeOf(handler);
            if (T != spec.TRequestIn and T != spec.TNotifyIn)
                @compileError(@typeName(T));

            const idx = comptime @enumToInt(std.meta.activeTag(handler));
            const fn_ptr = @ptrToInt(@field(handler, @memberName(T, idx)));
            const arr = &(comptime if (T == spec.TRequestIn) self.handlers_requests else self.handlers_notifies);
            if (arr[idx]) |_|
                @panic("jsonrpc.Protocol.on(" ++ @memberName(T, idx) ++ ") already subscribed-to, cannot overwrite existing subscriber");
            arr[idx] = fn_ptr;
        }

        pub fn in(self: *@This(), full_incoming_jsonrpc_msg_payload: []const u8) void {
            var mem_json = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem_json.deinit();
            var mem_keep = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem_keep.deinit(); // TODO: move this to proper place when moving to threaded-queuing

            var json_parser = std.json.Parser.init(&mem_json.allocator, true);
            var json_tree = json_parser.parse(full_incoming_jsonrpc_msg_payload) catch return;
            switch (json_tree.root) {
                else => {},
                std.json.Value.Object => |*hashmap| {
                    const msg_id = hashmap.getValue("id");
                    const msg_name = hashmap.getValue("method");
                    if (msg_id) |*id_jsonval| {
                        // if (lspj.unmarshal(spec.TRequestId, &mem_keep, id_jsonval)) |id| {
                        //     if (msg_name) |jstr| switch (jstr) {
                        //         .String => |method_name| handleIncomingMsg(RequestIn, self, &mem_keep, id, method_name, hashmap.getValue("params")),
                        //         else => {},
                        //     } else if (hashmap.getValue("error")) |jerr|
                        //         std.debug.warn("RESP-ERR\t{}\n", .{jerr}) // TODO: ResponseError
                        //     else
                        //         handleIncomingMsg(ResponseIn, self, &mem_keep, id, null, hashmap.getValue("result"));
                        // }
                    } else if (msg_name) |jstr| switch (jstr) {
                        .String => |method_name| handleIncomingMsg(spec.TNotifyIn, self, &mem_keep, null, method_name, hashmap.getValue("params")),
                        else => {},
                    };
                },
            }
        }

        fn handleIncomingMsg(comptime T: type, self: *@This(), mem: *std.heap.ArenaAllocator, id: ?spec.TRequestId, method_name: ?[]const u8, payload: ?std.json.Value) void {}

        pub fn out(self: *@This(), notify_or_request: var, on_response: var) void {
            const TResp = @TypeOf(on_response);
            const is_notify = (TResp == void);
            if ((!is_notify) and @typeId(TResp) != .Struct) // coarse check only here, no full struct decls scrutinizing.. users rtfm
                @compileError("jsonrpc.Protocol.out: on_response arg must be void or a struct with a .then(Out(T)) instance method, not " ++ @typeName(TResp));
        }
    };
}
