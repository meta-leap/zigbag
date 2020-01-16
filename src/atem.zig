const std = @import("std");
const zut = @import("./zutil.zig");

pub const load = @import("./load.zig");

pub const Prog = []FuncDef;

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

pub const StdFunc = enum {
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

    inline fn jsonSrc(self: *FuncDef, buf: *std.Buffer) @TypeOf(std.Buffer.append).ReturnType.ErrorSet!void {}
};

pub const Expr = union(enum) {
    NumInt: isize,
    ArgRef: isize,
    FuncRef: isize,
    Call: *ExprCall,
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
                var i = c.Args.len - 1;
                while (i > -1) : (i -= 1) {
                    try buf.append(", ");
                    try c.Args[i].jsonSrc(buf);
                }
                try buf.appendByte(']');
            },
        }
    }
};

pub const ExprCall = struct {
    Callee: Expr,
    Args: []Expr,
    IsClosure: u8 = 0,
};

pub fn jsonSrc(mem: *std.mem.Allocator, prog: Prog) ![]const u8 {
    var buf = &try std.Buffer.initCapacity(mem, 64 * 1024);
    defer buf.deinit();
    try buf.appendByte('[');
    var i: usize = 0;
    while (i < prog.len) : (i += 1) {
        if (i > 0)
            try buf.append(", ");
        try prog[i].jsonSrc(buf);
    }
    try buf.append("]\n");
    return buf.toOwnedSlice();
}
