const std = @import("std");

usingnamespace @import("./types.zig");

const json = @import("./json.zig");

pub fn Engine(comptime spec: Spec) type {
    const ResponseHandler = struct {
        mem_arena: std.heap.ArenaAllocator,
        req_id: @TypeOf(spec.newReqId).ReturnType,
        ptr_ctx: usize,
        ptr_fn: usize,
    };

    return struct {
        mem_alloc_for_arenas: *std.mem.Allocator,
        shared_out_buf: std.ArrayList(u8) = std.ArrayList(u8){ .len = 0, .items = &[_]u8{}, .allocator = undefined },

        handlers_requests: [@memberCount(spec.RequestIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.RequestIn),
        handlers_notifies: [@memberCount(spec.NotifyIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.NotifyIn),
        handlers_responses: std.ArrayList(ResponseHandler) = std.ArrayList(ResponseHandler){ .len = 0, .items = &[_]ResponseHandler{}, .allocator = undefined },

        pub fn deinit(self: *const @This()) void {
            if (self.shared_out_buf.capacity() > 0)
                self.shared_out_buf.deinit();
            if (self.handlers_responses.capacity() > 0) {
                var i: usize = 0;
                while (i < self.handlers_responses.len) : (i += 1)
                    self.handlers_responses.items[i].mem_arena.deinit();
                self.handlers_responses.deinit();
            }
        }

        pub fn on(self: *@This(), comptime handler: var) void {
            const T = @TypeOf(handler);
            comptime std.debug.assert(T == spec.RequestIn or T == spec.NotifyIn);

            const idx = comptime @enumToInt(std.meta.activeTag(handler));
            const fn_ptr = @ptrToInt(@field(handler, @memberName(T, idx)));
            const arr = &(comptime if (T == spec.RequestIn) self.handlers_requests else self.handlers_notifies);
            arr[idx] = fn_ptr;
        }

        pub fn in(self: *const @This(), full_incoming_jsonrpc_msg_payload: []const u8) !void {
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
                        if (json.unmarshal(spec.ReqId, &mem, id_jsonval)) |id| {
                            if (msg_name) |jstr| switch (jstr) {
                                .String => |method_name| {
                                    self.__handleIncomingMsg(spec.RequestIn, &mem, id, method_name, hashmap.getValue("params"));
                                },
                                else => {},
                            } else if (hashmap.getValue("error")) |jerr| {
                                std.debug.warn("RESP-ERR\t{}\n", .{jerr}); // TODO: ResponseError
                            } else {
                                self.__handleIncomingMsg(spec.RequestOut, &mem, id, null, hashmap.getValue("result"));
                            }
                        }
                    } else if (msg_name) |jstr| switch (jstr) {
                        .String => |method_name| {
                            self.__handleIncomingMsg(spec.NotifyIn, &mem, null, method_name, hashmap.getValue("params"));
                        },
                        else => {},
                    };
                },
            }
        }

        fn __handleIncomingMsg(self: *const @This(), comptime T: type, mem: *std.heap.ArenaAllocator, id: ?spec.ReqId, method_name: ?[]const u8, payload: ?std.json.Value) void {
            //
        }

        pub fn out(self: *@This(), comptime T: type, comptime tag: @TagType(T), req_ctx: var, payload: @memberType(T, @enumToInt(tag))) ![]const u8 {
            const is_notify = (T == spec.NotifyOut);
            comptime std.debug.assert(is_notify or T == spec.RequestOut);

            var mem_local = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
            defer mem_local.deinit();

            const idx = @enumToInt(tag);
            const method_member_name = @memberName(T, idx);

            var out_msg = std.json.Value{ .Object = std.json.ObjectMap.init(&mem_local.allocator) };
            _ = try out_msg.Object.put("jsonrpc", .{ .String = "2.0" });
            _ = try out_msg.Object.put("method", .{ .String = method_member_name });
            if (is_notify and @TypeOf(payload) != void)
                _ = try out_msg.Object.put("params", try json.marshal(&mem_local, payload))
            else if ((!is_notify) and @TypeOf(payload.it) != void)
                _ = try out_msg.Object.put("params", try json.marshal(&mem_local, payload.it));
            if (!is_notify) {
                var mem_keep = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
                const req_id = try spec.newReqId(&mem_keep.allocator);
                _ = try out_msg.Object.put("id", req_id);

                if (self.handlers_responses.capacity() == 0)
                    self.handlers_responses = try std.ArrayList(ResponseHandler).initCapacity(self.mem_alloc_for_arenas, 8);
                const ctx = try mem_keep.allocator.create(@TypeOf(req_ctx));
                ctx.* = req_ctx;
                try self.handlers_responses.append(ResponseHandler{
                    .mem_arena = mem_keep,
                    .req_id = req_id,
                    .ptr_ctx = @ptrToInt(ctx),
                    .ptr_fn = payload.on,
                });
                // if (std.mem.eql(u8, "demo_req_id_2", req_id.String)) {
                //     var handler = @intToPtr(fn (String, Ret(i64)) anyerror!void, payload.on);
                //     try handler(ctx.*, Ret(i64){ .ok = @intCast(i64, 12345) });
                // } else if (std.mem.eql(u8, "demo_req_id_1", req_id.String)) {
                //     var handler = @intToPtr(fn (String, Ret(f32)) anyerror!void, payload.on);
                //     try handler(ctx.*, Ret(f32){ .ok = @floatCast(f32, 123.45) });
                // }
            }

            if (self.shared_out_buf.capacity() == 0)
                self.shared_out_buf = try std.ArrayList(u8).initCapacity(self.mem_alloc_for_arenas, 16 * 1024);
            while (true) {
                const nesting_depth = 1024; // TODO! bah..
                var out_to_buf = std.io.SliceOutStream.init(self.shared_out_buf.items);
                if (out_msg.dumpStream(&out_to_buf.stream, nesting_depth))
                    return self.shared_out_buf.items[0..out_to_buf.pos]
                else |err| if (err == error.OutOfSpace)
                    try self.shared_out_buf.ensureCapacity(2 * self.shared_out_buf.capacity())
                else
                    return err;
            }
            unreachable;
        }
    };
}
