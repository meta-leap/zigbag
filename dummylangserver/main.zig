const std = @import("std");

const LangServer = @import("./lsp_serve.zig").LangServer;

pub fn main() !u8 {
    const tmp = @import("./lsp_types.zig");
    _ = @import("./jsonrpc2.zig").In;
    _ = @import("./jsonrpc2.zig").Out;
    const sess = @import("./jsonrpc2.zig").Protocol(.{
        .TRequestIn = tmp.RequestIn,
        .TResponseOut = tmp.ResponseOut,
        .TRequestOut = tmp.RequestOut,
        .TResponseIn = tmp.ResponseIn,
        .TNotifyIn = tmp.NotifyIn,
        .TNotifyOut = tmp.NotifyOut,
    });

    try (LangServer{
        .input = &std.io.getStdIn().inStream().stream,
        .output = &std.io.getStdOut().outStream().stream,
        .mem_alloc_for_arenas = std.heap.page_allocator,
    }).serve();
    // try sess.serve();
    return 1;
}
