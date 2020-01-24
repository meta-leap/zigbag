const std = @import("std");

pub const Uri = struct {
    scheme: ?[]const u8 = null,
    authority: []const u8,
    path: ?[]const u8 = null,
    query: ?[]const u8 = null,
    fragment: ?[]const u8 = null,

    pub fn init(uri: []const u8) Uri {
        var it = Uri{ .authority = uri };
        if (std.mem.indexOfScalar(u8, it.authority, '#')) |idx| {
            it.fragment = it.authority[idx + 1 ..];
            it.authority = it.authority[0..idx];
        }
        if (std.mem.indexOfScalar(u8, it.authority, '?')) |idx| {
            it.query = it.authority[idx + 1 ..];
            it.authority = it.authority[0..idx];
        }
        if (std.mem.indexOf(u8, it.authority, "://")) |idx| {
            it.scheme = it.authority[0..idx];
            it.authority = it.authority[idx + 3 ..];
        }
        if (std.mem.indexOfScalar(u8, it.authority, '/')) |idx| {
            it.path = it.authority[idx..];
            it.authority = it.authority[0..idx];
        }
        return it;
    }
};
