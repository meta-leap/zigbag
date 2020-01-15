const std = @import("std");

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
};

pub const Expr = union(enum) {
    NumInt: isize,
    ArgRef: isize,
    FuncRef: isize,
    Call: *ExprCall,

    pub inline fn is(self: Expr, comptime tag: var) ?(std.meta.TagPayloadType(Expr, tag)) {
        switch (self) {
            else => return null,
            tag => |ok| return ok,
        }
    }

    pub inline fn isnt(self: Expr, comptime tag: var) bool {
        return switch (self) {
            tag => false,
            else => true,
        };
    }

    pub fn jsonSrc(self: Expr) []const u8 {
        return "[]";
    }
};

pub const ExprCall = struct {
    Callee: Expr,
    Args: []const Expr,
    IsClosure: u8 = 0,
};
