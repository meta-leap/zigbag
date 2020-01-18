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

    const prog = try atem.load.FromJson(&mem, srcfiletext);
    const osargs = try mem.allocator.alloc([]const u8, std.os.argv.len - 2);
    for (osargs) |_, i|
        osargs[i] = std.mem.toSlice(u8, std.os.argv[i + 2]);
    const osenv = try mem.allocator.alloc([]const u8, std.os.environ.len);
    for (osenv) |_, i|
        osenv[i] = std.mem.toSlice(u8, std.os.environ[i]);

    std.debug.warn("\n\n{s}\n\n", .{atem.jsonSrc(&mem.allocator, prog)});
    for (osargs) |arg, i|
        std.debug.warn("{}\t{s}\n", .{ isStr(@TypeOf(arg)), arg });
    // const envlist = osenv.listOfExprs(mem.allocator);
    for (osenv) |env, i|
        std.debug.warn("{}\t{s}\n", .{ isStr(@TypeOf(env)), env });
}

pub inline fn isStr(comptime it: type) bool {
    return switch (@typeInfo(it)) {
        std.builtin.TypeId.Array => |ta| u8 == ta.child,
        std.builtin.TypeId.Pointer => |tp| u8 == tp.child or switch (@typeInfo(tp.child)) {
            std.builtin.TypeId.Array => |tpa| u8 == tpa.child,
            else => false,
        },
        else => false,
    };
}
