const atem = @import("./atem.zig");
const load = @import("./load.zig");

const std = @import("std");
const stdout = std.io.getStdOut();

pub fn main() !void {
    var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer mem.deinit();

    const srcfilepath = std.mem.toSlice(u8, std.os.argv[1]);
    const srcfile = try std.fs.File.openRead(srcfilepath);
    defer srcfile.close();
    const srcfiletext = try mem.allocator.alloc(u8, (try srcfile.stat()).size);
    _ = try srcfile.inStream().stream.readFull(srcfiletext);

    std.debug.warn("{s}\n", .{srcfiletext});
    const prog = try load.FromJson(&mem, srcfiletext);
}
