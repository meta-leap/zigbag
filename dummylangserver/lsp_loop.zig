const std = @import("std");

pub const Engine = struct {
    input: std.io.InStream(std.os.ReadError),
    output: std.io.OutStream(std.os.WriteError),
    memAllocForArenas: *std.mem.Allocator,

    pub fn serve(self: *Engine) !void {
        var mem_buf = std.heap.ArenaAllocator.init(self.memAllocForArenas);
        defer mem_buf.deinit();

        const buf = &try std.ArrayList(u8).initCapacity(&mem_buf.allocator, 16 * 1024);
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
                        try self.onFullIncomingPayload(buf.items[0..content_len]);

                    const keep = buf.items[content_len..buf.len];
                    std.mem.copy(u8, buf.items[0..keep.len], keep);
                    buf.len = keep.len;
                    got_content_len = null;
                }
            }

            if (!did_full_full_msg)
                buf.len += read_more: {
                    const num_bytes = try self.input.read(buf.items[buf.len..]);
                    if (num_bytes > 0) break :read_more num_bytes else return error.EndOfStream;
                };
        }
    }

    fn onFullIncomingPayload(self: *Engine, raw_json_bytes: []const u8) !void {
        var mem = std.heap.ArenaAllocator.init(self.memAllocForArenas);
        defer mem.deinit();

        var json_parser = std.json.Parser.init(&mem.allocator, true);
        var json_tree = try json_parser.parse(raw_json_bytes);
        switch (json_tree.root) {
            else => {},
            std.json.Value.Object => |hashmap| {
                if (hashmap.getValue("id")) |id|
                    std.debug.warn("ID:\t{}\n", .{id});
                if (hashmap.getValue("method")) |msg|
                    std.debug.warn("MSG:\t{}\n", .{msg});
            },
        }
    }
};
