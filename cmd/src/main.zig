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

    std.debug.warn("{}\n", .{srcfilestat.size});
    try stdout.write("srcfiletext\n");
    std.debug.warn("{s}\n", .{srcfiletext});
}
