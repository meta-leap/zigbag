const std = @import("std");

const atem = @import("atem");

pub fn main() !void {
    var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer mem.deinit();

    if (std.os.argv.len <= 1)
        return error.ExpectedFilePathArgButMissing;

    const osargs = try mem.allocator.alloc([]const u8, std.os.argv.len - 2);
    const osenv = try mem.allocator.alloc([]const u8, std.os.environ.len);
    for (osargs) |_, i|
        osargs[i] = std.mem.toSlice(u8, std.os.argv[i + 2]);
    for (osenv) |_, i|
        osenv[i] = std.mem.toSlice(u8, std.os.environ[i]);
    const argslist = try atem.listFrom(&mem.allocator, osargs);
    const envlist = try atem.listFrom(&mem.allocator, osenv);

    const srcfilepath = std.mem.toSlice(u8, std.os.argv[1]);
    const srcfile = try std.fs.File.openRead(srcfilepath);
    defer srcfile.close();
    const srcfiletext = try mem.allocator.alloc(u8, (try srcfile.stat()).size);
    _ = try srcfile.inStream().stream.readFull(srcfiletext);
    const prog = try atem.LoadFromJson(&mem, srcfiletext);

    const expr = atem.Expr{
        .Call = &atem.ExprCall{
            .Callee = .Never,
            .Args = &[_]atem.Expr{ envlist, argslist },
        },
    };
    const outexpr = try expr.eval(&mem, prog, true);
    if (try outexpr.listOfExprs(&mem.allocator)) |outlist| {
        const outbytes = try atem.listToBytes(&mem.allocator, outlist);
    } else
        std.debug.warn("RET-EXPR:\t{s}\n", .{try atem.jsonSrc(&mem.allocator, outexpr)});

    std.debug.warn("\n\n{s}\n\n", .{atem.jsonSrc(&mem.allocator, prog)});
    const tmpenv = try envlist.listOfExprs(&mem.allocator);
    if (tmpenv) |list| for (list) |it, i|
        std.debug.warn("{}\t{}\n", .{ i, try it.listOfExprsToStr(&mem.allocator) });
}
