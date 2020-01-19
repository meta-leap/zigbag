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

pub fn eval(memArena: *std.heap.ArenaAllocator, prog: Prog, expr: Expr, frames_capacity: usize) !Expr {
    const mem: *std.mem.Allocator = &memArena.allocator;
    var frames = try std.ArrayList(Frame).initCapacity(mem, frames_capacity);
    try frames.append(Frame{ .stash = &[_]Expr{expr} });
    var idx_frame: u16 = 0;
    var idx_callee: usize = 0;
    var num_args_done: u8 = 0;
    var cur = &frames.items[0];

    restep: while (true) {
        idx_callee = cur.stash.len - 1;

        while (cur.pos < 0) if (idx_frame == 0) break :restep else {
            var parent = &frames.items[idx_frame - 1];
            parent.stash[parent.pos] = cur.stash[idx_callee];
            cur = parent;
            frames.len -= 1;
            idx_frame -= 1;
            idx_callee = cur.stash.len - 1;
        };

        switch (cur.stash[cur.pos]) {
            .Never => cur.pos -= 1,

            .NumInt => cur.pos -= 1,

            .ArgRef => |argref| {
                const stash_lookup = if (cur.done_callee)
                    frames.items[idx_frame].stash
                else
                    frames.items[cur.args_frame_idx].stash;
                cur.stash[cur.pos] = stash_lookup[stash_lookup.len - @intCast(usize, -argref)];
                if (cur.pos == idx_callee) continue :restep else cur.pos -= 1;
            },

            .Call => |call| if (call.IsClosure != 0) {
                cur.pos -= 1;
            } else {
                const callee = call.Callee;
                const callargs = try std.ArrayList(Expr).initCapacity(mem, 3 + call.Args.len);
            },

            else => {},
        }

        if (idx_callee != 0 and cur.pos < idx_callee) {
            if (cur.done_args) {} else if (cur.num_args == 0) {} else if (cur.pos < 0 or cur.pos < idx_callee - cur.num_args) {
                cur.pos = idx_callee;
                cur.done_args = true;
            }
        }

        return error.TODO;
    }

    return frames.items[0].stash[0];
}
