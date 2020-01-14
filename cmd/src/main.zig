const atem = @import("./atem.zig");
const load = @import("./load.zig");

const std = @import("std");
const stdout = std.io.getStdOut();

pub fn main() !void {
    var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer mem.deinit();

    const srcfilepath = std.mem.toSlice(u8, std.os.argv[1]);
    const srcfile = try std.fs.File.openRead(srcfilepath);
    const srcfilestat = try srcfile.stat();
    const srcfiletext = try mem.allocator.alloc(u8, srcfilestat.size);
    _ = try srcfile.inStream().stream.readFull(srcfiletext);

    const tmpfd: atem.FuncDef = undefined;
    const tmpexpr: atem.Expr = undefined;
    std.debug.warn("{}\n", .{srcfilestat.size});
    std.debug.warn("{s}\n", .{srcfiletext});

    const prog = try load.FromJson(&mem.allocator, srcfiletext);
    const tmpintbuf = try mem.allocator.alloc(u8, 20);
    const tmpintlen = std.fmt.formatIntBuf(tmpintbuf, prog.len, 10, false, std.fmt.FormatOptions{});
    std.debug.warn("\n{s}\n", .{tmpintbuf[0..tmpintlen]});
}
