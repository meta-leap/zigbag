const std = @import("std");

const atem = @import("./atem.zig");

pub fn FromJson(ram: *std.mem.Allocator, src: []u8) !atem.Prog {
    var jsonparser = std.json.Parser.init(ram, true);
    const toplevel = (try jsonparser.parse(src)).root;
    return error.NotYet;
}
