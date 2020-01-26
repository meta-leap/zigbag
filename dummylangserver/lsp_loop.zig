const std = @import("std");

const types = @import("./lsp_types.zig");
const json = @import("./lsp_json.zig");

pub const Engine = struct {
    input: std.io.InStream(std.os.ReadError),
    output: std.io.OutStream(std.os.WriteError),
    memAllocForArenas: *std.mem.Allocator,

    pub fn serve(self: *Engine) !void {
        var mem_buf = std.heap.ArenaAllocator.init(self.memAllocForArenas);
        defer mem_buf.deinit();

        const buf = &try std.ArrayList(u8).initCapacity(&mem_buf.allocator, 16 * 1024); // initial cap must be big enough to catch the first occurrence of `Content-Length:` header, from there on out `buf` grows to any Content-Length greater than its current-capacity (which is never shrunk)
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

            if (!did_full_full_msg)
                buf.len += read_more: {
                    const num_bytes = try self.input.read(buf.items[buf.len..]);
                    if (num_bytes > 0) break :read_more num_bytes else return error.EndOfStream;
                };
        }
    }
};

fn handleFullIncomingJsonPayload(self: *Engine, raw_json_bytes: []const u8) !void {
    var mem_json = std.heap.ArenaAllocator.init(self.memAllocForArenas);
    defer mem_json.deinit();
    var mem_keep = std.heap.ArenaAllocator.init(self.memAllocForArenas);

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
                    } else
                        handleIncomingResponseMsg(self, &mem_keep, id);
                }
            } else if (msg_name) |jstr| switch (jstr) {
                .String => |method_name| handleIncomingNotifyMsg(self, &mem_keep, method_name),
                else => {},
            };
        },
    }
}

fn handleIncomingMsg(comptime T: type, self: *Engine, mem: *std.heap.ArenaAllocator, id: types.IntOrString, method: []const u8, params: ?std.json.Value) !void {
    std.debug.warn("REQ\t{}\t{}\t{}\n", .{ id, method, params });
    const union_member_name = @import("./xstd.mem.zig").replaceScalar(u8, try std.mem.dupe(&mem.allocator, u8, method), "$/", '_');
    const req = if (params) |*p| try json.unmarshalUnion(T, mem, union_member_name, p) else null;
    std.debug.warn("NAME\t{}\t{}\n", .{ union_member_name, req });
    if (req) |uintptr| { // TODO: would like to put in extra `inline fn` but: "unable to evaluate constant expression"
        comptime var i = @memberCount(T);
        inline while (i > 0) {
            i -= 1;
            if (std.mem.eql(u8, @memberName(T, i), union_member_name)) {
                const TMember = @memberType(T, i);
                if (@typeId(TMember) != .Void)
                    _ = try json.marshal(mem, (@intToPtr(TMember, uintptr)).*);
                break;
            }
        }
    }
}

fn handleIncomingResponseMsg(self: *Engine, mem: *std.heap.ArenaAllocator, id: types.IntOrString) void {
    std.debug.warn("RESP\t{}\n", .{id});
}

fn handleIncomingNotifyMsg(self: *Engine, mem: *std.heap.ArenaAllocator, method: []const u8) void {
    std.debug.warn("SIG\t{}\n", .{method});
}
