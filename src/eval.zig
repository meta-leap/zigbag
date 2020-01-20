const std = @import("std");

usingnamespace @import("./atem.zig");
usingnamespace @import("./zutil.zig");

pub fn eval(memArena: *std.heap.ArenaAllocator, prog: Prog, expr: Expr, frames_capacity: usize) !Expr {
    const Frame = struct {
        stash: std.ArrayList(Expr),
        args_frame: usize = 0, // u16
        pos: isize = 0, // i8

        num_args: usize = 0, // u8
        done_args: bool = false,
        done_callee: bool = false,
    };
    const mem = &memArena.allocator;
    var frames = try std.ArrayList(Frame).initCapacity(mem, frames_capacity);
    var idx_frame: usize = 0; // u16
    var idx_callee: usize = 0;
    var num_args_done: usize = 0; // i8
    try frames.append(Frame{ .stash = try std.ArrayList(Expr).initCapacity(mem, 1) });
    var cur = &frames.items[idx_frame];
    try cur.stash.append(expr);

    restep: while (true) {
        std.debug.warn("STEP\n", .{});
        idx_callee = cur.stash.len - 1;

        while (cur.pos < 0) {
            if (idx_frame == 0) break :restep else {
                const caller_frame = &frames.items[idx_frame - 1];
                caller_frame.stash.items[@intCast(usize, caller_frame.pos)] = cur.stash.items[idx_callee];
                cur = caller_frame;
                frames.len -= 1;
                idx_frame -= 1;
                idx_callee = cur.stash.len - 1;
            }
        }

        switch (cur.stash.items[@intCast(usize, cur.pos)]) {
            .Never, .NumInt => cur.pos -= 1,

            .ArgRef => |it| {
                const stash_lookup = if (cur.done_callee)
                    frames.items[idx_frame].stash.items
                else
                    frames.items[cur.args_frame].stash.items;
                cur.stash.items[@intCast(usize, cur.pos)] = stash_lookup[@intCast(usize, @intCast(isize, stash_lookup.len) + it)]; // TODO: can turn 2 intCasts into 1, via -it
                if (cur.pos == idx_callee) continue :restep else cur.pos -= 1;
            },

            .Call => |it| if (it.IsClosure != 0) {
                cur.pos -= 1;
            } else {
                var callee = it.Callee;
                var callargs = try std.ArrayList(Expr).initCapacity(mem, 3 + it.Args.len);
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
                    .pos = @intCast(isize, callargs.len) - 1,
                    .stash = callargs,
                });
                idx_frame += 1;
                cur = &frames.items[idx_frame];
                continue :restep;
            },

            .FuncRef => |it| if (cur.done_callee or cur.pos != idx_callee) {
                cur.pos -= 1;
            } else {
                const maybefuncdef = if (it < 0) null else &prog[@intCast(usize, it)];
                if (cur.num_args == 0) {
                    cur.num_args = 2;
                    var allargsused = true;
                    if (maybefuncdef) |f| {
                        cur.num_args = f.Args.len;
                        allargsused = f.allArgsUsed;
                        // TODO: optional micro-opt
                    }
                    if (cur.num_args == 0) {
                        const call = maybefuncdef.?.Body.Call;
                        cur.stash.len = idx_callee;
                        try cur.stash.appendSlice(call.Args);
                        try cur.stash.append(call.Callee);
                        cur.pos = @intCast(isize, cur.stash.len) - 1;
                        if (call.IsClosure == 0) {
                            num_args_done = 0;
                        } else {
                            num_args_done += call.Args.len;
                        }
                        continue :restep;
                    } else if (!allargsused) {
                        const until = if (cur.num_args < idx_callee) cur.num_args else idx_callee;
                        const func = maybefuncdef.?;
                        var i = num_args_done;
                        while (i < until) : (i += 1) if (0 == func.Args[i]) {
                            cur.stash.items[cur.stash.len - (2 + i)] = Expr.Never;
                        };
                    }
                    cur.pos -= (1 + @intCast(isize, num_args_done));
                    num_args_done = 0;
                } else if (cur.stash.len > cur.num_args) {
                    var result: Expr = undefined;
                    if (maybefuncdef) |func| {
                        result = func.Body;
                    } else {
                        const oplhs = cur.stash.items[cur.stash.len - 2];
                        const oprhs = cur.stash.items[cur.stash.len - 3];
                        switch (@intToEnum(OpCode, it)) {
                            .Add => result = Expr{ .NumInt = oplhs.NumInt + oprhs.NumInt },
                            .Sub => result = Expr{ .NumInt = oplhs.NumInt - oprhs.NumInt },
                            .Mul => result = Expr{ .NumInt = oplhs.NumInt * oprhs.NumInt },
                            .Div => result = Expr{ .NumInt = @divTrunc(oplhs.NumInt, oprhs.NumInt) },
                            .Mod => result = Expr{ .NumInt = @mod(oplhs.NumInt, oprhs.NumInt) },
                            .Eq => result = Expr{ .FuncRef = @enumToInt(if (oplhs.eqTo(oprhs)) StdFunc.True else StdFunc.False) },
                            .Gt => result = Expr{ .FuncRef = @enumToInt(if (oplhs.NumInt > oprhs.NumInt) StdFunc.True else StdFunc.False) },
                            .Lt => result = Expr{ .FuncRef = @enumToInt(if (oplhs.NumInt < oprhs.NumInt) StdFunc.True else StdFunc.False) },
                            .Prt => {
                                result = oprhs;
                                handlerForOpPrt(mem, try oplhs.listOfExprsToStr(mem), oprhs);
                            },
                            else => result = try handlerForOpUnknown(mem, it, oplhs, oprhs),
                        }
                    }
                    cur.stash.items[idx_callee] = result;
                    cur.done_callee = true;
                    continue :restep;
                } else
                    cur.pos -= 1;
            },

            else => unreachable,
        }

        if (idx_callee != 0 and cur.pos < idx_callee) {
            if (cur.done_args) {
                {
                    const diff = cur.num_args - idx_callee;
                    const result = cur.stash.items[idx_callee];
                    if (diff < 1) {
                        cur.stash.len = (cur.stash.len - 1) - cur.num_args;
                        try cur.stash.append(result);
                    } else {
                        // const ilp = idx_frame - 1;
                        // if (ilp > 0 and frames.items[ilp].num_args == 0 and frames.items[ilp].stash.len != 1 and frames.items[ilp].pos == frames.items[ilp].stash.len - 1) {
                        //     const callee = result;
                        //     const callargs = cur.stash.items[0..idx_callee];
                        //     continue :restep;
                        // } else {
                        const args = try std.mem.dupe(mem, Expr, cur.stash.items[0..idx_callee]);
                        cur.stash.len = 1;
                        cur.stash.items[0] = Expr{
                            .Call = try enHeap(mem, ExprCall{
                                .Callee = result,
                                .Args = args,
                                .IsClosure = diff,
                            }),
                        };
                        // }
                    }
                }
                cur.done_callee = false;
                cur.done_args = false;
                cur.num_args = 0;
                cur.pos = if (cur.stash.len == 1) -1 else @intCast(isize, cur.stash.len) - 1;
            } else if (cur.num_args == 0) {
                const closure = cur.stash.items[idx_callee].Call;
                cur.stash.len = idx_callee;
                try cur.stash.appendSlice(closure.Args);
                try cur.stash.append(closure.Callee);
                num_args_done = closure.Args.len;
                cur.pos = @intCast(isize, cur.stash.len) - 1;
            } else if (cur.pos < 0 or cur.pos < idx_callee - cur.num_args) {
                cur.pos = @intCast(isize, idx_callee);
                cur.done_args = true;
            }
        }
    }

    return frames.items[0].stash.items[0];
}

pub fn handleOpUnknown(mem: *std.mem.Allocator, op_code: isize, op_lhs: Expr, op_rhs: Expr) !Expr {
    return error.EvalBadOpCode;
}

pub fn handleOpPrt(mem: *std.mem.Allocator, msg: []const u8, result: Expr) void {
    std.debug.warn("{s}\t{s}\n", .{ msg, result.listOfExprsToStr(mem) });
}
