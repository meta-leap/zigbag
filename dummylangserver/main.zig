const std = @import("std");

const tmpj = @import("./lsp_types.zig");

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
    const jrpc = @import("./jsonrpc.zig");
    var sess = jrpc.Protocol(.{
            .TRequestId = tmpj.IntOrString,
            .TRequestIn = tmpj.RequestIn,
            .TRequestOut = tmpj.RequestOut,
            .TNotifyIn = tmpj.NotifyIn,
            .TNotifyOut = tmpj.NotifyOut,
        }){
        .mem_alloc_for_arenas = std.heap.page_allocator,
    };
    _ = jrpc.ErrorCodes;
    _ = jrpc.ResponseError;
    _ = jrpc.In;
    _ = jrpc.Out;
    _ = jrpc.Req;
    _ = jrpc.JsonAny;
    sess.out(tmpj.NotifyOut{ .window_showMessage = &tmpj.ShowMessageParams{ .type__ = .Info, .message = "Ohai" } }, .{ 10, 20 });
    sess.on(tmpj.NotifyIn{ .__cancelRequest = tmp_oncancel });
    sess.on(tmpj.NotifyIn{ .exit = tmp_onexit });
    sess.on(tmpj.RequestIn{ .initialize = tmp_oninit });
}

fn tmp_oninit(in: tmpj.In(tmpj.InitializeParams)) tmpj.Out(tmpj.InitializeResult) {
    return .{ .ok = LangServer.setup };
}

fn tmp_oncancel(in: tmpj.In(tmpj.CancelParams)) void {}

fn tmp_onexit(in: tmpj.In(void)) void {}
