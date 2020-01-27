const std = @import("std");

usingnamespace @import("./lsp_types.zig");
const lspj = @import("./lsp_json.zig");

pub const LangServer = struct {
    input: *std.io.InStream(std.os.ReadError),
    output: *std.io.OutStream(std.os.WriteError),
    mem_alloc_for_arenas: *std.mem.Allocator,
    dbgprint_all_outgoings: bool = true,

    handlers_requests: [@memberCount(RequestIn)]?usize = ([_]?usize{null}) ** @memberCount(RequestIn),
    handlers_notifies: [@memberCount(NotifyIn)]?usize = ([_]?usize{null}) ** @memberCount(NotifyIn),

    pub var setup = InitializeResult{
        .capabilities = .{},
        .serverInfo = .{ .name = "" }, // if empty, will be set to `process.args[0]`
    };

    pub fn on(self: *LangServer, comptime handler: var) void {
        const T = @TypeOf(handler);
        if (T != RequestIn and T != NotifyIn)
            @compileError(@typeName(T));

        const idx = comptime @enumToInt(std.meta.activeTag(handler));
        const fn_ptr = @ptrToInt(@field(handler, @memberName(T, idx)));
        const arr = &(comptime if (T == RequestIn) self.handlers_requests else self.handlers_notifies);
        if (arr[idx]) |_|
            @panic("LangServer.on(" ++ @memberName(T, idx) ++ ") already subscribed-to, cannot overwrite existing subscriber");
        arr[idx] = fn_ptr;
    }

    pub fn serve(self: *LangServer) !void {
        var mem_buf = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
        defer mem_buf.deinit();
        // initial `buf` cap must be big enough to catch the first occurrence of the
        // `Content-Length:` header, from there on out `buf` grows to any Content-Length
        // greater than its current-cap and never shrinks (in cap), so its cap is at any
        // point approx. reflective of the largest incoming message received so far
        const buf = &try std.ArrayList(u8).initCapacity(&mem_buf.allocator, 16 * 1024);

        self.on(RequestIn{ .initialize = onInitialize });
        self.on(NotifyIn{ .__cancelRequest = onCancel });
        self.on(NotifyIn{ .exit = onExit });

        var got_content_len: ?usize = null;
        var did_full_full_msg = false;
        while (true) {
            did_full_full_msg = false;
            const so_far = buf.items[0..buf.len];

            if (got_content_len == null)
                if (std.mem.indexOf(u8, so_far, "Content-Length:")) |idx|
                    if (idx == 0 or buf.items[idx - 1] == '\n') {
                        const idx_start = idx + "Content-Length:".len;
                        if (std.mem.indexOfScalarPos(u8, so_far, idx_start, '\n')) |idx_newline| {
                            const str_content_len = std.mem.trim(u8, so_far[idx_start..idx_newline], " \t\r");
                            got_content_len = try std.fmt.parseUnsigned(usize, str_content_len, 10); // fair to fail here: cannot realistically "recover" from a bad `Content-Length:`
                        }
                    };

            if (got_content_len) |content_len| {
                if (std.mem.indexOf(u8, so_far, "\r\n\r\n")) |idx| {
                    const got = buf.items[idx + 4 .. buf.len];
                    std.mem.copy(u8, buf.items[0..got.len], got);
                    buf.len = got.len;
                    if (got.len < content_len) {
                        try buf.ensureCapacity(content_len);
                        try self.input.readNoEof(buf.items[got.len..(content_len - got.len)]);
                        buf.len = content_len;
                    }

                    did_full_full_msg = true;
                    if (content_len > 0)
                        handleFullIncomingJsonPayload(self, buf.items[0..content_len]);

                    const keep = buf.items[content_len..buf.len];
                    std.mem.copy(u8, buf.items[0..keep.len], keep);
                    buf.len = keep.len;
                    got_content_len = null;
                }
            }

            if (!did_full_full_msg) // might have another full msg in buffer already, no point in waiting around for more input right now, the loop's next iteration will figure this out
                buf.len += read_more: {
                    const num_bytes = try self.input.read(buf.items[buf.len..]);
                    if (num_bytes > 0) break :read_more num_bytes else return error.EndOfStream;
                };
        }
    }
};

fn handleFullIncomingJsonPayload(self: *LangServer, raw_json_bytes: []const u8) void {
    var mem_json = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
    defer mem_json.deinit();
    var mem_keep = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
    defer mem_keep.deinit(); // TODO: move this to proper place when moving to threaded-queuing

    var json_parser = std.json.Parser.init(&mem_json.allocator, true);
    var json_tree = json_parser.parse(raw_json_bytes) catch return;
    switch (json_tree.root) {
        else => {},
        std.json.Value.Object => |*hashmap| {
            const msg_id = hashmap.getValue("id");
            const msg_name = hashmap.getValue("method");
            if (msg_id) |*id_jsonval| {
                if (lspj.unmarshal(IntOrString, &mem_keep, id_jsonval)) |id| {
                    if (msg_name) |jstr| switch (jstr) {
                        .String => |method_name| handleIncomingMsg(RequestIn, self, &mem_keep, id, method_name, hashmap.getValue("params")),
                        else => {},
                    } else if (hashmap.getValue("error")) |jerr|
                        std.debug.warn("RESP-ERR\t{}\n", .{jerr}) // TODO: ResponseError
                    else
                        handleIncomingMsg(ResponseIn, self, &mem_keep, id, null, hashmap.getValue("result"));
                }
            } else if (msg_name) |jstr| switch (jstr) {
                .String => |method_name| handleIncomingMsg(NotifyIn, self, &mem_keep, null, method_name, hashmap.getValue("params")),
                else => {},
            };
        },
    }
}

fn handleIncomingMsg(comptime T: type, self: *LangServer, mem: *std.heap.ArenaAllocator, id: ?IntOrString, method_name: ?[]const u8, payload: ?std.json.Value) void {
    const method = if (method_name) |name| name else "TODO: fetch from dangling response-awaiters";
    const member_name = @import("./xstd.mem.zig").replaceScalar(u8, std.mem.dupe(&mem.allocator, u8, method) catch unreachable, "$/", '_');

    comptime var i = @memberCount(T);
    inline while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, @memberName(T, i), member_name)) {
            if (T == NotifyIn or T == RequestIn) {
                const TUnionMember = @memberType(T, i);
                const fn_info = @typeInfo(TUnionMember).Fn;
                var fn_ret: ?fn_info.return_type.? = null;
                if ((if (T == NotifyIn) self.handlers_notifies else self.handlers_requests)[i]) |fn_ptr_uint| {
                    const fn_ref = @intToPtr(TUnionMember, fn_ptr_uint);
                    var fn_arg: fn_info.args[0].arg_type.? = undefined;
                    fn_arg.mem = &mem.allocator;
                    const fn_arg_param_type = @TypeOf(fn_arg.it);
                    if (fn_arg_param_type != void)
                        fn_arg.it = if (payload) |*p|
                            lspj.unmarshal(fn_arg_param_type, mem, p) orelse
                                (if (@typeId(fn_arg_param_type) == .Optional) null else return)
                        else
                            (if (@typeId(fn_arg_param_type) == .Optional) null else return);

                    fn_ret = fn_ref(fn_arg);
                    if (T == RequestIn and @memberType(fn_info.return_type.?, 0) != void)
                        sendRaw(mem, self, lspj.marshal(mem, fn_ret.?.toJsonRpcResponse(id.?))) catch unreachable;
                } else if (T == RequestIn) {
                    // request not handled by current setup. LSP requires a response for every request with result-or-err. thus send default err response
                }
                if (fn_ret) |ret|
                    std.debug.warn("\n{} RET\t{}\n", .{ member_name, ret });
            } else if (T == ResponseIn) {
                // TODO
            } else
                @compileError(@typeName(T));
            return;
        }
    }
    if (T == RequestIn) {
        const err = Out(void){ .err = fail(@enumToInt(ErrorCodes.MethodNotFound), method, null) };
        sendRaw(mem, self, lspj.marshal(mem, err.toJsonRpcResponse(id.?))) catch {};
    }
}

fn sendRaw(mem: *std.heap.ArenaAllocator, self: *LangServer, json_value: std.json.Value) !void {
    var buf: [1024 * 1024]u8 = undefined;
    var stream = std.io.SliceOutStream.init(&buf);
    try json_value.dumpStream(&stream.stream, 1024);
    const str = stream.getWritten();
    if (self.dbgprint_all_outgoings)
        std.debug.warn("\n\n>>>>>>>>>>>Content-Length: {d}\r\n\r\n{s}<<<<<<<<<<<\n\n", .{ str.len, str });
    self.output.print("Content-Length: {d}\r\n\r\n{s}", .{ str.len, str }) catch unreachable;
}

pub fn fail(code: ?isize, message: ?[]const u8, data: ?JsonAny) ResponseError {
    return ResponseError{
        .code = code orelse @enumToInt(ErrorCodes.InternalError),
        .message = message orelse "unknown error",
        .data = data,
    };
}

fn onInitialize(in: In(InitializeParams)) Out(InitializeResult) {
    std.debug.warn("\nINIT-REQ\t{}\n", .{in.it});
    if (LangServer.setup.serverInfo) |*server_info|
        if (server_info.name.len == 0) {
            const args = std.process.argsAlloc(in.mem) catch unreachable;
            server_info.name = args[0];
        };
    return .{ .ok = LangServer.setup };
}

fn onCancel(in: In(CancelParams)) void {
    // TODO
}

fn onExit(in: In(void)) void {
    std.os.exit(0);
}
