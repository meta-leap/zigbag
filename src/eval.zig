const std = @import("std");

usingnamespace @import("./atem.zig");

const Frame = struct {
    stash: []Expr,
    args_frame_idx: u16 = 0,
    pos: usize = 0,

    num_args: u8 = 0,
    done_args: bool = false,
    done_callee: bool = false,
};

pub fn eval(mem: *std.mem.Allocator, prog: Prog, expr: Expr, frames_capacity: usize) !Expr {
    var frames = try std.ArrayList(Frame).initCapacity(mem, frames_capacity);
    try frames.append(Frame{ .stash = &[_]Expr{expr} });
    var idx_frame: u16 = 0;
    var idx_callee: usize = 0;
    var num_args_done: u8 = 0;
    var cur = &frames.items[0];

    loop: while (true) {
        idx_callee = cur.stash.len - 1;
        while (cur.pos < 0) if (idx_frame == 0) break :loop else {
            var parent = &frames.items[idx_frame - 1];
            parent.stash[parent.pos] = cur.stash[idx_callee];
            cur = parent;
            // TODO
        };
    }

    return frames.items[0].stash[0];
}
