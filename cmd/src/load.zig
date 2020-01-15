const std = @import("std");

const atem = @import("./atem.zig");

pub fn FromJson(mem: *std.mem.Allocator, src: []const u8) !atem.Prog {
    var jsonparser = std.json.Parser.init(mem, true);
    defer jsonparser.deinit();
    var jsontree = try jsonparser.parse(src);
    defer jsontree.deinit();
    const rootarr = try asP(std.json.Value.Array, &jsontree.root);
    return fromJson(mem, rootarr.toSliceConst());
}

fn fromJson(mem: *std.mem.Allocator, top_level: []const std.json.Value) !atem.Prog {
    var prog = try mem.alloc(atem.FuncDef, top_level.len);
    var i: usize = 0;
    while (i < top_level.len) : (i += 1) {
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
    i = 0;
    while (i < top_level.len) : (i += 1)
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

            const callee = try exprFromJson(mem, &arr.at(0), curFnNumArgs);
            var args = try mem.alloc(atem.Expr, arr.len - 1);
            {
                var i: usize = args.len;
                var a: u8 = 0;
                while (i > 0) : (i -= 1) {
                    args[a] = try exprFromJson(mem, &arr.at(i), curFnNumArgs);
                    a += 1;
                }
            }
            if (callee.is(.Call)) |call| {
                const merged = try mem.alloc(atem.Expr, args.len + call.Args.len);
                std.mem.copy(atem.Expr, merged, args);
                std.mem.copy(atem.Expr, merged[args.len..], call.Args);
                mem.free(args);
                mem.free(call.Args);
                return atem.Expr{ .Call = &atem.ExprCall{ .Callee = call.Callee, .Args = merged } };
            } else
                return atem.Expr{ .Call = &atem.ExprCall{ .Callee = callee, .Args = args } };
        },

        else => {
            return error.BadJsonSrc;
        },
    }
}

fn postLoadPreProcess(prog: atem.Prog, i: usize) void {
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

fn detectAndMarkClosures(prog: atem.Prog, expr: atem.Expr) atem.Expr {
    return expr;
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
