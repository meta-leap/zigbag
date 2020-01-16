const std = @import("std");

const atem = @import("atem");

pub fn main() !void {
    var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer mem.deinit();

    const srcfilepath = std.mem.toSlice(u8, std.os.argv[1]);
    const srcfile = try std.fs.File.openRead(srcfilepath);
    defer srcfile.close();
    const srcfiletext = try mem.allocator.alloc(u8, (try srcfile.stat()).size);
    _ = try srcfile.inStream().stream.readFull(srcfiletext);

    std.debug.warn("{s}\n\n", .{srcfiletext});
    const prog = try atem.load.FromJson(&mem, srcfiletext);
    std.debug.warn("\n\n{s}\n\n", .{atem.jsonSrc(&mem.allocator, prog)});
}
