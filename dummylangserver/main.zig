const std = @import("std");

const Engine = @import("./lsp_serve.zig").Engine;

pub fn main() !u8 {
    try (Engine{
        .input = std.io.getStdIn().inStream().stream,
        .output = std.io.getStdOut().outStream().stream,
        .mem_alloc_for_arenas = std.heap.page_allocator,
    }).serve();
    return 1;
}
