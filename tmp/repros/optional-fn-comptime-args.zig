const std = @import("std");

test "" {
    main();
}

pub fn main() void {
    _ = (Options{}).isFoo;
}

pub const Options = struct {
    isFoo: fn (comptime T: type, fna: []const u8, comptime TT: type) bool = defaultIsFoo,

    pub fn defaultIsFoo(comptime struct_type: type, field_name: []const u8, comptime field_type: type) bool {
        return false;
    }
};
