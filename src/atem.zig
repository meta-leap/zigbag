const std = @import("std");
const zut = @import("./zutil.zig");

pub const load = @import("./load.zig");

pub const Prog = []const FuncDef;

pub const OpCode = enum {
    Add = -1,
    Sub = -2,
    Mul = -3,
    Div = -4,
    Mod = -5,
    Eq = -6,
    Lt = -7,
    Gt = -8,
    Prt = -42,
    Eval = -4242,
};

pub const StdFunc = enum(isize) {
    Id = 0,
    True = 1,
    False = 2,
    Nil = 3,
    Cons = 4,
};

pub const FuncDef = struct {
    Args: []bool,
    Body: Expr,
    Meta: [][]const u8,
    selector: isize,
    allArgsUsed: bool,
    isMereAlias: bool,

    fn jsonSrc(self: *const FuncDef, buf: *std.Buffer, dropFuncDefMetas: bool) !void {
        try buf.append("[ [");
        if (!dropFuncDefMetas) {
            for (self.Meta) |strmeta, i| {
                if (i > 0)
                    try buf.appendByte(',');
                try buf.appendByte('"');
                try buf.append(strmeta);
                try buf.appendByte('"');
            }
        }
        try buf.append("], [");
        for (self.Args) |argused, i| {
            if (i > 0)
                try buf.appendByte(',');
            try buf.appendByte(if (argused) '1' else '0');
        }
        try buf.append("],\n\t\t");
        try self.Body.jsonSrc(buf);
        try buf.append(" ]");
    }
};

pub const ExprCall = struct {
    Callee: Expr,
    Args: []Expr,
    IsClosure: u8 = 0,
};

pub const Expr = union(enum) {
    NumInt: isize,
    ArgRef: isize,
    FuncRef: isize,
    Call: *const ExprCall,
    Never: void,

    inline fn is(self: Expr, comptime tag: var) ?std.meta.TagPayloadType(Expr, tag) {
        return zut.uIs(Expr, tag, self);
    }

    inline fn isnt(self: Expr, comptime tag: var) bool {
        return zut.uIsnt(Expr, tag, self);
    }

    fn jsonSrc(self: Expr, buf: *std.Buffer) @TypeOf(std.Buffer.append).ReturnType.ErrorSet!void {
        switch (self) {
            .Never => try buf.append("null"),
            .NumInt => |n| try zut.fmtTo(buf, "{d}", .{n}),
            .ArgRef => |a| try zut.fmtTo(buf, "\"{d}\"", .{(-a) - 2}),
            .FuncRef => |f| try zut.fmtTo(buf, "[{d}]", .{f}),
            .Call => |c| {
                try buf.appendByte('[');
                try c.Callee.jsonSrc(buf);
                var i = c.Args.len;
                while (i > 0) {
                    i -= 1;
                    try buf.append(", ");
                    try c.Args[i].jsonSrc(buf);
                }
                try buf.appendByte(']');
            },
        }
    }

    fn eqTo(self: Expr, cmp: Expr) bool {
        if (std.meta.activeTag(self) == std.meta.activeTag(cmp)) switch (self) {
            .Never => unreachable,
            .NumInt => |n| return n == cmp.NumInt,
            .FuncRef => |f| return f == cmp.FuncRef,
            .ArgRef => |a| return a == cmp.ArgRef,
            .Call => |c| {
                if (c.Args.len == cmp.Call.Args.len and c.Callee.eqTo(cmp.Call.Callee)) {
                    for (cmp.Call.Args) |cmparg, i|
                        if (!cmparg.eqTo(c.Args[i]))
                            return false;
                    return true;
                }
            },
        };
        return false;
    }

    fn listOfExprs(self: Expr, mem: *std.mem.Allocator) !?[]const Expr {
        var list = try std.ArrayList(Expr).initCapacity(mem, 1024);
        errdefer list.deinit();
        var next = self;
        while (true) {
            switch (next) {
                .FuncRef => |f| if (f == @enumToInt(StdFunc.Nil))
                    return list.toOwnedSlice(),
                .Call => |c| if (c.Args.len == 2) switch (c.Callee) {
                    .FuncRef => |f| if (f == @enumToInt(StdFunc.Cons)) {
                        try list.append(c.Args[1]);
                        next = c.Args[0];
                        continue;
                    },
                    else => break,
                },
                else => break,
            }
        }
        list.deinit();
        return null;
    }
};

pub fn listToBytes(mem: *std.mem.Allocator, maybeNumList: ?[]const Expr) !?[]const u8 {
    if (maybeNumList) |it| {
        var ok = false;
        const bytes = try mem.alloc(u8, it.len);
        defer if (!ok) mem.free(bytes);
        for (it) |expr, i| switch (expr) {
            .NumInt => |n| if (n < 0 or n > 255) return null else bytes[i] = @intCast(u8, n),
            else => return null,
        };
        ok = true;
        return bytes;
    }
    return null;
}

pub fn jsonSrc(mem: *std.mem.Allocator, prog: Prog) ![]const u8 {
    _ = try listToBytes(mem, null);
    var buf = &try std.Buffer.initCapacity(mem, 64 * 1024);
    defer buf.deinit();
    try buf.append("[ ");
    var i: usize = 0;
    while (i < prog.len) : (i += 1) {
        if (i > 0)
            try buf.append(", ");
        try prog[i].jsonSrc(buf, false);
        try buf.appendByte('\n');
    }
    try buf.append("]\n");
    return buf.toOwnedSlice();
}
