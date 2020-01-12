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
    Meta: [][]u8,
    selector: u8,
    allArgsUsed: bool,
    isMereAlias: bool,
};

pub const Expr = union(enum) {
    NumInt: isize,
    ArgRef: isize,
    FuncRef: isize,
    Call: *struct {
        Callee: Expr,
        Args: []Expr,
        IsClosure: u8,
    },

    pub fn jsonSrc(self: Expr) []u8 {
        return switch (self) {
            .NumIntt => "[]",
        };
    }
};
