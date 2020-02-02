const std = @import("std");

/// json.Value equality comparison: for `.Array`s and `.Object`s, equal
/// sizes are prerequisite before further probing into their contents.
pub fn eql(self: std.json.Value, other: std.json.Value) bool {
    if (std.meta.activeTag(self) == std.meta.activeTag(other)) switch (self) {
        .Null => return true,
        .Bool => |self_bool| return self_bool == other.Bool,
        .Integer => |self_int| return self_int == other.Integer,
        .Float => |self_float| return self_float == other.Float, // TODO: reconsider if/when std.math gets a dedicated float eql
        .String => |self_string| return std.mem.eql(u8, self_string, other.String),

        .Array => |self_array| if (self_array.len == other.Array.len) {
            for (self_array.items[0..self_array.len]) |self_array_item, i|
                if (!eql(self_array_item, other.Array.items[i]))
                    return false;
            return true;
        },

        .Object => |self_object| if (self_object.count() == other.Object.count()) {
            var hash_map_iter = self_object.iterator();
            while (hash_map_iter.next()) |item| {
                if (other.Object.getValue(item.key)) |other_value| {
                    if (!eql(item.value, other_value)) return false;
                } else return false;
            }
            return true;
        },
    };
    return false;
}
