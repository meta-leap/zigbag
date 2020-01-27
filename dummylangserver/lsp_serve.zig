const std = @import("std");

const lspt = @import("./lsp_types.zig");
const lspj = @import("./lsp_json.zig");

pub const LangServer = struct {
    input: std.io.InStream(std.os.ReadError),
    output: std.io.OutStream(std.os.WriteError),
    mem_alloc_for_arenas: *std.mem.Allocator,

    handlers_requests: [@memberCount(lspt.RequestIn)]?usize = ([_]?usize{null}) ** @memberCount(lspt.RequestIn),
    handlers_notifies: [@memberCount(lspt.NotifyIn)]?usize = ([_]?usize{null}) ** @memberCount(lspt.NotifyIn),

    pub var setup = lspt.InitializeResult{
        .capabilities = .{},
        .serverInfo = .{ .name = "" }, // if empty, will be set to `process.args[0]`
    };

    pub fn on(self: *LangServer, comptime handler: var) void {
        const T = @TypeOf(handler);
        if (T != lspt.RequestIn and T != lspt.NotifyIn)
            @compileError(@typeName(T));

        const idx = comptime @enumToInt(std.meta.activeTag(handler));
        const fn_ptr = @ptrToInt(@field(handler, @memberName(T, idx)));
        const arr = &(comptime if (T == lspt.RequestIn) self.handlers_requests else self.handlers_notifies);
        if (arr[idx]) |_|
            @panic("LangServer.on(" ++ @memberName(T, idx) ++ ") already subscribed-to, cannot overwrite existing subscriber");
        arr[idx] = fn_ptr;
        std.debug.warn("TAG_IDX {}\t{}\t{}\n", .{ @memberName(T, idx), idx, fn_ptr });
    }

    pub fn serve(self: *LangServer) !void {
        var mem_buf = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
        defer mem_buf.deinit();
        const buf = &try std.ArrayList(u8).initCapacity(&mem_buf.allocator, 16 * 1024); // initial cap must be big enough to catch the first occurrence of `Content-Length:` header, from there on out `buf` grows to any Content-Length greater than its current-capacity (which is never shrunk)

        self.on(lspt.RequestIn{ .initialize = onInitialize });
        self.on(lspt.NotifyIn{ .__cancelRequest = onCancel });
        self.on(lspt.NotifyIn{ .exit = onExit });

        var got_content_len: ?usize = null;
        var did_full_full_msg = false;
        while (true) {
            did_full_full_msg = false;
            const so_far = buf.toSliceConst();

            if (got_content_len == null)
                if (std.mem.indexOf(u8, so_far, "Content-Length:")) |idx|
                    if (idx == 0 or buf.items[idx - 1] == '\n') {
                        const idx_start = idx + "Content-Length:".len;
                        if (std.mem.indexOfScalarPos(u8, so_far, idx_start, '\n')) |idx_newline| {
                            const str_content_len = std.mem.trim(u8, so_far[idx_start..idx_newline], " \t\r");
                            got_content_len = try std.fmt.parseUnsigned(usize, str_content_len, 10);
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
                        try handleFullIncomingJsonPayload(self, buf.items[0..content_len]);

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

fn handleFullIncomingJsonPayload(self: *LangServer, raw_json_bytes: []const u8) !void {
    var mem_json = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
    defer mem_json.deinit();
    var mem_keep = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);

    var json_parser = std.json.Parser.init(&mem_json.allocator, true);
    var json_tree = try json_parser.parse(raw_json_bytes);
    switch (json_tree.root) {
        else => {},
        std.json.Value.Object => |*hashmap| {
            const msg_id = hashmap.getValue("id");
            const msg_name = hashmap.getValue("method");
            if (msg_id) |*id_jsonval| {
                if (try lspj.unmarshal(lspt.IntOrString, &mem_keep, id_jsonval)) |id| {
                    if (msg_name) |jstr| switch (jstr) {
                        .String => |method_name| try handleIncomingMsg(lspt.RequestIn, self, &mem_keep, id, method_name, hashmap.getValue("params")),
                        else => {},
                    } else if (hashmap.getValue("error")) |jerr|
                        std.debug.warn("RESP-ERR\t{}\n", .{jerr}) // TODO: ResponseError
                    else
                        try handleIncomingMsg(lspt.ResponseIn, self, &mem_keep, id, null, hashmap.getValue("result"));
                }
            } else if (msg_name) |jstr| switch (jstr) {
                .String => |method_name| try handleIncomingMsg(lspt.NotifyIn, self, &mem_keep, null, method_name, hashmap.getValue("params")),
                else => {},
            };
        },
    }
}

fn handleIncomingMsg(comptime T: type, self: *LangServer, mem: *std.heap.ArenaAllocator, id: ?lspt.IntOrString, method_name: ?[]const u8, payload: ?std.json.Value) !void {
    const method = if (method_name) |name| name else "TODO: fetch from dangling response-awaiters";
    const member_name = @import("./xstd.mem.zig").replaceScalar(u8, try std.mem.dupe(&mem.allocator, u8, method), "$/", '_');

    comptime var i = @memberCount(T);
    inline while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, @memberName(T, i), member_name)) {
            if (T == lspt.NotifyIn or T == lspt.RequestIn) {
                const TMember = @memberType(T, i);
                const type_fn_info = @typeInfo(TMember).Fn;
                var fn_ret: ?type_fn_info.return_type.? = null;
                if ((if (T == lspt.NotifyIn) self.handlers_notifies else self.handlers_requests)[i]) |fn_ptr| {
                    var fn_arg: type_fn_info.args[0].arg_type.? = undefined;
                    fn_arg.mem = &mem.allocator;
                    const fn_arg_param_type = @TypeOf(fn_arg.it);
                    if (fn_arg_param_type != void)
                        fn_arg.it = if (payload) |*p|
                            (try lspj.unmarshal(fn_arg_param_type, mem, p)) orelse
                                (if (@typeId(fn_arg_param_type) == .Optional) null else return)
                        else
                            return;
                    const fn_val = @intToPtr(TMember, fn_ptr);
                    const fn_ret_tmp = fn_val(fn_arg);
                    fn_ret = fn_ret_tmp; // TODO: ditch useless intermediate const when "broken LLVM module found" goes away
                } else if (T == lspt.RequestIn) {
                    // request not handled by current setup. LSP requires a response for every request with result-or-err. thus send default err response
                }
                if (fn_ret) |ret|
                    std.debug.warn("\n{} RET\t{}\n", .{ member_name, ret });
            } else if (T == lspt.ResponseIn) {
                // TODO
            } else
                @compileError(@typeName(T));
            break;
        }
    }
}

pub fn fail(code: ?isize, message: ?[]const u8, data: ?lspt.JsonAny) lspt.ResponseError {
    return lspt.ResponseError{
        .code = code orelse @enumToInt(lspt.ErrorCodes.InternalError),
        .message = message orelse "unspecified error",
        .data = data,
    };
}

fn onInitialize(in: lspt.In(lspt.InitializeParams)) lspt.Out(lspt.InitializeResult) {
    std.debug.warn("\nINIT-REQ\t{}\n", .{in.it});
    if (LangServer.setup.serverInfo) |*server_info| {
        if (server_info.name.len == 0) {
            _ = fail(12345, "foo", null);
            const args = std.process.argsAlloc(in.mem) catch unreachable;
            server_info.name = args[0];
        }
    }
    return .{ .result = LangServer.setup };
}

fn onCancel(in: lspt.In(lspt.CancelParams)) void {
    // TODO
}

fn onExit(in: lspt.In(void)) void {
    std.os.exit(0);
}
