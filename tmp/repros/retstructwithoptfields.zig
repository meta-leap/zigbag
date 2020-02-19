const std = @import("std");
const Str = []const u8;

test "" {
    main();
}

pub fn main() !void {
    std.debug.warn("\n{}\n", .{(try rangesFor(&Intel.NamedDecl{
        .pos = .{
            .full = .{
                .start = 123,
                .end = 321,
            },
        },
    }, "whatever")) orelse return});
}

pub fn rangesFor(named_decl: *Intel.NamedDecl, in_src: Str) !?struct {
    full: Range = null,
    name: ?Range = null,
    brief: ?Range = null,
} {
    const TRet = @typeInfo(@typeInfo(@TypeOf(rangesFor).ReturnType).ErrorUnion.payload).Optional.child;
    var ret = TRet{
        .full = (try Range.initFromSlice(in_src, named_decl.
            pos.full.start, named_decl.pos.full.end)) orelse return null,
    };
    if (named_decl.pos.brief) |pos_brief|
        ret.brief = try Range.initFromSlice(in_src, pos_brief.start, pos_brief.end);
    if (named_decl.pos.name) |pos_name|
        ret.name = try Range.initFromSlice(in_src, pos_name.start, pos_name.end);
    return ret;
}

pub const Position = struct {
    line: isize,
    character: isize,

    pub fn fromByteIndexIn(string: Str, index: usize) !?Position {
        if (index < string.len) {
            var cur = Position{ .line = 0, .character = 0 };
            var i: usize = 0;
            while (i < string.len) {
                if (i >= index)
                    return cur;
                if (string[i] == '\n') {
                    cur.line += 1;
                    cur.character = 0;
                    i += 1;
                } else {
                    cur.character += 1;
                    i += try std.unicode.utf8ByteSequenceLength(string[i]);
                }
            }
        }
        return null;
    }

    pub fn toByteIndexIn(me: *const Position, string: Str) !?usize {
        var cur = Position{ .line = 0, .character = 0 };
        var i: usize = 0;
        while (i < string.len) {
            if (cur.line == me.line and cur.character == me.character)
                return i;
            if (string[i] == '\n') {
                cur.line += 1;
                cur.character = 0;
                i += 1;
            } else {
                cur.character += 1;
                i += try std.unicode.utf8ByteSequenceLength(string[i]);
            }
        }
        return null;
    }
};

pub const Range = struct {
    start: Position,
    end: Position,

    pub fn initFrom(string: Str) !?Range {
        if (try Position.fromByteIndexIn(string, string.len - 1)) |last_pos|
            return Range{ .start = .{ .line = 0, .character = 0 }, .end = last_pos };
        return null;
    }

    pub fn initFromSlice(string: Str, index_start: usize, index_end: usize) !?Range {
        if (try Position.fromByteIndexIn(string, index_start)) |start|
            if (try Position.fromByteIndexIn(string, index_end)) |end|
                return Range{ .start = start, .end = end };
        return null;
    }

    pub fn sliceBounds(me: *const Range, string: Str) !?[2]usize {
        var cur = Position{ .line = 0, .character = 0 };
        var idx_start: ?usize = null;
        var idx_end: ?usize = null;
        var i: usize = 0;
        while (idx_start == null or idx_end == null) {
            if (idx_end == null and cur.line == me.end.line and cur.character == me.end.character)
                idx_end = i;
            if (idx_start == null and cur.line == me.start.line and cur.character == me.start.character)
                idx_start = i;
            if (i == string.len)
                break;
            if (string[i] == '\n') {
                cur.line += 1;
                cur.character = 0;
                i += 1;
            } else {
                cur.character += 1;
                i += try std.unicode.utf8ByteSequenceLength(string[i]);
            }
        }
        if (idx_start) |i_start| {
            if (idx_end) |i_end|
                return [2]usize{ i_start, i_end };
        }
        return null;
    }

    pub fn sliceConst(me: *const Range, string: Str) !?Str {
        return if (try me.sliceBounds(string)) |start_and_end|
            string[start_and_end[0]..start_and_end[1]]
        else
            null;
    }

    pub fn sliceMut(me: *const Range, string: []u8) !?[]u8 {
        return if (try me.sliceBounds(string)) |start_and_end|
            string[start_and_end[0]..start_and_end[1]]
        else
            null;
    }
};

pub const Intel = struct {
    pub const TokPos = struct {
        start: usize,
        end: usize,
    };

    pub const NamedDecl = struct {
        pos: struct {
            full: TokPos,
            name: ?TokPos = null,
            brief: ?TokPos = null,
            brief_pref: ?TokPos = null,
            brief_suff: ?TokPos = null,
        },
    };
};
