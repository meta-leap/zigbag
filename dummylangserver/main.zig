const std = @import("std");

pub fn main() !u8 {
    try (@import("./lsp_loop.zig").Engine{
        .input = std.io.getStdIn().inStream().stream,
        .output = std.io.getStdOut().outStream().stream,
        .memAllocForArenas = std.heap.page_allocator,
    }).serve();
    return 1;
}
