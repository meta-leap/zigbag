const std = @import("std");

usingnamespace @import("./atem.zig");

const Frame = struct {
    stash: std.ArrayList(Expr),
    args_frame: u16 = 0,
    pos: i8 = 0,

    num_args: u8 = 0,
    done_args: bool = false,
    done_callee: bool = false,
};

pub fn eval(memArena: *std.heap.ArenaAllocator, prog: Prog, expr: Expr, frames_capacity: usize) !Expr {
    const mem: *std.mem.Allocator = &memArena.allocator;
    var frames = try std.ArrayList(Frame).initCapacity(mem, frames_capacity);
    try frames.append(Frame{ .stash = try std.ArrayList(Expr).initCapacity(mem, 1) });
    var idx_frame: u16 = 0;
    var idx_callee: usize = 0;
    var num_args_done: u8 = 0;
    var cur = &frames.items[0];

    restep: while (true) {
        idx_callee = cur.stash.items.len - 1;

        while (cur.pos < 0) if (idx_frame == 0) break :restep else {
            var parent = &frames.items[idx_frame - 1];
            parent.stash.items[@intCast(usize, parent.pos)] = cur.stash.items[idx_callee];
            cur = parent;
            frames.len -= 1;
            idx_frame -= 1;
            idx_callee = cur.stash.items.len - 1;
        };

        switch (cur.stash.items[@intCast(usize, cur.pos)]) {
            .Never, .NumInt => cur.pos -= 1,

            .ArgRef => |argref| {
                const stash_lookup = if (cur.done_callee)
                    frames.items[idx_frame].stash.items
                else
                    frames.items[cur.args_frame].stash.items;
                cur.stash.items[@intCast(usize, cur.pos)] = stash_lookup[stash_lookup.len - @intCast(usize, -argref)];
                if (cur.pos == idx_callee) continue :restep else cur.pos -= 1;
            },

            .Call => |call| if (call.IsClosure != 0) {
                cur.pos -= 1;
            } else {
                var callee = call.Callee;
                var callargs = try std.ArrayList(Expr).initCapacity(mem, 3 + call.Args.len);
                while (true) switch (callee) {
                    .Call => |subcall| {
                        callee = subcall.Callee;
                        try callargs.appendSlice(subcall.Args);
                    },
                    else => break,
                };
                try callargs.append(callee);
                try frames.append(Frame{
                    .args_frame = if (cur.done_callee) idx_frame else cur.args_frame,
                    .pos = @intCast(i8, callargs.len) - 1,
                    .stash = callargs,
                });
                idx_frame += 1;
                cur = &frames.items[idx_frame];
                continue :restep;
            },

            else => {},
        }

        if (idx_callee != 0 and cur.pos < idx_callee) {
            if (cur.done_args) {
                // TODO
            } else if (cur.num_args == 0) {
                // const closure = cur.stash.items[idx_callee].Call;
                // TODO
            } else if (cur.pos < 0 or cur.pos < idx_callee - cur.num_args) {
                cur.pos = @intCast(i8, idx_callee);
                cur.done_args = true;
            }
        }

        return error.TODO;
    }

    return frames.items[0].stash.items[0];
}
