const std = @import("std");

const types = @import("./lsp_types.zig");
const json = @import("./lsp_json.zig");

pub const Engine = struct {
    input: std.io.InStream(std.os.ReadError),
    output: std.io.OutStream(std.os.WriteError),
    mem_alloc_for_arenas: *std.mem.Allocator,

    handlers_requests: [@memberCount(types.RequestIn)]usize = ([_]usize{0}) ** @memberCount(types.RequestIn),
    handlers_notifies: [@memberCount(types.NotifyIn)]usize = ([_]usize{0}) ** @memberCount(types.NotifyIn),

    pub var setup = types.InitializeResult{
        .serverInfo = .{ .name = "" }, // if empty, will be set to `process.args[0]`
        .capabilities = .{},
    };

    pub fn on(self: *Engine, comptime union_member_of_incoming_request_or_notify: var) void {
        const T = @TypeOf(union_member_of_incoming_request_or_notify);
        comptime if (T != types.RequestIn and T != types.NotifyIn)
            @compileError(@typeName(T));

        comptime const idx = @enumToInt(std.meta.activeTag(union_member_of_incoming_request_or_notify));
        const fn_ptr = @ptrToInt(@field(union_member_of_incoming_request_or_notify, @memberName(T, idx)));
        const arr = &(comptime if (T == types.RequestIn) self.handlers_requests else self.handlers_notifies);
        if (arr[idx] != 0 and arr[idx] != fn_ptr)
            @panic("Engine.on(" ++ @memberName(T, idx) ++ ") already subscribed-to, cannot overwrite existing subscriber");
        arr[idx] = fn_ptr;
        std.debug.warn("TAG_IDX {}\t{}\t{}\n", .{ @memberName(T, idx), idx, fn_ptr });
    }

    pub fn serve(self: *Engine) !void {
        var mem_buf = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
        defer mem_buf.deinit();
        const buf = &try std.ArrayList(u8).initCapacity(&mem_buf.allocator, 16 * 1024); // initial cap must be big enough to catch the first occurrence of `Content-Length:` header, from there on out `buf` grows to any Content-Length greater than its current-capacity (which is never shrunk)

        _ = self.on(types.RequestIn{ .initialize = onInitialize });
        _ = self.on(types.NotifyIn{ .__cancelRequest = onCancel });
        _ = self.on(types.NotifyIn{ .exit = onExit });

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

fn handleFullIncomingJsonPayload(self: *Engine, raw_json_bytes: []const u8) !void {
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
                if (try json.unmarshal(types.IntOrString, &mem_keep, id_jsonval)) |id| {
                    if (msg_name) |jstr| switch (jstr) {
                        .String => |method_name| try handleIncomingMsg(types.RequestIn, self, &mem_keep, id, method_name, hashmap.getValue("params")),
                        else => {},
                    } else if (hashmap.getValue("error")) |jerr|
                        std.debug.warn("RESP-ERR\t{}\n", .{jerr}) // TODO: ResponseError
                    else
                        try handleIncomingMsg(types.ResponseIn, self, &mem_keep, id, null, hashmap.getValue("result"));
                }
            } else if (msg_name) |jstr| switch (jstr) {
                .String => |method_name| try handleIncomingMsg(types.NotifyIn, self, &mem_keep, null, method_name, hashmap.getValue("params")),
                else => {},
            };
        },
    }
}

fn handleIncomingMsg(comptime T: type, self: *Engine, mem: *std.heap.ArenaAllocator, id: ?types.IntOrString, method_name: ?[]const u8, payload: ?std.json.Value) !void {
    const method = if (method_name) |name| name else "TODO: fetch from dangling response-awaiters";
    const member_name = @import("./xstd.mem.zig").replaceScalar(u8, try std.mem.dupe(&mem.allocator, u8, method), "$/", '_');

    comptime var i = @memberCount(T);
    inline while (i > 0) {
        i -= 1;
        if (std.mem.eql(u8, @memberName(T, i), member_name)) {
            if (T == types.NotifyIn or T == types.RequestIn) {
                const type_fn_info = @typeInfo(@memberType(T, i)).Fn;
                const paramless = (type_fn_info.args.len == 1);
                const param_val = if (paramless) null else (if (payload) |*p|
                    try json.unmarshal(type_fn_info.args[1].arg_type.?, mem, p)
                else
                    null);
            } else if (T == types.ResponseIn) {
                // TODO
            } else
                @compileError(@typeName(T));
            break;
        }
    }
}

fn onInitialize(mem: *std.heap.ArenaAllocator, params: types.InitializeParams) !types.InitializeResult {
    if (Engine.setup.serverInfo) |*server_info| {
        if (server_info.name.len == 0) {
            const args = try std.process.argsAlloc(&mem.allocator);
            server_info.name = args[0];
        }
    }
    std.debug.warn("\nINIT-REQ\t{}\n\t\t{}\n\n", .{ params, Engine.setup });
    return Engine.setup;
}

fn onCancel(mem: *std.heap.ArenaAllocator, params: types.CancelParams) anyerror!void {
    // TODO
}

fn onExit(mem: *std.heap.ArenaAllocator) anyerror!void {
    std.os.exit(0);
}
