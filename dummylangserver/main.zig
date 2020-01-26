const std = @import("std");

const LangServer = @import("./lsp_serve.zig").LangServer;

pub fn main() !u8 {
    try (LangServer{
        .input = std.io.getStdIn().inStream().stream,
        .output = std.io.getStdOut().outStream().stream,
        .mem_alloc_for_arenas = std.heap.page_allocator,
    }).serve();
    return 1;
}
