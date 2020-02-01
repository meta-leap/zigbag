const std = @import("std");

pub fn eql(j1: std.json.Value, j2: std.json.Value) bool {
    if (std.meta.activeTag(j1) == std.meta.activeTag(j2)) switch (j1) {
        .Null => return true,
        .Bool => |j1_b| return j1_b == j2.Bool,
        .Integer => |j1_i| return j1_i == j2.Integer,
        .Float => |j1_f| return j1_f == j2.Float,
        .String => |j1_s| return std.mem.eql(u8, j1_s, j2.String),

        .Array => |j1_a| if (j1_a.len == j2.Array.len) {
            for (j1_a.items[0..j1_a.len]) |item, i|
                if (!eql(item, j2.Array.items[i]))
                    return false;
            return true;
        },

        .Object => |j1_o| if (j1_o.count() == j2.Object.count()) {
            var hash_map_iter = j1_o.iterator();
            while (hash_map_iter.next()) |item| {
                if (j2.Object.getValue(item.key)) |j2_value| {
                    if (!eql(item.value, j2_value)) return false;
                } else return false;
            }
            return true;
        },
    };
    return false;
}
