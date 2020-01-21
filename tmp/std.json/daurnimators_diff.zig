fn checkField(comptime field_name: []const u8, source_slice: []const u8) bool {
    var j: usize = 0;
    for (field_name) |c| {
        if (source_slice[j] != '\\') {
            if (c != source_slice[j]) return false;
            j += 1;
        } else if (source_slice[j + 1] != 'u') {
            const t: u8 = switch (source_slice[j + 1]) {
                '\\' => '\\',
                '/' => '/',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                'f' => 12,
                'b' => 8,
                '"' => '"',
                else => unreachable,
            };
            if (c != t) return false;
            j += 2;
        } else {
            @panic("TODO");
        }
    }
    assert(j == source_slice.len);
    return true;
}

pub const ParseOptions = struct {
    allocator: ?*Allocator = null,

    /// Behaviour when a duplicate field is encountered
    onDuplicateField: enum {
        UseFirst,
        Error,
        UseLast,
    } = .UseLast,
};

fn parseInternal(comptime T: type, token: Token, tokens: *TokenStream, options: ParseOptions) !T {
    switch (@typeInfo(T)) {
        .Bool => {
            return switch (token) {
                .True => true,
                .False => false,
                else => error.UnexpectedToken,
            };
        },
        .Float, .ComptimeFloat => {
            const numberToken = switch (token) {
                .Number => |n| n,
                else => return error.UnexpectedToken,
            };
            return try std.fmt.parseFloat(T, numberToken.slice(tokens.slice, tokens.i - 1));
        },
        .Int, .ComptimeInt => {
            const numberToken = switch (token) {
                .Number => |n| n,
                else => return error.UnexpectedToken,
            };
            if (!numberToken.is_integer) return error.UnexpectedToken;
            return try std.fmt.parseInt(T, numberToken.slice(tokens.slice, tokens.i - 1), 10);
        },
        .Optional => |optionalInfo| {
            if (token == .Null) {
                return null;
            } else {
                return try parseInternal(optionalInfo.child, token, tokens, options);
            }
        },
        .Enum => |enumInfo| {
            switch (token) {
                .Number => |numberToken| {
                    if (!numberToken.is_integer) return error.UnexpectedToken;
                    const n = try std.fmt.parseInt(enumInfo.tag_type, numberToken.slice(tokens.slice, tokens.i - 1), 10);
                    return try std.meta.intToEnum(T, n);
                },
                .String => |stringToken| {
                    const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                    switch (stringToken.escapes) {
                        .None => return std.meta.stringToEnum(T, source_slice) orelse return error.InvalidEnumTag,
                        .Some => {
                            inline for (enumInfo.fields) |field| {
                                if (field.name.len == stringToken.decodedLength() and checkField(field.name, source_slice)) {
                                    return @field(T, field.name);
                                }
                            }
                            return error.InvalidEnumTag;
                        },
                    }
                },
                else => return error.UnexpectedToken,
            }
        },
        .Struct => |structInfo| {
            switch (token) {
                .ObjectBegin => {},
                else => return error.UnexpectedToken,
            }
            var r: T = undefined;
            var fields_seen = [_]bool{false} ** structInfo.fields.len;
            errdefer {
                inline for (structInfo.fields) |field, i| {
                    if (fields_seen[i]) {
                        parseFree(field.field_type, @field(r, field.name), options);
                    }
                }
            }

            while (true) {
                switch ((try tokens.next()) orelse return error.UnexpectedEndOfJson) {
                    .ObjectEnd => break,
                    .String => |stringToken| {
                        const key_source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                        inline for (structInfo.fields) |field, i| {
                            if (switch (stringToken.escapes) {
                                .None => mem.eql(u8, field.name, key_source_slice),
                                .Some => (field.name.len == stringToken.decodedLength() and checkField(field.name, key_source_slice)),
                            }) {
                                if (fields_seen[i]) {
                                    // TODO using a switch here segfaults the compiler for some reason?!?
                                    // switch (options.onDuplicateField) {
                                    //     .UseFirst => {},
                                    //     .Error => {},
                                    //     .UseLast => {},
                                    // }
                                    if (options.onDuplicateField == .UseFirst) {
                                        break;
                                    } else if (options.onDuplicateField == .Error) {
                                        return error.DuplicateJSONField;
                                    } else if (options.onDuplicateField == .UseLast) {
                                        parseFree(field.field_type, @field(r, field.name), options);
                                    }
                                }
                                @field(r, field.name) = try parse(field.field_type, tokens, options);
                                fields_seen[i] = true;
                                break;
                            }
                        }
                    },
                    else => return error.UnexpectedToken,
                }
            }
            for (fields_seen) |seen| {
                // TODO: don't error if field has default value
                if (!seen) return error.MissingField;
            }
            return r;
        },
        .Array => |arrayInfo| {
            switch (token) {
                .ArrayBegin => {
                    var r: T = undefined;
                    var i: usize = 0;
                    errdefer {
                        while (true) : (i -= 1) {
                            parseFree(arrayInfo.child, r[i], options);
                            if (i == 0) break;
                        }
                    }
                    while (i < r.len) : (i += 1) {
                        r[i] = try parse(arrayInfo.child, tokens, options);
                    }
                    const tok = (try tokens.next()) orelse return error.UnexpectedEndOfJson;
                    switch (tok) {
                        .ArrayEnd => {},
                        else => return error.UnexpectedToken,
                    }
                    return r;
                },
                .String => |stringToken| {
                    if (arrayInfo.child != u8) return error.UnexpectedToken;
                    var r: T = undefined;
                    const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                    switch (stringToken.escapes) {
                        .None => mem.copy(u8, &r, source_slice),
                        .Some => try unescapeString(&r, source_slice),
                    }
                    return r;
                },
                else => return error.UnexpectedToken,
            }
        },
        .Pointer => |ptrInfo| {
            const allocator = options.allocator orelse return error.AllocatorRequired;
            switch (ptrInfo.size) {
                .One => {
                    const r: T = allocator.create(ptrInfo.child);
                    r.* = try parseInternal(ptrInfo.child, token, tokens, options);
                    return r;
                },
                .Slice => {
                    switch (token) {
                        .ArrayBegin => {
                            var arraylist = std.ArrayList(ptrInfo.child).init(allocator);
                            errdefer {
                                while (arraylist.popOrNull()) |v| {
                                    parseFree(ptrInfo.child, v, options);
                                }
                                arraylist.deinit();
                            }

                            while (true) {
                                const tok = (try tokens.next()) orelse return error.UnexpectedEndOfJson;
                                switch (tok) {
                                    .ArrayEnd => break,
                                    else => {},
                                }

                                try arraylist.ensureCapacity(arraylist.len + 1);
                                const v = try parseInternal(ptrInfo.child, tok, tokens, options);
                                arraylist.appendAssumeCapacity(v);
                            }
                            return arraylist.toOwnedSlice();
                        },
                        .String => |stringToken| {
                            if (ptrInfo.child != u8) return error.UnexpectedToken;
                            const source_slice = stringToken.slice(tokens.slice, tokens.i - 1);
                            switch (stringToken.escapes) {
                                .None => return mem.dupe(allocator, u8, source_slice),
                                .Some => |some_escapes| {
                                    const output = try allocator.alloc(u8, stringToken.decodedLength());
                                    errdefer allocator.free(output);
                                    try unescapeString(output, source_slice);
                                    return output;
                                },
                            }
                        },
                        else => return error.UnexpectedToken,
                    }
                },
                else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
            }
        },
        else => @compileError("Unable to parse into type '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}

pub fn parse(comptime T: type, tokens: *TokenStream, options: ParseOptions) !T {
    const token = (try tokens.next()) orelse return error.UnexpectedEndOfJson;
    return parseInternal(T, token, tokens, options);
}

pub fn parseFree(comptime T: type, value: T, options: ParseOptions) void {
    switch (@typeInfo(T)) {
        .Bool, .Float, .ComptimeFloat, .Int, .ComptimeInt, .Enum => {},
        .Optional => {
            if (value) |v| {
                return parseFree(@TypeOf(v), v, options);
            }
        },
        .Struct => |structInfo| {
            inline for (structInfo.fields) |field| {
                parseFree(field.field_type, @field(value, field.name), options);
            }
        },
        .Array => |arrayInfo| {
            for (value) |v| {
                parseFree(arrayInfo.child, v, options);
            }
        },
        .Pointer => |ptrInfo| {
            const allocator = options.allocator orelse unreachable;
            switch (ptrInfo.size) {
                .One => {
                    parseFree(ptrInfo.child, value.*, options);
                    allocator.destroy(v);
                },
                .Slice => {
                    for (value) |v| {
                        parseFree(ptrInfo.child, v, options);
                    }
                    allocator.free(value);
                },
                else => unreachable,
            }
        },
        else => unreachable,
    }
}

// TODO: numbers shouldn't need a space after them

test "parse" {
    testing.expectEqual(false, try parse(bool, &TokenStream.init("false"), ParseOptions{}));
    testing.expectEqual(true, try parse(bool, &TokenStream.init("true"), ParseOptions{}));
    testing.expectEqual(@as(u1, 1), try parse(u1, &TokenStream.init("1 "), ParseOptions{}));
    testing.expectError(error.Overflow, parse(u1, &TokenStream.init("50 "), ParseOptions{}));
    testing.expectEqual(@as(u64, 42), try parse(u64, &TokenStream.init("42 "), ParseOptions{}));
    testing.expectEqual(@as(f64, 42), try parse(f64, &TokenStream.init("42.0 "), ParseOptions{}));
    testing.expectEqual(@as(?bool, null), try parse(?bool, &TokenStream.init("null"), ParseOptions{}));
    testing.expectEqual(@as(?bool, true), try parse(?bool, &TokenStream.init("true"), ParseOptions{}));

    testing.expectEqual(@as([3]u8, "foo".*), try parse([3]u8, &TokenStream.init("\"foo\""), ParseOptions{}));
    testing.expectEqual(@as([3]u8, "foo".*), try parse([3]u8, &TokenStream.init("[102, 111, 111]"), ParseOptions{}));
}

test "parse into enum" {
    const T = extern enum {
        Foo = 42,
        Bar,
        @"with\\escape",
    };
    testing.expectEqual(@as(T, .Foo), try parse(T, &TokenStream.init("\"Foo\""), ParseOptions{}));
    testing.expectEqual(@as(T, .Foo), try parse(T, &TokenStream.init("42 "), ParseOptions{}));
    testing.expectEqual(@as(T, .@"with\\escape"), try parse(T, &TokenStream.init("\"with\\\\escape\""), ParseOptions{}));
    testing.expectError(error.InvalidEnumTag, parse(T, &TokenStream.init("5 "), ParseOptions{}));
    testing.expectError(error.InvalidEnumTag, parse(T, &TokenStream.init("\"Qux\""), ParseOptions{}));
}

test "parse into that allocates a slice" {
    testing.expectError(error.AllocatorRequired, parse([]u8, &TokenStream.init("\"foo\""), ParseOptions{}));

    const options = ParseOptions{ .allocator = debug.global_allocator };
    {
        const r = try parse([]u8, &TokenStream.init("\"foo\""), options);
        defer parseFree([]u8, r, options);
        testing.expectEqualSlices(u8, "foo", r);
    }
    {
        const r = try parse([]u8, &TokenStream.init("[102, 111, 111]"), options);
        defer parseFree([]u8, r, options);
        testing.expectEqualSlices(u8, "foo", r);
    }
    {
        const r = try parse([]u8, &TokenStream.init("\"with\\\\escape\""), options);
        defer parseFree([]u8, r, options);
        testing.expectEqualSlices(u8, "with\\escape", r);
    }
}

test "parse into struct with no fields" {
    const T = struct {};
    testing.expectEqual(T{}, try parse(T, &TokenStream.init("{}"), ParseOptions{}));
}

test "parse into struct with misc fields" {
    const options = ParseOptions{ .allocator = debug.global_allocator };
    const T = struct {
        int: i64,
        float: f64,
        @"with\\escape": bool,
        language: []const u8,
        optional: ?bool,
        array: []f64,

        const Bar = struct {
            nested: []const u8,
        };
        complex: Bar,

        const Baz = struct {
            foo: []const u8,
        };
        veryComplex: []Baz,
    };
    const r = try parse(T, &TokenStream.init(
        \\{
        \\  "int": 420,
        \\  "float": 3.14,
        \\  "with\\escape": true,
        \\  "language": "zig",
        \\  "optional": null,
        \\  "array": [66.6, 420.420, 69.69],
        \\  "complex": {
        \\    "nested": "zig"
        \\  },
        \\  "veryComplex": [
        \\    {
        \\      "foo": "zig"
        \\    }, {
        \\      "foo": "rocks"
        \\    }
        \\  ]
        \\}
    ), options);
    defer parseFree(T, r, options);
    testing.expectEqual(@as(i64, 420), r.int);
    testing.expectEqual(@as(f64, 3.14), r.float);
    testing.expectEqual(true, r.@"with\\escape");
    testing.expectEqualSlices(u8, "zig", r.language);
    testing.expectEqual(@as(?bool, null), r.optional);
    testing.expectEqualSlices(u8, r.complex.nested, "zig");
    testing.expectEqual(@as(f64, 66.6), r.array[0]);
    testing.expectEqual(@as(f64, 420.420), r.array[1]);
    testing.expectEqual(@as(f64, 69.69), r.array[2]);
    testing.expectEqualSlices(u8, "zig", r.veryComplex[0].foo);
    testing.expectEqualSlices(u8, "rocks", r.veryComplex[1].foo);
}

pub const JsonDumpOptions = struct {
    // TODO: indentation options?
    // TODO: make escaping '/' in strings optional?
    // TODO: allow picking if []u8 is string or array?
};

pub fn dump(
    value: var,
    options: JsonDumpOptions,
    context: var,
    comptime Errors: type,
    output: fn (@TypeOf(context), []const u8) Errors!void,
) Errors!void {
    const T = @TypeOf(value);
    switch (@typeInfo(T)) {
        .Float, .ComptimeFloat => {
            return std.fmt.formatFloatScientific(value, std.fmt.FormatOptions{}, context, Errors, output);
        },
        .Int, .ComptimeInt => {
            return std.fmt.formatIntValue(value, "", std.fmt.FormatOptions{}, context, Errors, output);
        },
        .Bool => {
            return output(context, if (value) "true" else "false");
        },
        .Optional => {
            if (value) |payload| {
                return try dump(payload, options, context, Errors, output);
            } else {
                return output(context, "null");
            }
        },
        .Enum => {
            if (comptime std.meta.trait.hasFn("jsonDump")(T)) {
                return value.jsonDump(options, context, Errors, output);
            }

            @compileError("Unable to dump enum '" ++ @typeName(T) ++ "'");
        },
        .Union => {
            if (comptime std.meta.trait.hasFn("jsonDump")(T)) {
                return value.jsonDump(options, context, Errors, output);
            }

            const info = @typeInfo(T).Union;
            if (info.tag_type) |UnionTagType| {
                inline for (info.fields) |u_field| {
                    if (@enumToInt(@as(UnionTagType, value)) == u_field.enum_field.?.value) {
                        return try dump(@field(value, u_field.name), options, context, Errors, output);
                    }
                }
            } else {
                @compileError("Unable to dump untagged union '" ++ @typeName(T) ++ "'");
            }
        },
        .Struct => |S| {
            if (comptime std.meta.trait.hasFn("jsonDump")(T)) {
                return value.jsonDump(options, context, Errors, output);
            }

            try output(context, "{");
            comptime var field_output = false;
            inline for (S.fields) |Field, field_i| {
                // don't include void fields
                if (Field.field_type == void) continue;

                if (!field_output) {
                    field_output = true;
                } else {
                    try output(context, ",");
                }

                try dump(Field.name, options, context, Errors, output);
                try output(context, ":");
                try dump(@field(value, Field.name), options, context, Errors, output);
            }
            try output(context, "}");
            return;
        },
        .Pointer => |ptr_info| switch (ptr_info.size) {
            .One => {
                // TODO: avoid loops?
                return try dump(value.*, options, context, Errors, output);
            },
            // TODO: .Many when there is a sentinel (waiting for https://github.com/ziglang/zig/pull/3972)
            .Slice => {
                if (ptr_info.child == u8 and std.unicode.utf8ValidateSlice(value)) {
                    try output(context, "\"");
                    var i: usize = 0;
                    while (i < value.len) : (i += 1) {
                        switch (value[i]) {
                            // normal ascii characters
                            0x20...0x21, 0x23...0x2E, 0x30...0x5B, 0x5D...0x7F => try output(context, value[i .. i + 1]),
                            // control characters with short escapes
                            '\\' => try output(context, "\\\\"),
                            '\"' => try output(context, "\\\""),
                            '/' => try output(context, "\\/"),
                            0x8 => try output(context, "\\b"),
                            0xC => try output(context, "\\f"),
                            '\n' => try output(context, "\\n"),
                            '\r' => try output(context, "\\r"),
                            '\t' => try output(context, "\\t"),
                            else => {
                                const ulen = std.unicode.utf8ByteSequenceLength(value[i]) catch unreachable;
                                const codepoint = std.unicode.utf8Decode(value[i .. i + ulen]) catch unreachable;
                                if (codepoint <= 0xFFFF) {
                                    // If the character is in the Basic Multilingual Plane (U+0000 through U+FFFF),
                                    // then it may be represented as a six-character sequence: a reverse solidus, followed
                                    // by the lowercase letter u, followed by four hexadecimal digits that encode the character's code point.
                                    try output(context, "\\u");
                                    try std.fmt.formatIntValue(codepoint, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, context, Errors, output);
                                } else {
                                    // To escape an extended character that is not in the Basic Multilingual Plane,
                                    // the character is represented as a 12-character sequence, encoding the UTF-16 surrogate pair.
                                    const high = @intCast(u16, (codepoint - 0x10000) >> 10) + 0xD800;
                                    const low = @intCast(u16, codepoint & 0x3FF) + 0xDC00;
                                    try output(context, "\\u");
                                    try std.fmt.formatIntValue(high, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, context, Errors, output);
                                    try output(context, "\\u");
                                    try std.fmt.formatIntValue(low, "x", std.fmt.FormatOptions{ .width = 4, .fill = '0' }, context, Errors, output);
                                }
                                i += ulen - 1;
                            },
                        }
                    }
                    try output(context, "\"");
                    return;
                }

                try output(context, "[");
                for (value) |x, i| {
                    if (i != 0) {
                        try output(context, ",");
                    }
                    try dump(x, options, context, Errors, output);
                }
                try output(context, "]");
                return;
            },
            else => @compileError("Unable to dump type '" ++ @typeName(T) ++ "'"),
        },
        .Array => |info| {
            return try dump(value[0..], options, context, Errors, output);
        },
        else => @compileError("Unable to dump type '" ++ @typeName(T) ++ "'"),
    }
    unreachable;
}

fn testDump(expected: []const u8, value: var) !void {
    const TestDumpContext = struct {
        expected_remaining: []const u8,
        fn testDumpWrite(context: *@This(), bytes: []const u8) !void {
            if (context.expected_remaining.len < bytes.len) {
                std.debug.warn(
                    \\====== expected this output: =========
                    \\{}
                    \\======== instead found this: =========
                    \\{}
                    \\======================================
                , .{
                    context.expected_remaining,
                    bytes,
                });
                return error.TooMuchData;
            }
            if (!mem.eql(u8, context.expected_remaining[0..bytes.len], bytes)) {
                std.debug.warn(
                    \\====== expected this output: =========
                    \\{}
                    \\======== instead found this: =========
                    \\{}
                    \\======================================
                , .{
                    context.expected_remaining[0..bytes.len],
                    bytes,
                });
                return error.DifferentData;
            }
            context.expected_remaining = context.expected_remaining[bytes.len..];
        }
    };
    var buf: [100]u8 = undefined;
    var context = TestDumpContext{ .expected_remaining = expected };
    try dump(value, JsonDumpOptions{}, &context, error{
        TooMuchData,
        DifferentData,
    }, TestDumpContext.testDumpWrite);
    if (context.expected_remaining.len > 0) return error.NotEnoughData;
}

test "dump basic types" {
    try testDump("false", false);
    try testDump("true", true);
    try testDump("null", @as(?u8, null));
    try testDump("null", @as(?*u32, null));
    try testDump("42", 42);
    try testDump("4.2e+01", 42.0);
    try testDump("42", @as(u8, 42));
    try testDump("42", @as(u128, 42));
    try testDump("4.2e+01", @as(f32, 42));
    try testDump("4.2e+01", @as(f64, 42));
}

test "dump string" {
    try testDump("\"hello\"", "hello");
    try testDump("\"with\\nescapes\\r\"", "with\nescapes\r");
    try testDump("\"with unicode\\u0001\"", "with unicode\u{1}");
    try testDump("\"with unicode\\u0080\"", "with unicode\u{80}");
    try testDump("\"with unicode\\u00ff\"", "with unicode\u{FF}");
    try testDump("\"with unicode\\u0100\"", "with unicode\u{100}");
    try testDump("\"with unicode\\u0800\"", "with unicode\u{800}");
    try testDump("\"with unicode\\u8000\"", "with unicode\u{8000}");
    try testDump("\"with unicode\\ud799\"", "with unicode\u{D799}");
    try testDump("\"with unicode\\ud800\\udc00\"", "with unicode\u{10000}");
    try testDump("\"with unicode\\udbff\\udfff\"", "with unicode\u{10FFFF}");
}

test "dump tagged unions" {
    try testDump("42", union(enum) {
        Foo: u32,
        Bar: bool,
    }{ .Foo = 42 });
}

test "dump struct" {
    try testDump("{\"foo\":42}", struct {
        foo: u32,
    }{ .foo = 42 });
}

test "dump struct with void field" {
    try testDump("{\"foo\":42}", struct {
        foo: u32,
        bar: void = {},
    }{ .foo = 42 });
}

test "dump array of structs" {
    const MyStruct = struct {
        foo: u32,
    };
    try testDump("[{\"foo\":42},{\"foo\":100},{\"foo\":1000}]", [_]MyStruct{
        MyStruct{ .foo = 42 },
        MyStruct{ .foo = 100 },
        MyStruct{ .foo = 1000 },
    });
}

test "dump struct with custom dumper" {
    try testDump("[\"something special\",42]", struct {
        foo: u32,
        const Self = @This();
        pub fn jsonDump(
            value: Self,
            options: JsonDumpOptions,
            context: var,
            comptime Errors: type,
            output: fn (@TypeOf(context), []const u8) Errors!void,
        ) !void {
            try output(context, "[\"something special\",");
            try dump(42, options, context, Errors, output);
            try output(context, "]");
        }
    }{ .foo = 42 });
}
