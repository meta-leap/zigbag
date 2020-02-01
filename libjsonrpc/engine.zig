const std = @import("std");

usingnamespace @import("./types.zig");

const json = @import("./json.zig");

const tmp_json_depth = 128; // TODO! compute depth statically

pub fn Engine(comptime spec: Spec, comptime jsonOptions: json.Options) type {
    comptime var json_options = @import("./zcomptime.zig").copyWithAllNullsSetFrom(json.Options, &jsonOptions, json.Options{
        .isStructFieldEmbedded = defaultIsStructFieldEmbedded,
        .rewriteStructFieldNameToJsonObjectKey = defaultRewriteStructFieldNameToJsonObjectKey,
        .rewriteUnionFieldNameToJsonRpcMethodName = defaultRewriteUnionFieldNameToJsonRpcMethodName,
        .rewriteJsonRpcMethodNameToUnionFieldName = defaultRewriteJsonRpcMethodNameToUnionFieldName,
    });

    return struct {
        // force_single_threaded: bool = @import("builtin").single_threaded,
        mem_alloc_for_arenas: *std.mem.Allocator,
        onOutgoing: fn ([]const u8) void,

        __: InternalState = InternalState{
            .handlers_notifies = [_]?usize{null} ** @memberCount(spec.NotifyIn),
            .handlers_requests = [_]?usize{null} ** @memberCount(spec.RequestIn),
        },

        pub fn deinit(self: *const @This()) void {
            if (self.__.shared_out_buf) |*shared_out_buf|
                shared_out_buf.deinit();
            if (self.__.handlers_responses) |*handlers_responses| {
                var i: usize = 0;
                while (i < handlers_responses.len) : (i += 1)
                    handlers_responses.items[i].mem_arena.deinit();
                handlers_responses.deinit();
            }
        }

        pub fn notify(self: *@This(), comptime tag: @TagType(spec.NotifyOut), param: @memberType(spec.NotifyOut, @enumToInt(tag))) !void {
            return self.out(spec.NotifyOut, tag, undefined, param, null);
        }

        pub fn request(self: *@This(), comptime tag: @TagType(spec.RequestOut), req_ctx: var, param: @typeInfo(@memberType(spec.RequestOut, @enumToInt(tag))).Struct.fields[0].field_type, comptime ThenStruct: type) !void {
            return self.out(spec.RequestOut, tag, req_ctx, param, ThenStruct);
        }

        pub fn on(self: *@This(), comptime handler: var) void {
            const T = @TypeOf(handler);
            comptime std.debug.assert(T == spec.RequestIn or T == spec.NotifyIn);

            const idx = comptime @enumToInt(std.meta.activeTag(handler));
            const fn_ptr = @ptrToInt(@field(handler, @memberName(T, idx)));
            const arr = &(comptime if (T == spec.RequestIn) self.__.handlers_requests else self.__.handlers_notifies);
            arr[idx] = fn_ptr;
        }

        fn out(self: *@This(), comptime T: type, comptime tag: @TagType(T), req_ctx: var, param: var, comptime ThenStruct: ?type) !void {
            const is_request = (T == spec.RequestOut);
            comptime std.debug.assert(is_request or T == spec.NotifyOut);

            var mem_local = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem_local.deinit();

            const idx = @enumToInt(tag);
            const method_member_name = @memberName(T, idx);

            var out_msg = std.json.Value{ .Object = std.json.ObjectMap.init(&mem_local.allocator) };
            if (@TypeOf(param) != void)
                _ = try out_msg.Object.put("params", try json.marshal(&mem_local, param, json_options));
            _ = try out_msg.Object.put("jsonrpc", .{ .String = "2.0" });
            _ = try out_msg.Object.put("method", .{ .String = json_options.rewriteUnionFieldNameToJsonRpcMethodName.?(T, idx, method_member_name) });

            if (is_request) {
                var mem_keep = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
                const req_id = try spec.newReqId(&mem_keep.allocator);
                _ = try out_msg.Object.put("id", req_id);

                if (self.__.handlers_responses == null)
                    self.__.handlers_responses = try std.ArrayList(InternalState.ResponseAwaiter).initCapacity(self.mem_alloc_for_arenas, 8);

                const ReqCtx = @typeInfo(@TypeOf(ThenStruct.?.then)).Fn.args[0].arg_type orelse
                    @compileError("your `then`s arg 0 must have a non-`var` (pointer) type");
                if (@typeId(ReqCtx) != .Pointer and ReqCtx != void)
                    @compileError("your `then`s arg 0 must have a pointer type");
                const ReqCtxVal = if (ReqCtx == void) void else @typeInfo(ReqCtx).Pointer.child;
                var ctx: *ReqCtxVal = undefined;
                if (ReqCtxVal != void) {
                    ctx = try mem_keep.allocator.create(ReqCtxVal);
                    ctx.* = if (@typeId(@TypeOf(ReqCtx)) == .Pointer) req_ctx.* else req_ctx;
                }
                try self.__.handlers_responses.?.append(InternalState.ResponseAwaiter{
                    .mem_arena = mem_keep,
                    .req_id = req_id,
                    .req_union_idx = idx,
                    .ptr_ctx = if (@sizeOf(ReqCtxVal) == 0) 0 else @ptrToInt(ctx),
                    .ptr_fn = @ptrToInt(ThenStruct.?.then),
                });
            }
            const json_out_bytes_in_shared_buf = try self.__.dumpJsonValueToSharedBuf(self.mem_alloc_for_arenas, &out_msg, tmp_json_depth);
            self.onOutgoing(try std.mem.dupe(&mem_local.allocator, u8, json_out_bytes_in_shared_buf));
        }

        pub fn incoming(self: *@This(), full_incoming_jsonrpc_msg_payload: []const u8) !void {
            var mem_local = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem_local.deinit();

            var msg: struct {
                id: ?*std.json.Value = null,
                method: []const u8 = undefined,
                params: ?*std.json.Value = null,
                result_ok: ?*std.json.Value = null,
                result_err: ?ResponseError = null,
                kind: json.Options.MsgKind = undefined,
            } = .{};

            // FIRST: gather what we can for `msg`
            switch ((try std.json.Parser.init(&mem_local.allocator, true).parse(full_incoming_jsonrpc_msg_payload)).root) {
                else => return error.MsgIsNoJsonObj,
                std.json.Value.Object => |*hashmap| {
                    if (hashmap.getValue("id")) |*jid|
                        msg.id = jid;
                    if (hashmap.getValue("error")) |*jerror|
                        msg.result_err = try json.unmarshal(ResponseError, &mem_local, jerror, json_options);
                    if (hashmap.getValue("result")) |*jresult|
                        msg.result_ok = jresult;
                    if (hashmap.getValue("params")) |*jparams|
                        msg.params = jparams;

                    msg.kind = if (msg.id) |_|
                        (if (msg.result_err == null and msg.result_ok == null) json.Options.MsgKind.request else json.Options.MsgKind.response)
                    else
                        json.Options.MsgKind.notification;

                    if (hashmap.getValue("method")) |jmethod| switch (jmethod) {
                        .String => |jstr| msg.method = json_options.rewriteJsonRpcMethodNameToUnionFieldName.?(msg.kind, jstr),
                        else => return error.MsgMalformedMethodField,
                    } else if (msg.kind != json.Options.MsgKind.response)
                        return error.MsgMissingMethodField;
                },
            }

            // NEXT: *now* handle `msg`
            switch (msg.kind) {
                .notification => {
                    inline for (@typeInfo(spec.NotifyIn).Union.fields) |*spec_field, idx|
                        if (std.mem.eql(u8, spec_field.name, msg.method)) {
                            if (self.__.handlers_notifies[idx]) |fn_ptr_uint| {
                                const fn_type = @typeInfo(spec_field.field_type).Fn;
                                const param_type = @typeInfo(fn_type.args[0].arg_type.?).Struct.fields[std.meta.fieldIndex(fn_type.args[0].arg_type.?, "it").?].field_type;
                                const param_val: param_type = if (msg.params) |params|
                                    try json.unmarshal(param_type, &mem_local, params, json_options)
                                else if (param_type == void)
                                    undefined
                                else if (@typeId(param_type) == .Optional)
                                    null
                                else
                                    return error.MsgParamsMissing;
                                const fn_ptr = @intToPtr(spec_field.field_type, fn_ptr_uint);
                                fn_ptr(.{ .it = param_val, .mem = &mem_local.allocator });
                            }
                            return;
                        };
                    return error.MsgUnknownMethod;
                },

                .request => {
                    inline for (@typeInfo(spec.RequestIn).Union.fields) |*spec_field, idx|
                        if (std.mem.eql(u8, spec_field.name, msg.method)) {
                            if (self.__.handlers_requests[idx]) |fn_ptr_uint| {
                                const fn_type = @typeInfo(spec_field.field_type).Fn;
                                const param_type = @typeInfo(fn_type.args[0].arg_type.?).Struct.fields[std.meta.fieldIndex(fn_type.args[0].arg_type.?, "it").?].field_type;
                                const param_val: param_type = if (msg.params) |params|
                                    try json.unmarshal(param_type, &mem_local, params, json_options)
                                else if (param_type == void)
                                    undefined
                                else if (@typeId(param_type) == .Optional)
                                    null
                                else
                                    return error.MsgParamsMissing;
                                const fn_ptr = @intToPtr(spec_field.field_type, fn_ptr_uint);
                                const fn_ret = fn_ptr(.{ .it = param_val, .mem = &mem_local.allocator });
                                const json_out_bytes_in_shared_buf = try self.__.dumpJsonValueToSharedBuf(self.mem_alloc_for_arenas, &(try json.marshal(&mem_local, fn_ret.toJsonRpcResponse(msg.id), json_options)), tmp_json_depth);
                                return self.onOutgoing(try std.mem.dupe(&mem_local.allocator, u8, json_out_bytes_in_shared_buf));
                            }
                            return;
                        };
                    const json_out_bytes_in_shared_buf = try self.__.dumpJsonValueToSharedBuf(self.mem_alloc_for_arenas, &(try json.marshal(&mem_local, ResponseError{
                        .code = @enumToInt(ErrorCodes.MethodNotFound),
                        .message = msg.method,
                    }, json_options)), tmp_json_depth);
                    return self.onOutgoing(try std.mem.dupe(&mem_local.allocator, u8, json_out_bytes_in_shared_buf));
                },

                .response => {
                    if (self.__.handlers_responses) |*handlers_responses| {
                        for (handlers_responses.items[0..handlers_responses.len]) |*response_awaiter, i| {
                            if (@import("./xstd.json.zig").eql(response_awaiter.req_id, msg.id.?.*)) {
                                defer {
                                    response_awaiter.mem_arena.deinit();
                                    _ = handlers_responses.swapRemove(i);
                                }
                                inline for (@typeInfo(spec.RequestOut).Union.fields) |*spec_field, idx| {
                                    if (response_awaiter.req_union_idx == idx) {
                                        const TResponse = std.meta.declarationInfo(spec_field.field_type, "Result").data.Type;
                                        const TThenFuncCtxHave = fn (usize, Ret(TResponse)) void;
                                        const TThenFuncCtxVoid = fn (void, Ret(TResponse)) void;
                                        var fn_arg: Ret(TResponse) = undefined;
                                        if (msg.result_err) |err|
                                            fn_arg = Ret(TResponse){ .err = err }
                                        else if (msg.result_ok) |ret|
                                            fn_arg = Ret(TResponse){ .ok = try json.unmarshal(TResponse, &response_awaiter.mem_arena, ret, json_options) }
                                        else
                                            fn_arg = Ret(TResponse){ .err = ResponseError{ .code = 0, .message = "unreachable" } }; // unreachable; // TODO! Zig currently segfaults here, check back later

                                        if (response_awaiter.ptr_ctx == 0) {
                                            var fn_then = @intToPtr(TThenFuncCtxVoid, response_awaiter.ptr_fn);
                                            fn_then(undefined, fn_arg);
                                        } else {
                                            var fn_then = @intToPtr(TThenFuncCtxHave, response_awaiter.ptr_fn);
                                            fn_then(response_awaiter.ptr_ctx, fn_arg);
                                        }
                                        return;
                                    }
                                }
                                return error.MsgUnknownReqId;
                            }
                        }
                    }
                    return error.MsgUnknownReqId;
                },
            }
        }

        const InternalState = struct {
            const ResponseAwaiter = struct {
                mem_arena: std.heap.ArenaAllocator,
                req_id: std.json.Value,
                req_union_idx: usize,
                ptr_ctx: usize,
                ptr_fn: usize,
            };

            shared_out_buf: ?std.ArrayList(u8) = null,
            handlers_notifies: [@memberCount(spec.NotifyIn)]?usize,
            handlers_requests: [@memberCount(spec.RequestIn)]?usize,
            handlers_responses: ?std.ArrayList(ResponseAwaiter) = null,

            fn dumpJsonValueToSharedBuf(self: *@This(), owner: *std.mem.Allocator, json_value: *const std.json.Value, comptime nesting_depth: comptime_int) ![]const u8 {
                while (true) {
                    if (self.shared_out_buf) |*shared_out_buf| {
                        var out_to_buf = std.io.SliceOutStream.init(shared_out_buf.items);
                        if (json_value.dumpStream(&out_to_buf.stream, nesting_depth))
                            return shared_out_buf.items[0..out_to_buf.pos]
                        else |err| if (err == error.OutOfSpace)
                            try shared_out_buf.ensureCapacity(2 * shared_out_buf.capacity())
                        else
                            return err;
                    } else
                        self.shared_out_buf = try std.ArrayList(u8).initCapacity(owner, 16 * 1024);
                }
            }
        };
    };
}

fn defaultRewriteStructFieldNameToJsonObjectKey(comptime TStruct: type, field_name: []const u8) []const u8 {
    return field_name;
}

fn defaultIsStructFieldEmbedded(comptime struct_type: type, field_name: []const u8, comptime field_type: type) bool {
    return false; // std.mem.eql(u8, field_name, @typeName(field_type));
}

fn defaultRewriteUnionFieldNameToJsonRpcMethodName(comptime union_type: type, comptime union_field_idx: comptime_int, comptime union_field_name: []const u8) []const u8 {
    return union_field_name;
}

fn defaultRewriteJsonRpcMethodNameToUnionFieldName(incoming_kind: json.Options.MsgKind, jsonrpc_method_name: []const u8) []const u8 {
    return jsonrpc_method_name;
}
