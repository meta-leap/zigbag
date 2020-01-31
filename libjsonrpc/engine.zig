const std = @import("std");

usingnamespace @import("./types.zig");

const json = @import("./json.zig");

pub fn Engine(comptime spec: Spec) type {
    const InternalState = struct {
        const ResponseHandler = struct {
            mem_arena: std.heap.ArenaAllocator,
            req_id: @TypeOf(spec.newReqId).ReturnType,
            ptr_ctx: usize,
            ptr_fn: usize,
        };
        shared_out_buf: ?std.ArrayList(u8) = null,
        handlers_notifies: [@memberCount(spec.NotifyIn)]?usize,
        handlers_requests: [@memberCount(spec.RequestIn)]?usize,
        handlers_responses: ?std.ArrayList(ResponseHandler) = null,
    };

    return struct {
        mem_alloc_for_arenas: *std.mem.Allocator,
        debug_print_outgoings: bool = false,
        debug_print_incomings: bool = true,
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

        pub fn in(self: *const @This(), full_incoming_jsonrpc_msg_payload: []const u8) !void {
            var mem_local = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem_local.deinit();
            if (self.debug_print_incomings)
                std.debug.warn("\n\n>>>>>INCOMING>>>>>{s}<<<<<<<<<<\n\n", .{full_incoming_jsonrpc_msg_payload});

            var json_parser = std.json.Parser.init(&mem_local.allocator, true);
            var json_tree = try json_parser.parse(full_incoming_jsonrpc_msg_payload);
            switch (json_tree.root) {
                else => {},
                std.json.Value.Object => |*hashmap| {
                    const msg_id = hashmap.getValue("id");
                    const msg_name = hashmap.getValue("method");
                    if (msg_id) |*id_jsonval| {
                        if (msg_name) |jstr| switch (jstr) {
                            .String => |method_name| {
                                // self.__handleIncomingMsg(spec.RequestIn, &mem_local, id, method_name, hashmap.getValue("params"));
                            },
                            else => {},
                        } else if (hashmap.getValue("error")) |jerr| {
                            std.debug.warn("RESP-ERR\t{}\n", .{jerr}); // TODO: ResponseError
                        } else {
                            // self.__handleIncomingMsg(spec.RequestOut, &mem_local, id, null, hashmap.getValue("result"));
                        }
                    } else if (msg_name) |jstr| switch (jstr) {
                        .String => |method_name| {
                            // self.__handleIncomingMsg(spec.NotifyIn, &mem_local, null, method_name, hashmap.getValue("params"));
                        },
                        else => {},
                    };
                },
            }
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
                _ = try out_msg.Object.put("params", try json.marshal(&mem_local, param));
            _ = try out_msg.Object.put("jsonrpc", .{ .String = "2.0" });
            _ = try out_msg.Object.put("method", .{ .String = method_member_name });

            if (is_request) {
                var mem_keep = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
                const req_id = try spec.newReqId(&mem_keep.allocator);
                _ = try out_msg.Object.put("id", req_id);

                if (self.__.handlers_responses == null)
                    self.__.handlers_responses = try std.ArrayList(InternalState.ResponseHandler).initCapacity(self.mem_alloc_for_arenas, 8);
                const ctx = try mem_keep.allocator.create(@TypeOf(req_ctx));
                ctx.* = req_ctx;
                try self.__.handlers_responses.?.append(InternalState.ResponseHandler{
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

            while (true) {
                if (self.__.shared_out_buf) |*shared_out_buf| {
                    const nesting_depth = 8; // TODO! bah..
                    var out_to_buf = std.io.SliceOutStream.init(shared_out_buf.items);
                    if (out_msg.dumpStream(&out_to_buf.stream, nesting_depth))
                        return shared_out_buf.items[0..out_to_buf.pos]
                    else |err| if (err == error.OutOfSpace)
                        try shared_out_buf.ensureCapacity(2 * shared_out_buf.capacity())
                    else
                        return err;
                } else
                    self.__.shared_out_buf = try std.ArrayList(u8).initCapacity(self.mem_alloc_for_arenas, 16 * 1024);
            }
        }
    };
}
