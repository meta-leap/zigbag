const std = @import("std");

usingnamespace @import("./types.zig");

const json = @import("./json.zig");

pub fn Engine(comptime spec: Spec) type {
    return struct {
        mem_alloc_for_arenas: *std.mem.Allocator,
        __shared_out_buf: std.ArrayList(u8) = std.ArrayList(u8){ .len = 0, .items = &[_]u8{}, .allocator = undefined },

        handlers_requests: [@memberCount(spec.RequestIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.RequestIn),
        handlers_notifies: [@memberCount(spec.NotifyIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.NotifyIn),
        // handlers_responses: [@memberCount(spec.TResponseIn)]

        pub fn deinit(self: *const @This()) void {
            if (self.__shared_out_buf.items.len > 0)
                self.__shared_out_buf.deinit();
        }

        pub fn on(self: *@This(), comptime handler: var) void {
            const T = @TypeOf(handler);
            if (T != spec.RequestIn and T != spec.NotifyIn)
                @compileError(@typeName(T));

            const idx = comptime @enumToInt(std.meta.activeTag(handler));
            const fn_ptr = @ptrToInt(@field(handler, @memberName(T, idx)));
            const arr = &(comptime if (T == spec.RequestIn) self.handlers_requests else self.handlers_notifies);
            if (arr[idx]) |_|
                @panic("jsonrpc.Engine.on(" ++ @memberName(T, idx) ++ ") already subscribed-to, cannot overwrite existing subscriber");
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

        pub fn out(self: *const @This(), comptime notify_or_request: var) ![]const u8 {
            const T = @TypeOf(notify_or_request);
            const is_notify = (T == spec.NotifyOut);
            if (T != spec.RequestOut and !is_notify)
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
