//! Source text and line offset indices.

const std = @import("std");
const Allocator = std.mem.Allocator;

const Source = @This();

path: []const u8,
/// Externally owned.
bytes: [:0]const u8,
/// Zero-indexed line to byte offset of first character.
line_starts: []const u32,

pub fn init(gpa: Allocator, path: []const u8, bytes: [:0]const u8) Allocator.Error!Source {
    var line_starts: std.ArrayList(u32) = .empty;
    errdefer line_starts.deinit(gpa);

    try line_starts.append(gpa, 0);
    for (bytes, 0..) |byte, i| {
        // skip trailing newline
        if (byte == '\n' and i + 1 < bytes.len)
            try line_starts.append(gpa, @intCast(i + 1));
    }

    return .{
        .path = path,
        .bytes = bytes,
        .line_starts = try line_starts.toOwnedSlice(gpa),
    };
}

pub fn deinit(source: *Source, gpa: Allocator) void {
    gpa.free(source.line_starts);
    source.* = undefined;
}

pub fn lineCount(source: *const Source) u32 {
    return @intCast(source.line_starts.len);
}

pub fn lineIndex(source: *const Source, offset: u32) u32 {
    const target = @min(offset, source.bytes.len);

    var lo: u32 = 0;
    var hi: u32 = source.lineCount();
    while (hi - lo > 1) {
        const mid = lo + (hi - lo) / 2;
        if (source.line_starts[mid] <= target) lo = mid else hi = mid;
    }
    return lo;
}

/// Excludes '\n'.
pub fn lineSlice(source: *const Source, line: u32) []const u8 {
    const start = source.line_starts[line];
    const end = if (line + 1 < source.lineCount())
        source.line_starts[line + 1] - 1 // the '\n' itself
    else
        @as(u32, @intCast(source.bytes.len));

    var text = source.bytes[start..end];
    if (text.len > 0 and text[text.len - 1] == '\n') text = text[0 .. text.len - 1];
    if (text.len > 0 and text[text.len - 1] == '\r') text = text[0 .. text.len - 1];
    return text;
}

test lineSlice {
    const gpa = std.testing.allocator;
    var source: Source = try .init(gpa, "<test>", "one\ntwo\r\n\nfour");
    defer source.deinit(gpa);

    try std.testing.expectEqual(4, source.lineCount());
    try std.testing.expectEqualStrings("one", source.lineSlice(0));
    try std.testing.expectEqualStrings("two", source.lineSlice(1));
    try std.testing.expectEqualStrings("", source.lineSlice(2));
    try std.testing.expectEqualStrings("four", source.lineSlice(3));
}

test lineIndex {
    const gpa = std.testing.allocator;
    var source: Source = try .init(gpa, "<test>", "one\ntwo\nthree");
    defer source.deinit(gpa);

    try std.testing.expectEqual(0, source.lineIndex(0));
    try std.testing.expectEqual(0, source.lineIndex(3)); // '\n' is part of the previous line
    try std.testing.expectEqual(1, source.lineIndex(4));
    try std.testing.expectEqual(2, source.lineIndex(8));
    try std.testing.expectEqual(2, source.lineIndex(999));
}

test "trailing newline does not add a line" {
    const gpa = std.testing.allocator;
    var source: Source = try .init(gpa, "<test>", "one\ntwo\n");
    defer source.deinit(gpa);

    try std.testing.expectEqual(2, source.lineCount());
    try std.testing.expectEqualStrings("two", source.lineSlice(1));
    try std.testing.expectEqual(1, source.lineIndex(@intCast(source.bytes.len)));
}

test "empty source" {
    const gpa = std.testing.allocator;
    var source: Source = try .init(gpa, "<test>", "");
    defer source.deinit(gpa);

    try std.testing.expectEqual(1, source.lineCount());
    try std.testing.expectEqual(0, source.lineIndex(0));
    try std.testing.expectEqualStrings("", source.lineSlice(0));
}
