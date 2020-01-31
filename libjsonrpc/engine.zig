const std = @import("std");

usingnamespace @import("./types.zig");

const json = @import("./json.zig");

pub fn Engine(comptime spec: Spec, comptime jsonOptions: json.Options) type {
    const InternalState = struct {
        const ResponseAwaiter = struct {
            mem_arena: std.heap.ArenaAllocator,
            req_id: @TypeOf(spec.newReqId).ReturnType,
            ptr_ctx: usize,
            ptr_fn: usize,
        };
        shared_out_buf: ?std.ArrayList(u8) = null,
        handlers_notifies: [@memberCount(spec.NotifyIn)]?usize,
        handlers_requests: [@memberCount(spec.RequestIn)]?usize,
        handlers_responses: ?std.ArrayList(ResponseAwaiter) = null,
        fn jsonValueToBytes(self: *@This(), mem: *std.mem.Allocator, json_value: *const std.json.Value, comptime nesting_depth: comptime_int) ![]const u8 {
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
                    self.shared_out_buf = try std.ArrayList(u8).initCapacity(mem, 16 * 1024);
            }
        }
    };

    comptime var json_options: json.Options = jsonOptions;
    comptime {
        if (json_options.isStructFieldEmbedded == null)
            json_options.isStructFieldEmbedded = defaultIsFieldEmbedded;
        if (json_options.rewriteZigFieldNameToJsonObjectKey == null)
            json_options.rewriteZigFieldNameToJsonObjectKey = defaultRewriteZigFieldNameToJsonObjectKey;
        if (json_options.rewriteUnionFieldNameToJsonRpcMethodName == null)
            json_options.rewriteUnionFieldNameToJsonRpcMethodName = defaultRewriteUnionFieldNameToJsonRpcMethodName;
        if (json_options.rewriteJsonRpcMethodNameToUnionFieldName == null)
            json_options.rewriteJsonRpcMethodNameToUnionFieldName = defaultRewriteJsonRpcMethodNameToUnionFieldName;
    }

    return struct {
        mem_alloc_for_arenas: *std.mem.Allocator,
        __: InternalState = InternalState{
            .handlers_notifies = ([_]?usize{null}) ** @memberCount(spec.NotifyIn),
            .handlers_requests = ([_]?usize{null}) ** @memberCount(spec.RequestIn),
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

        pub fn notify(self: *@This(), comptime tag: @TagType(spec.NotifyOut), req_ctx: var, payload: @memberType(spec.NotifyOut, @enumToInt(tag))) ![]const u8 {
            return self.out(spec.NotifyOut, tag, req_ctx, payload);
        }

        pub fn request(self: *@This(), comptime tag: @TagType(spec.RequestOut), req_ctx: var, payload: @memberType(spec.RequestOut, @enumToInt(tag))) ![]const u8 {
            return self.out(spec.RequestOut, tag, req_ctx, payload);
        }

        pub fn on(self: *@This(), comptime handler: var) void {
            const T = @TypeOf(handler);
            comptime std.debug.assert(T == spec.RequestIn or T == spec.NotifyIn);

            const idx = comptime @enumToInt(std.meta.activeTag(handler));
            const fn_ptr = @ptrToInt(@field(handler, @memberName(T, idx)));
            const arr = &(comptime if (T == spec.RequestIn) self.__.handlers_requests else self.__.handlers_notifies);
            arr[idx] = fn_ptr;
        }

        pub fn out(self: *@This(), comptime T: type, comptime tag: @TagType(T), req_ctx: var, payload: @memberType(T, @enumToInt(tag))) ![]const u8 {
            const is_request = (T == spec.RequestOut);
            comptime std.debug.assert(is_request or T == spec.NotifyOut);

            var mem_local = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem_local.deinit();

            const idx = @enumToInt(tag);
            const method_member_name = @memberName(T, idx);

            var out_msg = std.json.Value{ .Object = std.json.ObjectMap.init(&mem_local.allocator) };
            const param = if (is_request) payload.param else payload;
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
                const ctx = try mem_keep.allocator.create(@TypeOf(req_ctx));
                ctx.* = req_ctx;
                try self.__.handlers_responses.?.append(InternalState.ResponseAwaiter{
                    .mem_arena = mem_keep,
                    .req_id = req_id,
                    .ptr_ctx = @ptrToInt(ctx),
                    .ptr_fn = payload.then_fn_ptr,
                });
                // if (std.mem.eql(u8, "demo_req_id_2", req_id.String)) {
                //     const then = @intToPtr(fn (String, Ret(i64)) anyerror!void, payload.then_fn_ptr);
                //     try then(ctx.*, Ret(i64){ .ok = @intCast(i64, 12345) });
                // } else if (std.mem.eql(u8, "demo_req_id_1", req_id.String)) {
                //     const then = @intToPtr(fn (String, Ret(f32)) anyerror!void, payload.then_fn_ptr);
                //     try then(ctx.*, Ret(f32){ .ok = @floatCast(f32, 123.45) });
                // }
            }
            return self.__.jsonValueToBytes(self.mem_alloc_for_arenas, &out_msg, 64); // TODO! nesting-depth..
        }

        pub fn in(self: *@This(), full_incoming_jsonrpc_msg_payload: []const u8) !?[]const u8 {
            var mem_local = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem_local.deinit();
            // std.debug.warn("\n\n>>>>>INCOMING>>>>>{s}<<<<<<<<<<\n\n", .{full_incoming_jsonrpc_msg_payload});

            var msg: struct {
                id: ?*std.json.Value = null,
                method: String = undefined,
                params: ?*std.json.Value = null,
                result_ok: ?*std.json.Value = null,
                result_err: ?ResponseError = null,
                kind: json.Options.MsgKind = undefined,
            } = .{};

            // first: gather what we can for `msg`
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

            // next: *now* handle `msg`
            switch (msg.kind) {
                .notification => {
                    inline for (@typeInfo(spec.NotifyIn).Union.fields) |*spec_field, idx|
                        if (std.mem.eql(u8, spec_field.name, msg.method)) {
                            if (self.__.handlers_notifies[idx]) |fn_ptr_uint| {
                                const fn_type = @typeInfo(spec_field.field_type).Fn;
                                const param_type = @typeInfo(fn_type.args[0].arg_type.?).Struct.fields[0].field_type;
                                const param_val: param_type = if (msg.params) |params|
                                    try json.unmarshal(param_type, &mem_local, params, json_options)
                                else if (param_type == void)
                                    undefined
                                else if (@typeId(param_type) == .Optional)
                                    null
                                else
                                    return error.MsgNotifyInParamsMissing;
                                const fn_ptr = @intToPtr(spec_field.field_type, fn_ptr_uint);
                                fn_ptr(.{ .it = param_val, .mem = &mem_local.allocator });
                            }
                            return null;
                        };
                    return error.MsgNotifyInUnknownMethod;
                },

                .request => {
                    inline for (@typeInfo(spec.RequestIn).Union.fields) |*spec_field, idx|
                        if (std.mem.eql(u8, spec_field.name, msg.method)) {
                            if (self.__.handlers_requests[idx]) |fn_ptr_uint| {
                                const fn_type = @typeInfo(spec_field.field_type).Fn;
                                const param_type = @typeInfo(fn_type.args[0].arg_type.?).Struct.fields[0].field_type;
                                const param_val: param_type = if (msg.params) |params|
                                    try json.unmarshal(param_type, &mem_local, params, json_options)
                                else if (param_type == void)
                                    undefined
                                else if (@typeId(param_type) == .Optional)
                                    null
                                else
                                    return error.MsgRequestInParamsMissing;
                                const fn_ptr = @intToPtr(spec_field.field_type, fn_ptr_uint);
                                const fn_ret = fn_ptr(.{ .it = param_val, .mem = &mem_local.allocator });
                                return try self.__.jsonValueToBytes(self.mem_alloc_for_arenas, &(try json.marshal(&mem_local, fn_ret.toJsonRpcResponse(msg.id), json_options)), 64);
                            }
                            return null;
                        };
                    return try self.__.jsonValueToBytes(self.mem_alloc_for_arenas, &(try json.marshal(&mem_local, ResponseError{
                        .code = @enumToInt(ErrorCodes.MethodNotFound),
                        .message = msg.method,
                    }, json_options)), 64);
                },

                .response => {
                    return null;
                },
            }
        }
    };
}

fn defaultRewriteZigFieldNameToJsonObjectKey(comptime TStruct: type, field_name: []const u8) []const u8 {
    return field_name;
}

fn defaultIsFieldEmbedded(comptime struct_type: type, field_name: []const u8, comptime field_type: type) bool {
    return false; // std.mem.eql(u8, field_name, @typeName(field_type));
}

fn defaultRewriteUnionFieldNameToJsonRpcMethodName(comptime union_type: type, comptime union_field_idx: comptime_int, comptime union_field_name: []const u8) []const u8 {
    return union_field_name;
}

fn defaultRewriteJsonRpcMethodNameToUnionFieldName(incoming_kind: json.Options.MsgKind, jsonrpc_method_name: []const u8) []const u8 {
    return jsonrpc_method_name;
}
