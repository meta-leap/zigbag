const std = @import("std");

pub fn forever(
    buf: *std.ArrayList(u8),
    onFullIncomingPayload: fn ([]const u8) void,
) !void {
    var stdin = std.io.getStdIn().inStream();
    var got_content_length: ?usize = null;

    while (true) {
        buf.len += readmore: {
            const num_bytes = try stdin.stream.read(buf.items[buf.len..]);
            if (num_bytes == 0) return else break :readmore num_bytes;
        };

        const so_far = buf.toSliceConst();
        if (got_content_length == null)
            if (std.mem.indexOf(u8, so_far, "Content-Length:")) |idx|
                if (idx == 0 or buf.items[idx - 1] == '\n') {
                    const idx_start = idx + "Content-Length:".len;
                    if (std.mem.indexOfScalarPos(u8, so_far, idx_start, '\n')) |idx_newline| {
                        const str_content_length = std.mem.trim(u8, so_far[idx_start..idx_newline], " \t\r");
                        got_content_length = try std.fmt.parseUnsigned(usize, str_content_length, 10);
                    }
                };
        if (got_content_length) |content_len| {
            if (std.mem.indexOf(u8, so_far, "\r\n\r\n")) |idx| {
                const keep = buf.items[idx + 4 .. buf.len];
                std.mem.copy(u8, buf.items[0..keep.len], keep);
                try buf.ensureCapacity(content_len);
                if (keep.len < content_len)
                    try stdin.stream.readNoEof(buf.items[keep.len .. content_len - keep.len]);
                if (content_len > 0)
                    onFullIncomingPayload(buf.items[0..content_len]);

                const keep2 = buf.items[content_len..buf.len];
                std.mem.copy(u8, buf.items[0..keep2.len], keep2);
                buf.len = keep2.len;
                got_content_length = null;
            }
        }
    }
}
