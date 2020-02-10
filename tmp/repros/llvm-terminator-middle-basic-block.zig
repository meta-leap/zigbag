const std = @import("std");

test "" {
    try main();
}

pub fn main() error{}!void {
    var dir: ?std.fs.Dir = null;
    if (std.time.timestamp() > 0) blk: {
        defer dir.?.deleteTree("nevermind") catch {};
    }
}
