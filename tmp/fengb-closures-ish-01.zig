// contributed by github.com/fengb to #zig irc chan on 13 Feb 2020

const any = @OpaqueType();

fn Closure(comptime Return: type) type {
    return struct {
        const ClosureType = @This();
        callFn: fn (ctx: *const any) Return,

        pub fn call(self: ClosureType) Return {
            return self.callFn(@ptrCast(*const any, &self));
        }

        pub fn bind(func: var, args: var) Context(@TypeOf(func), @TypeOf(args)) {
            return Context(@TypeOf(func), @TypeOf(args)).init(func, args);
        }

        fn Context(comptime Func: type, comptime Args: type) type {
            return struct {
                const ContextType = @This();

                closure: ClosureType,
                func: Func,
                args: Args,

                fn init(func: Func, args: Args) ContextType {
                    return .{
                        .closure = .{ .callFn = closureCall },
                        .func = func,
                        .args = args,
                    };
                }

                fn closureCall(closure: *const any) Return {
                    const reified = @ptrCast(*const ClosureType, @alignCast(@alignOf(ClosureType), closure));
                    const self = @fieldParentPtr(ContextType, "closure", reified);
                    return @call(.{}, self.func, self.args);
                }
            };
        }
    };
}

fn add(a: usize, b: usize) usize {
    return a + b;
}

const std = @import("std");
pub fn main() void {
    var now = @as(usize, std.time.milliTimestamp());
    const ctx1 = Closure(usize).bind(add, .{ @as(usize, std.time.milliTimestamp()), now / 2 });
    const ctx2 = Closure(usize).bind(add, .{ now * 2, @as(usize, std.time.milliTimestamp()) });

    const closures = [_]*const Closure(usize){ &ctx1.closure, &ctx2.closure };
    runAll(closures[0..]);
}

fn runAll(closures: []const *const Closure(usize)) void {
    for (closures) |closure| {
        std.debug.warn("{}\n", .{closure.call()});
    }
}
