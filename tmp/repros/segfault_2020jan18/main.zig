const std = @import("std");

pub fn main() !void {
    var mem = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer mem.deinit();

    const list = try listFromStr(&mem.allocator, "Hail Zig =)");
    std.debug.warn("{s}", .{try listToStr(&mem.allocator, list)});
}

fn listFromStr(mem: *std.mem.Allocator, from: []const u8) !Expr {
    var ret = Expr{ .FuncRef = @enumToInt(StdFunc.Nil) };
    var i = from.len;
    while (i > 0) {
        i -= 1;
        ret = Expr{
            .Call = try enHeap(mem, ExprCall{
                .Callee = Expr{ .FuncRef = @enumToInt(StdFunc.Cons) },
                .Args = try std.mem.dupe(mem, Expr, &[_]Expr{
                    ret,
                    Expr{ .NumInt = from[i] },
                }),
            }),
        };
    }
    return ret;
}

fn listToStr(mem: *std.mem.Allocator, expr: Expr) !?[]const u8 {
    const maybenumlist = try maybeList(mem, expr);
    return if (maybenumlist) |it| listToBytes(mem, it) else null;
}

fn maybeList(mem: *std.mem.Allocator, self: Expr) !?[]const Expr {
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

fn listToBytes(mem: *std.mem.Allocator, maybeNumList: []const Expr) !?[]const u8 {
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

inline fn enHeap(mem: *std.mem.Allocator, it: var) !*@TypeOf(it) {
    var ret = try mem.create(@TypeOf(it));
    ret.* = it;
    return ret;
}

const ExprCall = struct {
    Callee: Expr,
    Args: []Expr,
};

const Expr = union(enum) {
    NumInt: isize,
    FuncRef: isize,
    Call: *const ExprCall,
};

const StdFunc = enum(isize) {
    Nil = 3,
    Cons = 4,
};
