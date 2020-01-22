const std = @import("std");

pub fn main() !void {
    var mem = std.heap.page_allocator;
    var stdout = std.io.getStdOut().outStream();
    var stdin = std.io.getStdIn().inStream();

    var buf = std.Buffer.initNull(mem);
    defer buf.deinit();
    while (true) {
        try stdin.stream.readUntilDelimiterBuffer(&buf, '\n', 987654321);
        var inputline = buf.toOwnedSlice();
        defer mem.free(inputline);
        if (inputline.len == 0)
            break;
        std.mem.reverse(u8, inputline);
        try stdout.stream.print("{s}\n\n", .{inputline});
    }
}
