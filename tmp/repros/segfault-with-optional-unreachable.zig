const std = @import("std");

test "" {
    main();
}

pub fn main() void {
    incomingRepro(@intCast(usize, std.time.milliTimestamp()));
}

pub fn incomingRepro(foo: usize) void {
    var msg: struct {
        result_ok: ?*std.json.Value = null,
        result_err: ?ResponseError = null,
    } = .{};

    inline for (@typeInfo(RequestOut).Union.fields) |*spec_field, idx| {
        if (foo == idx) {
            const TResponse = @typeInfo(@typeInfo(spec_field.field_type).Fn.return_type.?).Union.fields[0].field_type;
            const fn_arg = if (msg.result_err) |err|
                Ret(TResponse){ .err = err }
            else if (msg.result_ok) |ret|
                Ret(TResponse){ .ok = undefined }
            else
                unreachable;
        }
    }
}

pub const ResponseError = struct {
    code: isize,
    message: []const u8,
};

pub const RequestOut = union(enum) {
    pow2: fn (Arg(i64)) Ret(i64),
    rnd: fn (Arg(void)) Ret(f32),
    add: fn (Arg(?struct {
        a: i64,
        b: i64,
    })) Ret(?i64),
};

pub fn Arg(comptime T: type) type {
    return struct {
        it: T,
    };
}

pub fn Ret(comptime T: type) type {
    return union(enum) {
        ok: T,
        err: ResponseError,
    };
}
