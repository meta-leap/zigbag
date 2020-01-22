const std = @import("std");

pub fn main() !u8 {
    var mem_global = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer mem_global.deinit();

    var stdout = std.io.getStdOut().outStream();
    var stdin = std.io.getStdIn().inStream();

    var buf = try std.ArrayList(u8).initCapacity(&mem_global.allocator, 8 * 1024 * 1024);
    const needle_header_content_length = "Content-Length:";
    var got_content_length: ?usize = null;
    while (true) {
        const len = try stdin.stream.read(buf.items[buf.len..]);
        if (len == 0) break else {
            buf.len += len;
            const so_far = buf.toSliceConst();
            if (got_content_length == null)
                if (std.mem.indexOf(u8, so_far, needle_header_content_length)) |idx|
                    if (idx == 0 or buf.items[idx - 1] == '\n') {
                        const idx_start = idx + needle_header_content_length.len;
                        if (std.mem.indexOfScalarPos(u8, so_far, idx_start, '\n')) |idx_sep| {
                            const str_content_length = std.mem.trim(u8, so_far[idx_start..idx_sep], " \t\r");
                            got_content_length = try std.fmt.parseUnsigned(usize, str_content_length, 10);
                        }
                    };
            if (got_content_length) |content_len| {
                std.debug.warn("Your clen:\t'{d}'\n", .{content_len});
            }
        }
    }
    return 1;
}
