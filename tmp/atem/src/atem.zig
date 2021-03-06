const std = @import("std");
usingnamespace @import("./zutil.zig");
const atem_eval = @import("./eval.zig");

pub const LoadFromJson = @import("./load.zig").FromJson;
pub const Prog = []FuncDef;

pub var handlerForOpPrt = atem_eval.handleOpPrt;
pub var handlerForOpUnknown = atem_eval.handleOpUnknown;

pub const OpCode = enum(isize) {
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
    Args: []i8,
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
            try fmtTo(buf, "{d}", .{argused});
        }
        try buf.append("],\n\t\t");
        try self.Body.jsonSrc(buf);
        try buf.append(" ]");
    }
};

pub const ExprCall = struct {
    Callee: Expr,
    Args: []Expr,
    IsClosure: usize = 0, // u8
};

pub const Expr = union(enum) {
    NumInt: isize,
    ArgRef: isize,
    FuncRef: isize,
    Call: *ExprCall,
    Never: void,

    inline fn is(self: Expr, comptime tag: var) ?std.meta.TagPayloadType(Expr, tag) {
        return uIs(Expr, tag, self);
    }

    inline fn isnt(self: Expr, comptime tag: var) bool {
        return uIsnt(Expr, tag, self);
    }

    fn eval(self: Expr, memArena: *std.heap.ArenaAllocator, prog: Prog, big: bool) !Expr {
        var framescapacity: usize = if (!big) 64 else (32 * 1024);
        return atem_eval.eval(memArena, prog, self, framescapacity);
    }

    fn jsonSrc(self: Expr, buf: *std.Buffer) @TypeOf(std.Buffer.append).ReturnType.ErrorSet!void {
        switch (self) {
            .Never => try buf.append("null"),
            .NumInt => |n| try fmtTo(buf, "{d}", .{n}),
            .ArgRef => |a| try fmtTo(buf, "\"{d}\"", .{(-a) - 2}),
            .FuncRef => |f| try fmtTo(buf, "[{d}]", .{f}),
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
            .NumInt => |n| return n == cmp.NumInt,
            .Call => |c| {
                if (c.Args.len == cmp.Call.Args.len and c.Callee.eqTo(cmp.Call.Callee)) {
                    for (cmp.Call.Args) |_, i|
                        if (!c.Args[i].eqTo(cmp.Call.Args[i]))
                            return false;
                    return true;
                }
            },
            .ArgRef => |a| return a == cmp.ArgRef,
            .FuncRef => |f| return f == cmp.FuncRef,
            .Never => unreachable,
        };
        return false;
    }

    fn deinitFrom(self: Expr, mem: *std.mem.Allocator) void {
        switch (self) {
            .Call => |call| {
                call.Callee.deinitFrom(mem);
                for (call.Args) |argval|
                    argval.deinitFrom(mem);
                mem.free(call.Args);
                mem.destroy(call);
            },
            else => {},
        }
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
                    else => {},
                },
                else => {},
            }
            break;
        }
        list.deinit();
        return null;
    }

    fn listOfExprsToStr(self: Expr, mem: *std.mem.Allocator) ![]const u8 {
        const maybenumlist = try self.listOfExprs(mem);
        if (maybenumlist) |it| if (try listToBytes(mem, it)) |ret| return ret;
        return try toJsonSrc(mem, self);
    }
};

pub fn listToBytes(mem: *std.mem.Allocator, maybeNumList: []const Expr) !?[]const u8 {
    var ok = false;
    const bytes = try mem.alloc(u8, maybeNumList.len);
    defer if (!ok) mem.free(bytes);
    for (maybeNumList) |expr, i| switch (expr) {
        .NumInt => |n| if (n < 0 or n > 255) return null else bytes[i] = @intCast(u8, n),
        else => return null,
    };
    ok = true;
    return bytes;
}

pub fn listFrom(mem: *std.mem.Allocator, from: var) !Expr {
    var ret = Expr{ .FuncRef = @enumToInt(StdFunc.Nil) };
    var i = from.len;
    const isstr = comptime isStr(@TypeOf(from));
    while (i > 0) {
        i -= 1;
        const args = try std.mem.dupe(mem, Expr, &[_]Expr{ ret, if (isstr) (Expr{ .NumInt = from[i] }) else try listFrom(mem, from[i]) });
        ret = Expr{ .Call = try enHeap(mem, ExprCall{ .Callee = Expr{ .FuncRef = @enumToInt(StdFunc.Cons) }, .Args = args, .IsClosure = 2 }) };
    }
    return ret;
}

pub fn toJsonSrc(mem: *std.mem.Allocator, it: var) ![]const u8 {
    var buf = &try std.Buffer.initCapacity(mem, 64 * 1024);
    defer buf.deinit();
    const T = comptime @TypeOf(it);
    if (T == Expr)
        try it.jsonSrc(buf)
    else if (T == *FuncDef)
        try it.jsonSrc(buf, false)
    else if (T == FuncDef)
        try it.jsonSrc(buf, false)
    else if (T == Prog) {
        try buf.append("[ ");
        var i: usize = 0;
        while (i < it.len) : (i += 1) {
            if (i > 0)
                try buf.append(", ");
            try it[i].jsonSrc(buf, false);
            try buf.appendByte('\n');
        }
        try buf.append("]\n");
    } else
        @compileError("badly-typed arg to toJsonSrc: cannot handle " ++ @typeName(T) ++ " values");
    return buf.toOwnedSlice();
}
