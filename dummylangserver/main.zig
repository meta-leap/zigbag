const std = @import("std");

const Engine = @import("./lsp_loop.zig").Engine;

pub fn main() !u8 {
    try (Engine{
        .input = std.io.getStdIn().inStream().stream,
        .output = std.io.getStdOut().outStream().stream,
        .memAllocForArenas = std.heap.page_allocator,
    }).serve();
    return 1;
}
