const std = @import("std");

pub fn eql(one: std.json.Value, two: std.json.Value) bool {
    if (std.meta.activeTag(one) == std.meta.activeTag(two)) switch (one) {
        .Null => return true,
        .Bool => |one_bool| return one_bool == two.Bool,
        .Integer => |one_int| return one_int == two.Integer,
        .Float => |one_float| return one_float == two.Float,
        .String => |one_string| return std.mem.eql(u8, one_string, two.String),

        .Array => |one_array| if (one_array.len == two.Array.len) {
            for (one_array.items[0..one_array.len]) |one_array_item, i|
                if (!eql(one_array_item, two.Array.items[i]))
                    return false;
            return true;
        },

        .Object => |one_object| if (one_object.count() == two.Object.count()) {
            var hash_map_iter = one_object.iterator();
            while (hash_map_iter.next()) |item| {
                if (two.Object.getValue(item.key)) |two_value| {
                    if (!eql(item.value, two_value)) return false;
                } else return false;
            }
            return true;
        },
    };
    return false;
}
