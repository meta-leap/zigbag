const std = @import("std");

const types = @import("./lsp_types.zig");
const json = @import("./lsp_json.zig");

pub const Engine = struct {
    input: std.io.InStream(std.os.ReadError),
    output: std.io.OutStream(std.os.WriteError),
    mem_alloc_for_arenas: *std.mem.Allocator,

    handlers_requests: [@memberCount(types.RequestIn)][]usize = ([_][]usize{&[_]usize{}}) ** @memberCount(types.RequestIn),
    handlers_notifies: [@memberCount(types.NotifyIn)][]usize = ([_][]usize{&[_]usize{}}) ** @memberCount(types.NotifyIn),

    pub fn on(self: *Engine, comptime union_member_of_incoming_request_or_notify: var) void {
        const T = @TypeOf(union_member_of_incoming_request_or_notify);
        if (T != types.RequestIn and T != types.NotifyIn)
            @compileError(@typeName(T));
        comptime const idx = @enumToInt(std.meta.activeTag(union_member_of_incoming_request_or_notify));
        const fn_ptr = @ptrToInt(@field(union_member_of_incoming_request_or_notify, @memberName(T, idx)));
        var slice = if (T == types.RequestIn) self.handlers_requests[idx] else self.handlers_notifies[idx];
        for (slice) |fn_ptr_have|
            if (fn_ptr_have == fn_ptr)
                return;

        (if (T == types.RequestIn) self.handlers_requests else self.handlers_notifies)[idx] = slice;
        std.debug.warn("TAG_IDX\t{}\t{}\n", .{ idx, fn_ptr });
    }

    pub fn serve(self: *Engine) !void {
        var mem_buf = std.heap.ArenaAllocator.init(self.mem_alloc_for_arenas);
        defer mem_buf.deinit();
        const buf = &try std.ArrayList(u8).initCapacity(&mem_buf.allocator, 16 * 1024); // initial cap must be big enough to catch the first occurrence of `Content-Length:` header, from there on out `buf` grows to any Content-Length greater than its current-capacity (which is never shrunk)

        self.on(types.RequestIn{ .initialize = onInitializeRequest });
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

            if (!did_full_full_msg) // might have another full msg in buffer already, no point in reading further for now
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
            if (T == types.NotifyIn) {} else if (T == types.RequestIn) {
                const type_fn_info = @typeInfo(@memberType(T, i)).Fn;
                if (type_fn_info.args.len == 0) {
                    // TODO!
                } else {
                    const arg_type = comptime type_fn_info.args[0].arg_type.?;
                    const arg_ptr: ?arg_type = if (payload) |*p|
                        try json.unmarshal(type_fn_info.args[0].arg_type.?, mem, p)
                    else
                        null;
                }
            } else if (T == types.ResponseIn) {} else
                @compileError(@typeName(T));
            break;
        }
    }
}

fn onInitializeRequest(params: *types.InitializeParams) void {
    std.debug.warn("INIT-REQ\t{}\n", .{params.*});
}
