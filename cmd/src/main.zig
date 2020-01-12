const atem = @import("./atem.zig");
const load = @import("./load.zig");

const std = @import("std");
const stdout = std.io.getStdOut();

pub fn main() !void {
    var memheap = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer memheap.deinit();

    const srcfilepath = std.mem.toSlice(u8, std.os.argv[1]);
    const srcfile = try std.fs.File.openRead(srcfilepath);
    const srcfilestat = try srcfile.stat();
    const srcfiletext = try memheap.allocator.alloc(u8, srcfilestat.size);
    _ = try srcfile.inStream().stream.readFull(srcfiletext);

    const tmpfd: atem.FuncDef = undefined;
    const tmpexpr: atem.Expr = undefined;
    const tmpintbuf = try memheap.allocator.alloc(u8, 20);
    const tmpintlen = std.fmt.formatIntBuf(tmpintbuf, srcfilestat.size, 10, false, std.fmt.FormatOptions{});
    std.debug.warn("{}\n", .{srcfilestat.size});
    std.debug.warn("{s}\n", .{srcfiletext});
    std.debug.warn("\n\n{}\t{s}!\n", .{ tmpintlen, tmpintbuf[0..tmpintlen] });

    const prog = try load.FromJson(&memheap.allocator, srcfiletext);
}
