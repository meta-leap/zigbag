const std = @import("std");

const atem = @import("./atem.zig");

pub fn FromJson(memArena: *std.heap.ArenaAllocator, src: []const u8) !atem.Prog {
    var jsonparser = std.json.Parser.init(&memArena.allocator, true);
    var jsontree = try jsonparser.parse(src);
    const rootarr = try asP(std.json.Value.Array, &jsontree.root);
    return fromJson(&memArena.allocator, rootarr.toSliceConst());
}

fn fromJson(mem: *std.mem.Allocator, top_level: []const std.json.Value) !atem.Prog {
    var prog = try mem.alloc(atem.FuncDef, top_level.len);
    for (prog) |_, i| {
        const arrfuncdef = try asP(std.json.Value.Array, &top_level[i]);
        if (arrfuncdef.len != 3)
            return error.BadJsonSrc;

        const arrmeta = try asP(std.json.Value.Array, &arrfuncdef.at(0));
        const arrargs = try asP(std.json.Value.Array, &arrfuncdef.at(1));
        prog[i].allArgsUsed = true;
        prog[i].Meta = try mem.alloc([]u8, arrmeta.len);
        prog[i].Args = try mem.alloc(bool, arrargs.len);
        {
            var a: usize = 0;
            while (a < arrargs.len) : (a += 1) {
                const numused = try asV(std.json.Value.Integer, &arrargs.at(a));
                prog[i].Args[a] = (numused != 0);
                if (numused == 0)
                    prog[i].allArgsUsed = false;
            }
            var m: usize = 0;
            while (m < arrmeta.len) : (m += 1)
                prog[i].Meta[m] = try asV(std.json.Value.String, &arrmeta.at(m));
        }
        prog[i].Body = try exprFromJson(mem, &arrfuncdef.at(2), @intCast(isize, arrargs.len));
    }
    for (prog) |_, i|
        postLoadPreProcess(prog, i);
    return prog;
}

fn exprFromJson(mem: *std.mem.Allocator, from: *const std.json.Value, curFnNumArgs: isize) anyerror!atem.Expr {
    switch (from.*) {
        std.json.Value.Integer => |int| {
            return atem.Expr{ .NumInt = int };
        },

        std.json.Value.String => |str| {
            var n = try std.fmt.parseInt(isize, str, 10);
            if (n < 0)
                n += curFnNumArgs;
            if (n < 0 or n >= curFnNumArgs)
                return error.BadJsonSrc;
            return atem.Expr{ .ArgRef = -(n + 2) };
        },

        std.json.Value.Array => |arr| {
            if (arr.len == 1)
                return atem.Expr{ .FuncRef = try asV(std.json.Value.Integer, &arr.at(0)) };

            var ret = atem.ExprCall{
                .Callee = try exprFromJson(mem, &arr.at(0), curFnNumArgs),
                .Args = try mem.alloc(atem.Expr, arr.len - 1),
            };
            var i: usize = ret.Args.len;
            var a: u8 = 0;
            while (i > 0) : (i -= 1) {
                ret.Args[a] = try exprFromJson(mem, &arr.at(i), curFnNumArgs);
                a += 1;
            }
            if (ret.Callee.is(.Call)) |call| {
                const merged = try mem.alloc(atem.Expr, ret.Args.len + call.Args.len);
                std.mem.copy(atem.Expr, merged, ret.Args);
                std.mem.copy(atem.Expr, merged[ret.Args.len..], call.Args);
                ret.Callee = call.Callee;
                ret.Args = merged;
            }
            return atem.Expr{ .Call = try copy(mem, ret) };
        },

        else => {
            return error.BadJsonSrc;
        },
    }
}

fn postLoadPreProcess(prog: atem.Prog, i: usize) void {
    std.debug.warn("\n\n{}\t{}\n\t{}\n", .{ i, prog[i].Meta[0], prog[i].Body });
    const fd = &prog[i];
    fd.isMereAlias = false;
    fd.selector = 0;
    if (fd.Args.len == 0 and fd.Body.isnt(.Call))
        fd.isMereAlias = true
    else if (fd.Args.len >= 2) {
        if (fd.Body.is(.ArgRef)) |argref|
            fd.selector = argref
        else if (fd.Body.is(.Call)) |call|
            if (call.Callee.is(.ArgRef)) |argref| {
                var ok = (argref != -2);
                if (ok) for (call.Args) |arg|
                    if (arg.isnt(.ArgRef)) {
                        ok = false;
                        break;
                    };
                if (ok)
                    fd.selector = @intCast(isize, call.Args.len);
            };
    }
    fd.Body = detectAndMarkClosures(prog, fd.Body);
}

fn detectAndMarkClosures(prog: atem.Prog, it: atem.Expr) atem.Expr {
    var ret = it;
    while (ret.is(.FuncRef)) |fnr| {
        if (fnr > 0 and prog[@intCast(usize, fnr)].isMereAlias)
            ret = prog[@intCast(usize, fnr)].Body
        else
            break;
    }
    if (ret.is(.Call)) |call| {
        call.Callee = detectAndMarkClosures(prog, call.Callee);
        for (call.Args) |_, i|
            call.Args[i] = detectAndMarkClosures(prog, call.Args[i]);
        if (call.Callee.is(.FuncRef)) |fnr| {
            var numargs: isize = 2;
            if (fnr >= 0)
                numargs = @intCast(isize, prog[@intCast(usize, fnr)].Args.len);
            var diff: isize = numargs - @intCast(isize, call.Args.len);
            var i: usize = 0;
            while (diff > 0 and i < call.Args.len) : (i += 1) {
                if (call.Args[i].is(.ArgRef)) |_|
                    diff = 0
                else if (call.Args[i].is(.Call)) |subcall| {
                    if (subcall.IsClosure == 0)
                        diff = 0;
                }
            }
            if (diff > 0)
                call.IsClosure = @intCast(u8, diff);
        }
    }

    return ret;
}

inline fn asP(comptime tag: var, scrutinee: var) !*const std.meta.TagPayloadType(std.json.Value, tag) {
    switch (scrutinee.*) {
        tag => |*ok| return ok,
        else => return error.BadJsonSrc,
    }
}

inline fn asV(comptime tag: var, scrutinee: var) !std.meta.TagPayloadType(std.json.Value, tag) {
    switch (scrutinee.*) {
        tag => |ok| return ok,
        else => return error.BadJsonSrc,
    }
}

inline fn copy(mem: *std.mem.Allocator, it: var) !*@TypeOf(it) {
    var ret = try mem.create(@TypeOf(it));
    ret.* = it;
    return ret;
}
