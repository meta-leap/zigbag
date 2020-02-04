const std = @import("std");

const json = @import("./lsp_json.zig");

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
        then: var,
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
        __shared_out_buf: std.ArrayList(u8) = std.ArrayList(u8){ .len = 0, .items = &[_]u8{}, .allocator = undefined },

        handlers_requests: [@memberCount(spec.TRequestIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.TRequestIn),
        handlers_notifies: [@memberCount(spec.TNotifyIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.TNotifyIn),
        // handlers_responses: [@memberCount(spec.TResponseIn)]

        pub fn deinit(self: *@This()) void {
            if (self.__shared_out_buf.items.len > 0)
                self.__shared_out_buf.deinit();
        }

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

        pub fn in(self: *@This(), full_incoming_jsonrpc_msg_payload: []const u8) !void {
            var mem = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem.deinit();
            std.debug.warn("\n\n>>>>>>>>>>>INPUT: {s}<<<<<<<<<<<\n\n", .{full_incoming_jsonrpc_msg_payload});

            var json_parser = std.json.Parser.init(&mem.allocator, true);
            var json_tree = try json_parser.parse(full_incoming_jsonrpc_msg_payload);
            switch (json_tree.root) {
                else => {},
                std.json.Value.Object => |*hashmap| {
                    const msg_id = hashmap.getValue("id");
                    const msg_name = hashmap.getValue("method");
                    if (msg_id) |*id_jsonval| {
                        if (json.unmarshal(spec.TRequestId, &mem, id_jsonval)) |id| {
                            if (msg_name) |jstr| switch (jstr) {
                                .String => |method_name| {
                                    self.__handleIncomingMsg(spec.TRequestIn, &mem, id, method_name, hashmap.getValue("params"));
                                },
                                else => {},
                            } else if (hashmap.getValue("error")) |jerr| {
                                std.debug.warn("RESP-ERR\t{}\n", .{jerr}); // TODO: ResponseError
                            } else {
                                self.__handleIncomingMsg(spec.TRequestOut, &mem, id, null, hashmap.getValue("result"));
                            }
                        }
                    } else if (msg_name) |jstr| switch (jstr) {
                        .String => |method_name| {
                            self.__handleIncomingMsg(spec.TNotifyIn, &mem, null, method_name, hashmap.getValue("params"));
                        },
                        else => {},
                    };
                },
            }
        }

        fn __handleIncomingMsg(self: *@This(), comptime T: type, mem: *std.heap.ArenaAllocator, id: ?spec.TRequestId, method_name: ?[]const u8, payload: ?std.json.Value) void {
            //
        }

        pub fn out(self: *@This(), comptime notify_or_request: var) ![]const u8 {
            const T = @TypeOf(notify_or_request);
            const is_notify = (T == spec.TNotifyOut);
            if (T != spec.TRequestOut and !is_notify)
                @compileError(@typeName(T));
            const idx = comptime @enumToInt(std.meta.activeTag(notify_or_request));

            var mem = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem.deinit();

            var out_msg = std.json.Value{ .Object = std.json.ObjectMap.init(&mem.allocator) };
            _ = try out_msg.Object.put("jsonrpc", .{ .String = "2.0" });
            _ = try out_msg.Object.put("method", .{ .String = @memberName(T, idx) });
            _ = try out_msg.Object.put("params", .{ .Null = {} }); // TODO!
            _ = try out_msg.Object.put("id", .{ .Null = {} }); // TODO!

            if (self.__shared_out_buf.items.len == 0)
                self.__shared_out_buf = try std.ArrayList(u8).initCapacity(self.mem_alloc_for_arenas, 16 * 1024);
            while (true) {
                const nesting_depth = 1024; // TODO! bah..
                var out_to_buf = std.io.SliceOutStream.init(self.__shared_out_buf.items);
                if (out_msg.dumpStream(&out_to_buf.stream, nesting_depth))
                    return self.__shared_out_buf.items[0..out_to_buf.pos]
                else |err| if (err == error.OutOfSpace)
                    try self.__shared_out_buf.ensureCapacity(2 * self.__shared_out_buf.capacity())
                else
                    return err;
            }
            unreachable;
        }
    };
}
