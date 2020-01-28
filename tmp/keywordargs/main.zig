const std = @import("std");

pub fn main() void {
    var sess = Protocol(.{}){};
    sess.serve(); // forever-loop
}

pub fn Protocol(comptime spec: struct {
    TIn: type = union(enum) {},
    TOut: type = union(enum) {},
}) type {
    return struct {
        subscribers: [@memberCount(spec.TIn)]?usize = ([_]?usize{null}) ** @memberCount(spec.TIn),
        pub fn on(self: *@This()) void {} // subscription
        pub fn serve(self: *@This()) void {} // transport-dealing forever-loop
    };
}

pub const MyIn = union(enum) {
    foo: fn (isize) bool,
    bar: fn (bool) isize,
};

pub const MyOut = union(enum) {
    baz: fn ([]u8) void,
};
