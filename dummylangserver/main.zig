const std = @import("std");

pub fn main() !u8 {
    _ = @import("./uri.zig").Uri.init("wut://foo/bar/baz?hello=world#frag");

    var mem_global = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer mem_global.deinit();

    var stdout = std.io.getStdOut().outStream();

    try @import("./baseprotocol.zig").forever(
        &try std.ArrayList(u8).initCapacity(&mem_global.allocator, 8 * 1024 * 1024),
        onFullIncomingPayload,
    );
    return 1;
}

fn onFullIncomingPayload(raw_json_bytes: []const u8) void {
    std.debug.warn(">>>{s}<<<\n", .{raw_json_bytes});
}
