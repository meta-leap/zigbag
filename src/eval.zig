const std = @import("std");

usingnamespace @import("./atem.zig");
usingnamespace @import("./zutil.zig");

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
    var cur = &frames.items[0];
    try cur.stash.append(expr);
    var idx_frame: u16 = 0;
    var idx_callee: usize = 0;
    var num_args_done: i8 = 0;

    restep: while (true) {
        std.debug.warn("STEP\n", .{});
        idx_callee = cur.stash.len - 1;

        while (cur.pos < 0) if (idx_frame == 0) break :restep else {
            var parent = &frames.items[idx_frame - 1];
            parent.stash.items[@intCast(usize, parent.pos)] = cur.stash.items[idx_callee];
            cur = parent;
            frames.len -= 1;
            idx_frame -= 1;
            idx_callee = cur.stash.len - 1;
        };

        switch (cur.stash.items[@intCast(usize, cur.pos)]) {
            .Never, .NumInt => cur.pos -= 1,

            .ArgRef => |it| {
                const stash_lookup = if (cur.done_callee)
                    frames.items[idx_frame].stash.items
                else
                    frames.items[cur.args_frame].stash.items;
                cur.stash.items[@intCast(usize, cur.pos)] = stash_lookup[stash_lookup.len - @intCast(usize, -it)];
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
                    .pos = @intCast(i8, callargs.len) - 1,
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
                        cur.num_args = @intCast(u8, f.Args.len);
                        allargsused = f.allArgsUsed;
                        // TODO: optional micro-opt
                    }
                    if (cur.num_args == 0) {
                        const call = maybefuncdef.?.Body.Call;
                        cur.stash.len = idx_callee;
                        try cur.stash.appendSlice(call.Args);
                        try cur.stash.append(call.Callee);
                        cur.pos = @intCast(i8, cur.stash.len - 1);
                        if (call.IsClosure == 0) {
                            num_args_done = 0;
                        } else {
                            num_args_done += @intCast(i8, call.Args.len);
                        }
                        continue :restep;
                    } else if (!allargsused) {
                        const until = if (cur.num_args < idx_callee) cur.num_args else idx_callee;
                        const func = maybefuncdef.?;
                        var i = @intCast(usize, num_args_done);
                        while (i < until) : (i += 1) if (0 == func.Args[i]) {
                            cur.stash.items[cur.stash.len - (2 + i)] = Expr.Never;
                        };
                    }
                    cur.pos -= (1 + num_args_done);
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
                    cur.done_callee = true;
                    cur.stash.items[idx_callee] = result;
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
                    var result = cur.stash.items[idx_callee];
                    if (diff < 1) {
                        cur.stash.len = cur.stash.len - 1 - cur.num_args;
                        try cur.stash.append(result);
                    } else if (false) {
                        // TODO: optional micro-opt
                    } else {
                        const args = try std.mem.dupe(mem, Expr, cur.stash.items[0..idx_callee]);
                        cur.stash.len = 1;
                        cur.stash.items[0] = Expr{
                            .Call = try enHeap(mem, ExprCall{
                                .Callee = result,
                                .Args = args,
                                .IsClosure = @intCast(u8, diff),
                            }),
                        };
                    }
                }
                cur.done_callee = false;
                cur.done_args = false;
                cur.num_args = 0;
                cur.pos = if (cur.stash.len == 1) -1 else @intCast(i8, cur.stash.len) - 1;
            } else if (cur.num_args == 0) {
                const closure = cur.stash.items[idx_callee].Call;
                cur.stash.len = idx_callee;
                try cur.stash.appendSlice(closure.Args);
                try cur.stash.append(closure.Callee);
                num_args_done = @intCast(i8, closure.Args.len);
                cur.pos = @intCast(i8, cur.stash.len) - 1;
            } else if (cur.pos < 0 or cur.pos < idx_callee - cur.num_args) {
                cur.pos = @intCast(i8, idx_callee);
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
