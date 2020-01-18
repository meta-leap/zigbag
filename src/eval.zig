const std = @import("std");

usingnamespace @import("./atem.zig");

pub fn eval(memArena: *std.mem.Allocator, prog: Prog, expr: Expr, framesCapacity: usize) !Expr {
    return error.Okay;
}
