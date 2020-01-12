const std = @import("std");

const atem = @import("./atem.zig");

pub fn FromJson(mem: *std.mem.Allocator, src: []u8) !atem.Prog {
    var jsonparser = std.json.Parser.init(mem, true);
    defer jsonparser.deinit();
    var jsontree = try jsonparser.parse(src);
    defer jsontree.deinit();
    const rootarr = try as(std.json.Value.Array, std.json.Array, jsontree.root);
    return fromJson(mem, rootarr.toSlice());
}

fn fromJson(mem: *std.mem.Allocator, top_level: []std.json.Value) !atem.Prog {
    var prog = try mem.alloc(atem.FuncDef, top_level.len);
    var i: usize = 0;
    while (i < top_level.len) : (i += 1) {
        prog[i].allArgsUsed = true;
        const arrfuncdef = try as(std.json.Value.Array, std.json.Array, top_level[i]);
        if (arrfuncdef.len != 3)
            return error.BadJsonSrc;
        const arrargs = try as(std.json.Value.Array, std.json.Array, arrfuncdef.at(1));
        prog[i].Args = try mem.alloc(bool, arrargs.len);
        var j: usize = 0;
        while (j < arrargs.len) : (j += 1) {
            const numused = try as(std.json.Value.Integer, i64, arrargs.at(j));
            prog[i].Args[j] = (numused != 0);
            if (numused == 0)
                prog[i].allArgsUsed = false;
        }
    }
    return error.Neato;
}

inline fn as(comptime UnionMemberTag: var, comptime TUnionMember: type, scrutinee: var) !TUnionMember {
    switch (scrutinee) {
        UnionMemberTag => |ok| return ok,
        else => return error.BadJsonSrc,
    }
}
