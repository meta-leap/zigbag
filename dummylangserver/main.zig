const std = @import("std");

const LangServer = @import("./lsp_serve.zig").LangServer;

pub fn main() !u8 {
    try (LangServer{
        .input = &std.io.getStdIn().inStream().stream,
        .output = &std.io.getStdOut().outStream().stream,
        .mem_alloc_for_arenas = std.heap.page_allocator,
    }).serve();

    tmpMockToForceCompilations();
    return 1;
}

fn tmpMockToForceCompilations() void {
    const jt = @import("./lsp_types.zig");
    const jrpc = @import("./jsonrpc.zig");
    const sess = jrpc.Protocol(.{
        .TRequestId = jt.IntOrString,
        .TRequestIn = jt.RequestIn,
        .TResponseOut = jt.ResponseOut,
        .TRequestOut = jt.RequestOut,
        .TResponseIn = jt.ResponseIn,
        .TNotifyIn = jt.NotifyIn,
        .TNotifyOut = jt.NotifyOut,
    });
    _ = jrpc.ErrorCodes;
    _ = jrpc.ResponseError;
    _ = jrpc.In;
    _ = jrpc.Out;
    _ = jrpc.JsonAny;
    _ = sess.incoming;
    _ = sess.outgoing;
    _ = sess.subscribe;
}
