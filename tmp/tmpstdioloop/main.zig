const std = @import("std");

pub fn main() !void {
    var mem = std.heap.page_allocator;
    var stdout = std.io.getStdOut().outStream();
    var stdin = std.io.getStdIn().inStream();

    var buf = std.Buffer.initNull(mem);
    defer buf.deinit();
    while (true) {
        try stdin.stream.readUntilDelimiterBuffer(&buf, '\n', 987654321);
        const inputline = buf.toOwnedSlice();
        defer mem.free(inputline);
        if (inputline.len == 0)
            break;
        try stdout.stream.print("So you say: {s}\n", .{inputline});
    }
}
